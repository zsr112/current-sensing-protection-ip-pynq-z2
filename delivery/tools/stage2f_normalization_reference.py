#!/usr/bin/env python3
"""Independent integer reference model for Stage 2F-D normalization."""

from __future__ import annotations

from collections import deque
from dataclasses import dataclass
import json
from pathlib import Path
from typing import Any, Iterable


RAW_WIDTH = 12
NORMALIZED_WIDTH = 13
LATENCY_ACLK = 1


@dataclass(frozen=True)
class Profile:
    identity: str
    state: str
    encoding: str
    zero_code: int | None
    ch1_negative: bool
    ch2_negative: bool

    @property
    def configured(self) -> bool:
        return self.state == "CONFIGURED_DIGITAL"


def load_profile(path: Path) -> Profile:
    data = json.loads(path.read_text(encoding="utf-8"))
    polarity = data["channel_polarity"]
    return Profile(
        identity=data["profile_identity"],
        state=data["profile_state"],
        encoding=data["encoding"],
        zero_code=data["zero_code"],
        ch1_negative=polarity["channel_1"] == "INCREASING_CODE_IS_NEGATIVE",
        ch2_negative=polarity["channel_2"] == "INCREASING_CODE_IS_NEGATIVE",
    )


def _twos_complement(raw_code: int) -> int:
    sign_bit = 1 << (RAW_WIDTH - 1)
    modulus = 1 << RAW_WIDTH
    return raw_code - modulus if raw_code & sign_bit else raw_code


def decode_code(raw_code: int, encoding: str, zero_code: int | None) -> int | None:
    """Decode one raw code using Python integers, independently of RTL widths."""

    if not 0 <= raw_code < (1 << RAW_WIDTH):
        raise ValueError(f"raw code outside 12-bit domain: {raw_code}")
    if encoding == "UNSIGNED_WITH_ZERO_CODE":
        if zero_code is None or not 0 <= zero_code < (1 << RAW_WIDTH):
            raise ValueError("unsigned profile requires a 12-bit zero code")
        return raw_code - zero_code
    if encoding == "TWOS_COMPLEMENT":
        if zero_code != 0:
            raise ValueError("two's-complement profile requires zero code 0")
        return _twos_complement(raw_code)
    return None


def normalize_code(raw_code: int, profile: Profile, channel: int = 1) -> int | None:
    if not profile.configured:
        return None
    decoded = decode_code(raw_code, profile.encoding, profile.zero_code)
    if decoded is None:
        return None
    negative = profile.ch1_negative if channel == 1 else profile.ch2_negative
    normalized = -decoded if negative else decoded
    if not -(1 << (NORMALIZED_WIDTH - 1)) <= normalized < (1 << (NORMALIZED_WIDTH - 1)):
        raise AssertionError(f"normalized result does not fit signed 13 bits: {normalized}")
    return normalized


def mathematical_oracle(
    raw_code: int,
    encoding: str,
    zero_code: int | None,
    polarity_negative: bool,
) -> int:
    """Compute the contract directly from its mathematical definition."""

    if not 0 <= raw_code < (1 << RAW_WIDTH):
        raise ValueError(f"raw code outside 12-bit domain: {raw_code}")
    if encoding == "UNSIGNED_WITH_ZERO_CODE":
        if zero_code is None or not 0 <= zero_code < (1 << RAW_WIDTH):
            raise ValueError("unsigned profile requires a 12-bit zero code")
        expected = raw_code - zero_code
    elif encoding == "TWOS_COMPLEMENT":
        if zero_code != 0:
            raise ValueError("two's-complement profile requires zero code 0")
        expected = raw_code if raw_code < 2048 else raw_code - 4096
    else:
        raise ValueError(f"unsupported configured encoding: {encoding}")
    return -expected if polarity_negative else expected


Transaction = tuple[int, int, int]
Output = tuple[int, int, int] | None


class NormalizationPipelineModel:
    """Cycle model with an explicit fixed-latency queue and reset flush."""

    def __init__(self, profile: Profile, latency: int = LATENCY_ACLK) -> None:
        if latency < 1:
            raise ValueError("latency must be positive")
        self.profile = profile
        self.latency = latency
        self._pending: deque[Output] = deque([None] * latency)

    def reset(self) -> None:
        self._pending = deque([None] * self.latency)

    def step(
        self,
        reset_n: bool,
        raw_valid: bool,
        sequence: int = 0,
        ch1: int = 0,
        ch2: int = 0,
    ) -> Output:
        if not reset_n:
            self.reset()
            return None
        output = self._pending.popleft()
        transaction: Output = None
        if raw_valid and self.profile.configured:
            transaction = (
                sequence,
                normalize_code(ch1, self.profile, 1),
                normalize_code(ch2, self.profile, 2),
            )
        self._pending.append(transaction)
        return output


def expected_stream(profile: Profile, transactions: Iterable[Transaction]) -> list[Output]:
    model = NormalizationPipelineModel(profile)
    outputs: list[Output] = []
    for sequence, ch1, ch2 in transactions:
        outputs.append(model.step(True, True, sequence, ch1, ch2))
    outputs.append(model.step(True, False))
    return outputs


