#!/usr/bin/env python3
"""Independent cycle model and longevity-vector generator for Stage 2G."""

from __future__ import annotations

import argparse
import random
from dataclasses import dataclass
from enum import IntEnum
from pathlib import Path


FAULT_NONE = 0x00
FAULT_OVERCURRENT = 0x01
FAULT_SENSOR_MISMATCH = 0x02
FAULT_SENSOR_OPEN = 0x03
FAULT_SENSOR_SATURATION = 0x04
FAULT_SENSOR_STUCK = 0x05
FAULT_OC_WITH_SENSOR = 0x06


class EpisodeState(IntEnum):
    ARMED = 0
    FAULT_LATCHED = 1
    RESET_WAIT = 2


def priority_code(bitmap: int) -> int:
    """Encode the frozen compatibility priority from a primitive bitmap."""

    bitmap &= 0x3F
    overcurrent = bool(bitmap & 0x03)
    sensor = bool(bitmap & 0x3C)
    if overcurrent and sensor:
        return FAULT_OC_WITH_SENSOR
    if overcurrent:
        return FAULT_OVERCURRENT
    for mask, code in (
        (0x10, FAULT_SENSOR_SATURATION),
        (0x08, FAULT_SENSOR_OPEN),
        (0x20, FAULT_SENSOR_STUCK),
        (0x04, FAULT_SENSOR_MISMATCH),
    ):
        if bitmap & mask:
            return code
    return FAULT_NONE


@dataclass(frozen=True)
class Delivery:
    sequence: int
    bitmap: int
    integrity_clean: bool


@dataclass(frozen=True)
class Evaluation:
    sequence: int
    bitmap: int
    code: int
    integrity_clean: bool


@dataclass
class PolicySnapshot:
    state: EpisodeState = EpisodeState.RESET_WAIT
    fault_latched: bool = False
    fault_code_compat: int = FAULT_NONE
    post_clear_recovery_pending: bool = False
    pwm_disable: bool = True
    clear_pending: bool = False
    first_fault_code: int = FAULT_NONE
    first_fault_bitmap: int = 0
    live_fault_bitmap: int = 0
    fault_seen_bitmap: int = 0
    first_fault_event: bool = False
    clear_resolution_event: bool = False
    clear_accept_event: bool = False
    clear_resolution_sequence: int = 0


class EpisodeModel:
    """State model expressed from the frozen episode lifecycle."""

    def __init__(self) -> None:
        self.snapshot = PolicySnapshot()

    def _reset(self) -> None:
        self.snapshot = PolicySnapshot()

    def _clear_fields(self) -> None:
        current = self.snapshot
        current.first_fault_code = FAULT_NONE
        current.first_fault_bitmap = 0
        current.live_fault_bitmap = 0
        current.fault_seen_bitmap = 0

    def _start_episode(self, evaluation: Evaluation) -> None:
        current = self.snapshot
        current.state = EpisodeState.FAULT_LATCHED
        current.fault_latched = True
        current.fault_code_compat = evaluation.code
        current.post_clear_recovery_pending = False
        current.pwm_disable = True
        current.clear_pending = False
        current.first_fault_code = evaluation.code
        current.first_fault_bitmap = evaluation.bitmap
        current.live_fault_bitmap = evaluation.bitmap
        current.fault_seen_bitmap = evaluation.bitmap
        current.first_fault_event = True

    def retire(
        self,
        evaluation: Evaluation | None,
        *,
        clear_request: bool,
        reset: bool,
    ) -> PolicySnapshot:
        if reset:
            self._reset()
            return self.snapshot

        current = self.snapshot
        current.first_fault_event = False
        current.clear_resolution_event = False
        current.clear_accept_event = False

        if current.state is EpisodeState.RESET_WAIT:
            current.pwm_disable = True
            current.clear_pending = False
            self._clear_fields()
            if evaluation is not None and evaluation.integrity_clean:
                if evaluation.bitmap:
                    self._start_episode(evaluation)
                else:
                    current.state = EpisodeState.ARMED
                    current.fault_latched = False
                    current.fault_code_compat = FAULT_NONE
                    current.post_clear_recovery_pending = False
                    current.pwm_disable = False

        elif current.state is EpisodeState.ARMED:
            current.fault_latched = False
            current.fault_code_compat = FAULT_NONE
            current.post_clear_recovery_pending = False
            current.pwm_disable = False
            current.clear_pending = False
            self._clear_fields()
            if (
                evaluation is not None
                and evaluation.integrity_clean
                and evaluation.bitmap
            ):
                self._start_episode(evaluation)

        else:
            current.fault_latched = True
            current.pwm_disable = True
            if current.clear_pending and evaluation is not None:
                current.clear_pending = False
                current.clear_resolution_event = True
                current.clear_resolution_sequence = evaluation.sequence
                if evaluation.integrity_clean and not evaluation.bitmap:
                    current.state = EpisodeState.RESET_WAIT
                    current.post_clear_recovery_pending = True
                    current.clear_accept_event = True
                    self._clear_fields()
                elif evaluation.integrity_clean:
                    current.live_fault_bitmap = evaluation.bitmap
                    current.fault_seen_bitmap |= evaluation.bitmap
            else:
                if evaluation is not None and evaluation.integrity_clean:
                    current.live_fault_bitmap = evaluation.bitmap
                    current.fault_seen_bitmap |= evaluation.bitmap
                if not current.clear_pending and clear_request:
                    current.clear_pending = True

        return current


