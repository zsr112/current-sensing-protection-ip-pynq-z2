"""Reusable MMIO interface for the current-sensing protection IP."""

from dataclasses import dataclass
from enum import Enum

try:
    from sw.generated.protection_register_map import *
    from sw.generated.protection_register_map import __all__ as _REGISTER_MAP_EXPORTS
except ModuleNotFoundError:
    from generated.protection_register_map import *
    from generated.protection_register_map import __all__ as _REGISTER_MAP_EXPORTS


__all__ = [
    *_REGISTER_MAP_EXPORTS,
    "ProtectionSnapshot",
    "ObservabilitySnapshot",
    "FeatureState",
    "ProtectionIPInterfaceError",
    "UnsupportedFeatureError",
    "IndeterminateFeatureError",
    "IncompatibleRegisterMapError",
    "RegisterMapVersion",
    "RegisterMapCapabilities",
    "PolicyStatus",
    "FaultBitmapValue",
    "apply_demo_configuration",
    "disable_pwm",
    "clear_fault_request",
    "read_status",
    "read_observability",
    "clear_observability_status",
    "read_register_map_version",
    "read_capabilities",
    "is_armed",
    "startup_ready",
    "read_policy_status",
    "read_first_fault_bitmap",
    "read_live_fault_bitmap",
    "read_fault_seen_bitmap",
    "read_policy_evaluation_identity",
    "recovery_is_verified",
    "recover_after_external_safety_confirmation",
    "enable_pwm_after_recovery",
]

RECOVERY_TIMEOUT_POLLS = 1000


class FeatureState(Enum):
    """Public feature discovery state."""

    PRESENT = "PRESENT"
    ABSENT = "ABSENT"
    UNKNOWN = "UNKNOWN"


class ProtectionIPInterfaceError(RuntimeError):
    """Base class for typed public-interface failures."""


class UnsupportedFeatureError(ProtectionIPInterfaceError):
    """The device explicitly reports that a requested feature is absent."""

    def __init__(self, feature):
        self.feature = feature
        super().__init__(f"unsupported feature: {feature}")


class IndeterminateFeatureError(ProtectionIPInterfaceError):
    """Legacy discovery cannot prove whether a requested feature exists."""

    def __init__(self, feature):
        self.feature = feature
        super().__init__(f"feature support is indeterminate: {feature}")


class IncompatibleRegisterMapError(ProtectionIPInterfaceError):
    """Explicit register-map metadata is malformed or incompatible."""


@dataclass(frozen=True)
class RegisterMapVersion:
    raw_value: int
    magic: int
    major: int
    minor: int

    @property
    def explicit(self):
        return self.raw_value != 0


@dataclass(frozen=True)
class RegisterMapCapabilities:
    version: RegisterMapVersion
    raw_capabilities_0: int | None
    raw_capabilities_1: int | None
    armed_ready: FeatureState
    fault_bitmaps: FeatureState
    clear_level_status: FeatureState
    stage2g_policy: FeatureState
    normalized_telemetry: FeatureState
    stage2e_transaction_observability: FeatureState
    policy_evaluation_identity: FeatureState
    fault_bitmap_width: int | None
    implemented_sequence_width: int | None
    minimum_sequence_width: int | None
    maximum_sequence_width: int | None


@dataclass(frozen=True)
class PolicyStatus:
    raw_value: int
    armed_ready: bool
    fault_latched_state: bool
    reset_wait_state: bool
    clear_pending: bool
    post_clear_recovery_pending: bool


@dataclass(frozen=True)
class FaultBitmapValue:
    raw_value: int
    known_flags: FaultCause
    unknown_mask: int
    advertised_width: int


@dataclass(frozen=True)
class ProtectionSnapshot:
    """Single readout of the active protection interface state."""

    ctrl: int
    status: int
    fault_code: int
    i_ch1: int
    i_ch2: int