def exhaustive_arithmetic(profile: Profile) -> int:
    """Compare every profile result with a separate mathematical oracle."""

    count = 0
    for raw in range(1 << RAW_WIDTH):
        for channel in (1, 2):
            value = normalize_code(raw, profile, channel)
            if profile.configured:
                negative = profile.ch1_negative if channel == 1 else profile.ch2_negative
                expected = mathematical_oracle(
                    raw, profile.encoding, profile.zero_code, negative
                )
                if value != expected:
                    raise AssertionError(
                        f"reference mismatch raw={raw} channel={channel}: "
                        f"actual={value} expected={expected}"
                    )
            else:
                if value is not None:
                    raise AssertionError("unconfigured profile produced a value")
            count += 1
    return count


def exhaustive_reference_verification() -> int:
    """Verify all required zero-code, polarity, and signed-code domains."""

    count = 0
    for zero_code in (0, 1, 2047, 2048, 4094, 4095):
        for negative in (False, True):
            profile = Profile(
                identity=f"REFERENCE_UNSIGNED_{zero_code}_{int(negative)}",
                state="CONFIGURED_DIGITAL",
                encoding="UNSIGNED_WITH_ZERO_CODE",
                zero_code=zero_code,
                ch1_negative=negative,
                ch2_negative=negative,
            )
            for raw in range(1 << RAW_WIDTH):
                actual = normalize_code(raw, profile, 1)
                expected = zero_code - raw if negative else raw - zero_code
                if actual != expected:
                    raise AssertionError(
                        f"unsigned exhaustive mismatch zero={zero_code} raw={raw} "
                        f"negative={negative}: actual={actual} expected={expected}"
                    )
                count += 1
    for negative in (False, True):
        profile = Profile(
            identity=f"REFERENCE_TWOS_{int(negative)}",
            state="CONFIGURED_DIGITAL",
            encoding="TWOS_COMPLEMENT",
            zero_code=0,
            ch1_negative=negative,
            ch2_negative=negative,
        )
        for raw in range(1 << RAW_WIDTH):
            decoded = raw if raw < 2048 else raw - 4096
            expected = -decoded if negative else decoded
            actual = normalize_code(raw, profile, 1)
            if actual != expected:
                raise AssertionError(
                    f"two's-complement exhaustive mismatch raw={raw} "
                    f"negative={negative}: actual={actual} expected={expected}"
                )
            count += 1
    if mathematical_oracle(0x7FF, "TWOS_COMPLEMENT", 0, False) != 2047:
        raise AssertionError("0x7ff signed boundary failed")
    if mathematical_oracle(0x800, "TWOS_COMPLEMENT", 0, False) != -2048:
        raise AssertionError("0x800 signed boundary failed")
    if mathematical_oracle(0x800, "TWOS_COMPLEMENT", 0, True) != 2048:
        raise AssertionError("reversed 0x800 signed boundary failed")
    return count


def verify_reference_mutations() -> int:
    """Prove five incorrect mathematical models disagree with the contract."""

    def zero_hard_coded(raw: int, encoding: str, zero: int, negative: bool) -> int:
        if encoding == "UNSIGNED_WITH_ZERO_CODE":
            value = raw - 2048
        else:
            value = raw if raw < 2048 else raw - 4096
        return -value if negative else value

    def subtraction_reversed(raw: int, encoding: str, zero: int, negative: bool) -> int:
        if encoding == "UNSIGNED_WITH_ZERO_CODE":
            value = zero - raw
        else:
            value = raw if raw < 2048 else raw - 4096
        return -value if negative else value

    def twos_as_unsigned(raw: int, encoding: str, zero: int, negative: bool) -> int:
        value = raw - zero if encoding == "UNSIGNED_WITH_ZERO_CODE" else raw
        return -value if negative else value

    def wrong_sign_bit(raw: int, encoding: str, zero: int, negative: bool) -> int:
        if encoding == "UNSIGNED_WITH_ZERO_CODE":
            value = raw - zero
        else:
            value = raw - 4096 if raw & (1 << 10) else raw
        return -value if negative else value

    def polarity_reversed(raw: int, encoding: str, zero: int, negative: bool) -> int:
        if encoding == "UNSIGNED_WITH_ZERO_CODE":
            value = raw - zero
        else:
            value = raw if raw < 2048 else raw - 4096
        return value if negative else -value

    mutants = (
        zero_hard_coded,
        subtraction_reversed,
        twos_as_unsigned,
        wrong_sign_bit,
        polarity_reversed,
    )
    domains = [
        ("UNSIGNED_WITH_ZERO_CODE", zero)
        for zero in (0, 1, 2047, 2048, 4094, 4095)
    ] + [("TWOS_COMPLEMENT", 0)]
    killed = 0
    for mutant in mutants:
        mismatch = False
        for encoding, zero in domains:
            for negative in (False, True):
                for raw in range(1 << RAW_WIDTH):
                    expected = mathematical_oracle(raw, encoding, zero, negative)
                    if mutant(raw, encoding, zero, negative) != expected:
                        mismatch = True
                        break
                if mismatch:
                    break
            if mismatch:
                break
        if not mismatch:
            raise AssertionError(f"reference mutation survived: {mutant.__name__}")
        killed += 1
    return killed


def main() -> int:
    cases = exhaustive_reference_verification()
    killed = verify_reference_mutations()
    print(f"PYTHON_REFERENCE_EXHAUSTIVE=PASS_{cases}_CASES")
    print("TWOS_COMPLEMENT_BOUNDARY=PASS_0X7FF_0X800")
    print(f"PYTHON_REFERENCE_MUTATIONS=PASS_{killed}_OF_{killed}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