@dataclass
class CycleResult:
    evaluation: Evaluation | None
    policy: PolicySnapshot


class Stage2GPipelineModel:
    """Edge-accurate edge-0/1/2/3 transaction pipeline."""

    def __init__(self, sequence_width: int = 32) -> None:
        if sequence_width < 16 or sequence_width > 32:
            raise ValueError("sequence_width must be in the inclusive range 16..32")
        self.sequence_width = sequence_width
        self.sequence_mask = (1 << sequence_width) - 1
        self.expected_sequence = 0
        self.has_last_delivery = False
        self.last_destination_sequence = 0
        self.capture: Delivery | None = None
        self.decision: Delivery | None = None
        self.evaluation: Evaluation | None = None
        self.policy = EpisodeModel()

    def _reset_sequence_classifier(self) -> None:
        self.expected_sequence = 0
        self.has_last_delivery = False
        self.last_destination_sequence = 0

    def _classify_delivery(self, delivery: Delivery) -> Delivery:
        """Apply Stage 2E's delivery classification before policy capture."""

        sequence = delivery.sequence & self.sequence_mask
        expected = self.expected_sequence
        delta = (sequence - expected) & self.sequence_mask
        expected_delivery = sequence == expected
        duplicate = (
            not expected_delivery
            and self.has_last_delivery
            and sequence == self.last_destination_sequence
        )
        stale_first = not expected_delivery and not self.has_last_delivery
        sequence_gap = (
            not expected_delivery
            and not duplicate
            and not stale_first
            and not (delta & (1 << (self.sequence_width - 1)))
        )
        if expected_delivery or sequence_gap:
            self.expected_sequence = (sequence + 1) & self.sequence_mask
        self.last_destination_sequence = sequence
        self.has_last_delivery = True
        return Delivery(
            sequence=sequence,
            bitmap=delivery.bitmap,
            integrity_clean=delivery.integrity_clean and expected_delivery,
        )

    def _evaluate(self, decision: Delivery | None) -> Evaluation | None:
        if decision is None:
            return None
        bitmap = decision.bitmap & 0x3F
        return Evaluation(
            sequence=decision.sequence & self.sequence_mask,
            bitmap=bitmap,
            code=priority_code(bitmap),
            integrity_clean=decision.integrity_clean,
        )

    def step(
        self,
        delivery: Delivery | None,
        *,
        clear_request: bool = False,
        reset: bool = False,
    ) -> CycleResult:
        retiring = None if reset else self.evaluation
        policy = self.policy.retire(
            retiring, clear_request=clear_request, reset=reset
        )
        if reset:
            self._reset_sequence_classifier()
            self.capture = None
            self.decision = None
            self.evaluation = None
        else:
            self.evaluation = self._evaluate(self.decision)
            self.decision = self.capture
            self.capture = (
                self._classify_delivery(delivery)
                if delivery is not None
                else None
            )
        return CycleResult(evaluation=self.evaluation, policy=policy)