@dataclass(frozen=True)
class ObservabilitySnapshot:
    """Eventually consistent transaction-integrity telemetry.

    Source-domain fields pass through independent Gray-counter CDC paths.
    A returned object is convenient software grouping, not a hardware-atomic
    multi-register snapshot.
    """

    capability: int
    status: int
    source_accept_count: int
    destination_delivery_count: int
    backpressure_cycle_count: int
    source_protocol_violation_count: int
    source_drop_count: int
    fifo_overflow_attempt_count: int
    fifo_underflow_attempt_count: int
    duplicate_delivery_count: int
    sequence_gap_count: int
    reorder_or_stale_count: int
    aggregate_error_count: int
    last_source_sequence: int
    last_destination_sequence: int


def _read_word(mmio, offset):
    return int(mmio.read(offset)) & 0xFFFF_FFFF


def _field_value(value, mask, lsb):
    return (value & mask) >> lsb


def read_register_map_version(mmio):
    raw_value = _read_word(mmio, REG_REGISTER_MAP_VERSION)
    if raw_value == 0:
        return RegisterMapVersion(0, 0, 0, 0)

    version = RegisterMapVersion(
        raw_value=raw_value,
        magic=_field_value(
            raw_value,
            REGISTER_MAP_VERSION_MAGIC_MASK,
            REGISTER_MAP_VERSION_MAGIC_LSB,
        ),
        major=_field_value(
            raw_value,
            REGISTER_MAP_VERSION_ABI_MAJOR_MASK,
            REGISTER_MAP_VERSION_ABI_MAJOR_LSB,
        ),
        minor=_field_value(
            raw_value,
            REGISTER_MAP_VERSION_ABI_MINOR_MASK,
            REGISTER_MAP_VERSION_ABI_MINOR_LSB,
        ),
    )
    if version.magic != REGISTER_MAP_VERSION_MAGIC_RESET:
        raise IncompatibleRegisterMapError(
            f"unexpected register-map magic 0x{version.magic:04X}"
        )
    if version.major != REGISTER_MAP_VERSION_ABI_MAJOR_RESET:
        raise IncompatibleRegisterMapError(
            f"unsupported register-map ABI major {version.major}"
        )
    return version


def _legacy_stage2e_observability_present(value):
    sequence_width = _field_value(
        value,
        OBS_CAPABILITY_SEQUENCE_WIDTH_MASK,
        OBS_CAPABILITY_SEQUENCE_WIDTH_LSB,
    )
    expected = (
        OBS_CAPABILITY_DEFAULT & ~OBS_CAPABILITY_SEQUENCE_WIDTH_MASK
    ) | (
        (sequence_width << OBS_CAPABILITY_SEQUENCE_WIDTH_LSB)
        & OBS_CAPABILITY_SEQUENCE_WIDTH_MASK
    )
    return 16 <= sequence_width <= 32 and value == expected


def _feature_state(value, mask):
    return FeatureState.PRESENT if value & mask else FeatureState.ABSENT


def read_capabilities(mmio):
    version = read_register_map_version(mmio)
    if not version.explicit:
        observability = _read_word(mmio, REG_OBS_CAPABILITY)
        stage2e_state = (
            FeatureState.PRESENT
            if _legacy_stage2e_observability_present(observability)
            else FeatureState.UNKNOWN
        )
        return RegisterMapCapabilities(
            version=version,
            raw_capabilities_0=None,
            raw_capabilities_1=None,
            armed_ready=FeatureState.UNKNOWN,
            fault_bitmaps=FeatureState.UNKNOWN,
            clear_level_status=FeatureState.UNKNOWN,
            stage2g_policy=FeatureState.UNKNOWN,
            normalized_telemetry=FeatureState.UNKNOWN,
            stage2e_transaction_observability=stage2e_state,
            policy_evaluation_identity=FeatureState.UNKNOWN,
            fault_bitmap_width=None,
            implemented_sequence_width=None,
            minimum_sequence_width=None,
            maximum_sequence_width=None,
        )

    if version.minor < REGISTER_MAP_VERSION_ABI_MINOR_RESET:
        raise IncompatibleRegisterMapError(
            f"unsupported register-map ABI minor {version.minor}"
        )

    capabilities_0 = _read_word(mmio, REG_CAPABILITIES_0)
    capabilities_1 = _read_word(mmio, REG_CAPABILITIES_1)
    if capabilities_0 & CAPABILITIES_0_NORMALIZED_TELEMETRY_RESERVED_MASK:
        raise IncompatibleRegisterMapError(
            "normalized telemetry is reserved zero in the known ABI prefix"
        )
    if (
        version.minor == REGISTER_MAP_VERSION_ABI_MINOR_RESET
        and capabilities_0 & CAPABILITIES_0_RESERVED_MASK
    ):
        raise IncompatibleRegisterMapError(
            "CAPABILITIES_0 has nonzero reserved bits for ABI 1.1"
        )

    fault_bitmap_width = _field_value(
        capabilities_1,
        CAPABILITIES_1_FAULT_BITMAP_WIDTH_MASK,
        CAPABILITIES_1_FAULT_BITMAP_WIDTH_LSB,
    )
    implemented_sequence_width = _field_value(
        capabilities_1,
        CAPABILITIES_1_IMPLEMENTED_SEQUENCE_WIDTH_MASK,
        CAPABILITIES_1_IMPLEMENTED_SEQUENCE_WIDTH_LSB,
    )
    minimum_sequence_width = _field_value(
        capabilities_1,
        CAPABILITIES_1_MIN_SEQUENCE_WIDTH_MASK,
        CAPABILITIES_1_MIN_SEQUENCE_WIDTH_LSB,
    )
    maximum_sequence_width = _field_value(
        capabilities_1,
        CAPABILITIES_1_MAX_SEQUENCE_WIDTH_MASK,
        CAPABILITIES_1_MAX_SEQUENCE_WIDTH_LSB,
    )
    if not FAULT_BITMAP_WIDTH <= fault_bitmap_width <= 32:
        raise IncompatibleRegisterMapError(
            f"invalid advertised fault bitmap width {fault_bitmap_width}"
        )
    if not 16 <= implemented_sequence_width <= 32:
        raise IncompatibleRegisterMapError(
            f"invalid implemented sequence width {implemented_sequence_width}"
        )
    if minimum_sequence_width != 16 or maximum_sequence_width != 32:
        raise IncompatibleRegisterMapError(
            "invalid supported sequence-width bounds"
        )
    if not minimum_sequence_width <= implemented_sequence_width <= maximum_sequence_width:
        raise IncompatibleRegisterMapError(
            "implemented sequence width is outside advertised bounds"
        )

    return RegisterMapCapabilities(
        version=version,
        raw_capabilities_0=capabilities_0,
        raw_capabilities_1=capabilities_1,
        armed_ready=_feature_state(capabilities_0, CAPABILITIES_0_ARMED_READY),
        fault_bitmaps=_feature_state(capabilities_0, CAPABILITIES_0_FAULT_BITMAPS),
        clear_level_status=_feature_state(
            capabilities_0, CAPABILITIES_0_CLEAR_LEVEL_STATUS
        ),
        stage2g_policy=_feature_state(
            capabilities_0, CAPABILITIES_0_STAGE2G_POLICY
        ),
        normalized_telemetry=FeatureState.ABSENT,
        stage2e_transaction_observability=_feature_state(
            capabilities_0,
            CAPABILITIES_0_STAGE2E_TRANSACTION_OBSERVABILITY,
        ),
        policy_evaluation_identity=_feature_state(
            capabilities_0, CAPABILITIES_0_POLICY_EVALUATION_IDENTITY
        ),
        fault_bitmap_width=fault_bitmap_width,
        implemented_sequence_width=implemented_sequence_width,
        minimum_sequence_width=minimum_sequence_width,
        maximum_sequence_width=maximum_sequence_width,
    )


def _require_feature(capabilities, attribute, public_name):
    state = getattr(capabilities, attribute)
    if state is FeatureState.ABSENT:
        raise UnsupportedFeatureError(public_name)
    if state is FeatureState.UNKNOWN:
        raise IndeterminateFeatureError(public_name)