class TraceBuilder:
    def __init__(self, seed: int, sequence_width: int = 32) -> None:
        self.rng = random.Random(seed)
        self.sequence_width = sequence_width
        self.sequence_mask = (1 << sequence_width) - 1
        self.model = Stage2GPipelineModel(sequence_width)
        self.rows: list[tuple[int, ...]] = []
        self.sequence = (self.sequence_mask - 7) & self.sequence_mask
        self.episode_starts = 0
        self.episode_accepts = 0
        self.resolutions = 0
        self.integrity_failures = 0
        self.resets = 0
        self.previous_policy = PolicySnapshot()

    def _check_invariants(self, result: CycleResult, reset: bool) -> None:
        current = result.policy
        previous = self.previous_policy
        if current.state is not EpisodeState.ARMED and not current.pwm_disable:
            raise AssertionError("safe output released outside ARMED")
        if (
            previous.state is EpisodeState.FAULT_LATCHED
            and current.state is EpisodeState.FAULT_LATCHED
            and not reset
        ):
            if current.first_fault_code != previous.first_fault_code:
                raise AssertionError("first code changed inside an episode")
            if current.first_fault_bitmap != previous.first_fault_bitmap:
                raise AssertionError("first bitmap changed inside an episode")
            if current.fault_seen_bitmap | previous.fault_seen_bitmap != current.fault_seen_bitmap:
                raise AssertionError("seen bitmap is not monotonic")
        if current.clear_accept_event:
            if current.state is not EpisodeState.RESET_WAIT or not current.pwm_disable:
                raise AssertionError("accepted clear did not remain safe in RESET_WAIT")
        self.previous_policy = PolicySnapshot(**vars(current))

    def emit(
        self,
        *,
        bitmap: int | None = None,
        integrity_clean: bool = True,
        clear_request: bool = False,
        reset: bool = False,
        sequence: int | None = None,
    ) -> PolicySnapshot:
        delivery = None
        input_sequence = 0
        input_bitmap = 0
        if bitmap is not None and not reset:
            input_sequence = self.sequence if sequence is None else sequence
            input_sequence &= self.sequence_mask
            input_bitmap = bitmap & 0x3F
            delivery = Delivery(
                sequence=input_sequence,
                bitmap=input_bitmap,
                integrity_clean=integrity_clean,
            )
            self.sequence = (input_sequence + 1) & self.sequence_mask
            if not integrity_clean:
                self.integrity_failures += 1
        if reset:
            self.sequence = 0
            self.resets += 1

        result = self.model.step(
            delivery, clear_request=clear_request, reset=reset
        )
        carried_integrity_clean = bool(
            delivery is not None
            and self.model.capture is not None
            and self.model.capture.integrity_clean
        )
        self._check_invariants(result, reset)
        evaluation = result.evaluation
        policy = result.policy
        if policy.first_fault_event:
            self.episode_starts += 1
        if policy.clear_resolution_event:
            self.resolutions += 1
        if policy.clear_accept_event:
            self.episode_accepts += 1

        self.rows.append(
            (
                int(reset),
                int(delivery is not None),
                input_sequence,
                input_bitmap,
                int(carried_integrity_clean),
                int(clear_request),
                int(evaluation is not None),
                evaluation.sequence if evaluation else 0,
                evaluation.bitmap if evaluation else 0,
                evaluation.code if evaluation else FAULT_NONE,
                int(evaluation.integrity_clean) if evaluation else 0,
                int(policy.state),
                int(policy.fault_latched),
                policy.fault_code_compat,
                int(policy.post_clear_recovery_pending),
                int(policy.pwm_disable),
                int(policy.clear_pending),
                policy.first_fault_code,
                policy.first_fault_bitmap,
                policy.live_fault_bitmap,
                policy.fault_seen_bitmap,
                int(policy.first_fault_event),
                int(policy.clear_resolution_event),
                int(policy.clear_accept_event),
                policy.clear_resolution_sequence,
            )
        )
        return policy

    def drain_until(self, predicate, limit: int = 24) -> PolicySnapshot:
        for _ in range(limit):
            policy = self.emit()
            if predicate(policy):
                return policy
        raise AssertionError("model phase failed to make bounded progress")

    def random_bitmap(self, *, nonzero: bool = False) -> int:
        choices = [0x01, 0x02, 0x04, 0x08, 0x10, 0x20,
                   0x03, 0x05, 0x12, 0x24, 0x3F]
        if not nonzero:
            choices.extend([0, 0, 0])
        return self.rng.choice(choices)

    def generate(self, completed_episodes: int) -> None:
        self.emit(reset=True)
        self.emit(reset=True)
        self.emit()

        while self.episode_accepts < completed_episodes:
            state = self.model.policy.snapshot.state

            if state is EpisodeState.RESET_WAIT:
                if self.rng.random() < 0.22:
                    self.emit(bitmap=self.random_bitmap(nonzero=True))
                else:
                    self.emit(bitmap=0)
                # Earlier post-clear traffic may still be in the fixed-latency
                # pipeline.  The first eligible clean retirement owns the
                # RESET_WAIT transition, so follow either legal destination.
                self.drain_until(
                    lambda value: value.state is not EpisodeState.RESET_WAIT
                )
                continue

            if state is EpisodeState.ARMED:
                if self.rng.random() < 0.03:
                    self.emit(reset=True)
                    self.emit()
                    continue
                self.emit(bitmap=self.random_bitmap(nonzero=True))
                self.drain_until(
                    lambda value: value.state is EpisodeState.FAULT_LATCHED
                )
                continue

            # Exercise persistent, sequential, simultaneous, disappearing,
            # and non-clean evaluations.  Consecutive emits create II=1
            # traffic; explicit gaps exercise indefinite state retention.
            for _ in range(self.rng.randint(1, 7)):
                if self.rng.random() < 0.18:
                    self.emit()
                else:
                    self.emit(
                        bitmap=self.random_bitmap(),
                        integrity_clean=self.rng.random() >= 0.12,
                    )

            if self.rng.random() < 0.025:
                self.emit(reset=True)
                self.emit()
                continue

            self.emit(clear_request=True)
            # A held request is coalesced while pending.  Some iterations also
            # retain a complete no-sample gap before resolution.
            for _ in range(self.rng.randint(0, 3)):
                self.emit(clear_request=self.rng.random() < 0.65)

            policy = self.model.policy.snapshot
            if policy.state is not EpisodeState.FAULT_LATCHED:
                continue
            if not policy.clear_pending:
                # An in-flight evaluation may already have rejected the
                # request.  Start another request on a later edge.
                continue

            outcome = self.rng.random()
            if outcome < 0.70:
                bitmap = 0
                clean = True
            elif outcome < 0.88:
                bitmap = self.random_bitmap(nonzero=True)
                clean = True
            else:
                bitmap = self.random_bitmap()
                clean = False
            policy = self.emit(bitmap=bitmap, integrity_clean=clean)
            if not policy.clear_resolution_event:
                self.drain_until(
                    lambda value: value.clear_resolution_event,
                    limit=16,
                )

        for _ in range(6):
            self.emit()

    def write(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        header = (
            "# reset delivery seq bitmap integrity clear "
            "eval_valid eval_seq eval_bitmap eval_code eval_integrity "
            "state public_latched public_code recovery_pending "
            "pwm_disable clear_pending first_code "
            "first_bitmap live_bitmap seen_bitmap first_event "
            "clear_resolution clear_accept clear_resolution_seq"
        )
        lines = [header]
        for row in self.rows:
            values = list(row)
            for index in (2, 3, 7, 8, 9, 13, 17, 18, 19, 20, 24):
                values[index] = f"{values[index]:x}"
            lines.append(" ".join(str(value) for value in values))
        path.write_text("\n".join(lines) + "\n", encoding="ascii")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--episodes", type=int, default=1000)
    parser.add_argument("--seed", type=lambda value: int(value, 0), default=0x2A7E2026)
    parser.add_argument(
        "--sequence-width",
        type=int,
        choices=(16, 24, 32),
        default=32,
        help="sequence arithmetic width used by the independent model",
    )
    args = parser.parse_args()
    if args.episodes < 1000:
        parser.error("--episodes must be at least 1000")

    builder = TraceBuilder(args.seed, args.sequence_width)
    builder.generate(args.episodes)
    if builder.episode_starts < args.episodes:
        raise AssertionError("fewer episode starts than requested")
    if builder.episode_accepts < args.episodes:
        raise AssertionError("fewer accepted episode clears than requested")
    if builder.integrity_failures == 0 or builder.resets == 0:
        raise AssertionError("longevity trace missed integrity/reset coverage")
    builder.write(args.output)
    print(f"REFERENCE_VECTOR_FILE={args.output.resolve()}")
    print(f"REFERENCE_VECTOR_CYCLES={len(builder.rows)}")
    print(f"RANDOM_EPISODE_STARTS={builder.episode_starts}")
    print(f"RANDOM_EPISODE_ACCEPTS={builder.episode_accepts}")
    print(f"RANDOM_CLEAR_RESOLUTIONS={builder.resolutions}")
    print(f"RANDOM_INTEGRITY_FAILURES={builder.integrity_failures}")
    print(f"RANDOM_RESETS={builder.resets}")
    print(f"REFERENCE_SEQUENCE_WIDTH={args.sequence_width}")
    print(f"RANDOM_EPISODES=PASS_{builder.episode_accepts}")
    print("REFERENCE_MODEL_COMPARISON_INPUT=PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