def _decode_policy_status(raw_value):
    known_mask = (
        POLICY_STATUS_ARMED_READY
        | POLICY_STATUS_FAULT_LATCHED_STATE
        | POLICY_STATUS_RESET_WAIT_STATE
        | POLICY_STATUS_CLEAR_PENDING
        | POLICY_STATUS_POST_CLEAR_RECOVERY_PENDING
    )
    if raw_value & ~known_mask:
        raise IncompatibleRegisterMapError("POLICY_STATUS reserved bits are nonzero")
    status = PolicyStatus(
        raw_value=raw_value,
        armed_ready=bool(raw_value & POLICY_STATUS_ARMED_READY),
        fault_latched_state=bool(raw_value & POLICY_STATUS_FAULT_LATCHED_STATE),
        reset_wait_state=bool(raw_value & POLICY_STATUS_RESET_WAIT_STATE),
        clear_pending=bool(raw_value & POLICY_STATUS_CLEAR_PENDING),
        post_clear_recovery_pending=bool(
            raw_value & POLICY_STATUS_POST_CLEAR_RECOVERY_PENDING
        ),
    )
    if sum(
        (
            status.armed_ready,
            status.fault_latched_state,
            status.reset_wait_state,
        )
    ) != 1:
        raise IncompatibleRegisterMapError(
            "POLICY_STATUS public state is not one-hot"
        )
    if status.clear_pending and not status.fault_latched_state:
        raise IncompatibleRegisterMapError(
            "POLICY_STATUS CLEAR_PENDING is outside FAULT_LATCHED_STATE"
        )
    if status.post_clear_recovery_pending and (
        not status.reset_wait_state or status.clear_pending
    ):
        raise IncompatibleRegisterMapError(
            "POLICY_STATUS post-clear relationship is invalid"
        )
    return status


def _policy_status_for_features(mmio, required_features):
    capabilities = read_capabilities(mmio)
    for attribute, public_name in required_features:
        _require_feature(capabilities, attribute, public_name)
    return _decode_policy_status(_read_word(mmio, REG_POLICY_STATUS))


def is_armed(mmio):
    return _policy_status_for_features(
        mmio,
        (
            ("armed_ready", "ARMED_READY"),
            ("stage2g_policy", "STAGE2G_POLICY"),
        ),
    ).armed_ready


def startup_ready(mmio):
    return is_armed(mmio)


def read_policy_status(mmio):
    return _policy_status_for_features(
        mmio,
        (
            ("clear_level_status", "CLEAR_LEVEL_STATUS"),
            ("stage2g_policy", "STAGE2G_POLICY"),
        ),
    )


def _read_fault_bitmap(mmio, offset):
    capabilities = read_capabilities(mmio)
    _require_feature(capabilities, "fault_bitmaps", "FAULT_BITMAPS")
    _require_feature(capabilities, "stage2g_policy", "STAGE2G_POLICY")
    width = capabilities.fault_bitmap_width
    if width is None:
        raise IndeterminateFeatureError("FAULT_BITMAP_WIDTH")
    raw_value = _read_word(mmio, offset)
    advertised_mask = 0xFFFF_FFFF if width == 32 else (1 << width) - 1
    if raw_value & ~advertised_mask:
        raise IncompatibleRegisterMapError(
            "fault bitmap has bits above its advertised width"
        )
    return FaultBitmapValue(
        raw_value=raw_value,
        known_flags=FaultCause(raw_value & FAULT_BITMAP_VALID_MASK),
        unknown_mask=raw_value & advertised_mask & ~FAULT_BITMAP_VALID_MASK,
        advertised_width=width,
    )


def read_first_fault_bitmap(mmio):
    return _read_fault_bitmap(mmio, REG_FIRST_FAULT_BITMAP)


def read_live_fault_bitmap(mmio):
    return _read_fault_bitmap(mmio, REG_LIVE_FAULT_BITMAP)


def read_fault_seen_bitmap(mmio):
    return _read_fault_bitmap(mmio, REG_FAULT_SEEN_BITMAP)


def read_policy_evaluation_identity(mmio):
    capabilities = read_capabilities(mmio)
    _require_feature(
        capabilities,
        "policy_evaluation_identity",
        "POLICY_EVALUATION_IDENTITY",
    )
    _require_feature(capabilities, "stage2g_policy", "STAGE2G_POLICY")
    return _read_word(mmio, REG_POLICY_EVALUATION_SEQUENCE)


def apply_demo_configuration(mmio):
    """Apply software demo values while keeping PWM disabled."""
    mmio.write(REG_CTRL, 0)
    mmio.write(REG_TH_OC1, 2500)
    mmio.write(REG_TH_OC2, 2500)
    mmio.write(REG_TH_DIFF, 200)
    mmio.write(REG_PWM_PERIOD, 1000)
    mmio.write(REG_PWM_DUTY, 500)


def disable_pwm(mmio):
    mmio.write(REG_CTRL, 0)
    return (mmio.read(REG_CTRL) & CTRL_PWM_ENABLE) == 0


def clear_fault_request(mmio):
    mmio.write(REG_CTRL, CTRL_CLEAR_FAULT)


def read_status(mmio):
    return ProtectionSnapshot(
        ctrl=mmio.read(REG_CTRL),
        status=mmio.read(REG_STATUS),
        fault_code=mmio.read(REG_FAULT_CODE),
        i_ch1=mmio.read(REG_I_CH1),
        i_ch2=mmio.read(REG_I_CH2),
    )


def read_observability(mmio):
    """Read reset-only counters and W1C status without side effects."""
    return ObservabilitySnapshot(
        capability=mmio.read(REG_OBS_CAPABILITY),
        status=mmio.read(REG_OBS_STATUS_W1C) & OBS_STATUS_MASK,
        source_accept_count=mmio.read(REG_OBS_SOURCE_ACCEPT_COUNT),
        destination_delivery_count=mmio.read(
            REG_OBS_DESTINATION_DELIVERY_COUNT
        ),
        backpressure_cycle_count=mmio.read(REG_OBS_BACKPRESSURE_CYCLE_COUNT),
        source_protocol_violation_count=mmio.read(
            REG_OBS_SOURCE_PROTOCOL_VIOLATION_COUNT
        ),
        source_drop_count=mmio.read(REG_OBS_SOURCE_DROP_COUNT),
        fifo_overflow_attempt_count=mmio.read(
            REG_OBS_FIFO_OVERFLOW_ATTEMPT_COUNT
        ),
        fifo_underflow_attempt_count=mmio.read(
            REG_OBS_FIFO_UNDERFLOW_ATTEMPT_COUNT
        ),
        duplicate_delivery_count=mmio.read(REG_OBS_DUPLICATE_DELIVERY_COUNT),
        sequence_gap_count=mmio.read(REG_OBS_SEQUENCE_GAP_COUNT),
        reorder_or_stale_count=mmio.read(REG_OBS_REORDER_OR_STALE_COUNT),
        aggregate_error_count=mmio.read(REG_OBS_AGGREGATE_ERROR_COUNT),
        last_source_sequence=mmio.read(REG_OBS_LAST_SOURCE_SEQUENCE),
        last_destination_sequence=mmio.read(
            REG_OBS_LAST_DESTINATION_SEQUENCE
        ),
    )


def clear_observability_status(mmio, mask=OBS_STATUS_W1C_MASK):
    """Clear selected cause bits; ANY_ERROR is a read-only aggregate."""
    mmio.write(REG_OBS_STATUS_W1C, int(mask) & OBS_STATUS_W1C_MASK)


def recovery_is_verified(snapshot):
    fault_mask = STATUS_FAULT_VALID | STATUS_FAULT_LATCHED
    return (
        (snapshot.status & fault_mask) == 0
        and snapshot.fault_code == FAULT_NONE
        and (snapshot.ctrl & CTRL_PWM_ENABLE) == 0
    )


def recover_after_external_safety_confirmation(
    mmio, timeout_polls=RECOVERY_TIMEOUT_POLLS
):
    # Caller must externally confirm physical input safety first.
    if timeout_polls <= 0 or not disable_pwm(mmio):
        disable_pwm(mmio)
        return False

    clear_fault_request(mmio)

    for _ in range(timeout_polls):
        if recovery_is_verified(read_status(mmio)):
            return True

    disable_pwm(mmio)
    return False


def enable_pwm_after_recovery(mmio):
    if not recovery_is_verified(read_status(mmio)):
        disable_pwm(mmio)
        return False

    mmio.write(REG_CTRL, CTRL_PWM_ENABLE)
    if (mmio.read(REG_CTRL) & CTRL_PWM_ENABLE) == 0:
        disable_pwm(mmio)
        return False

    return True
