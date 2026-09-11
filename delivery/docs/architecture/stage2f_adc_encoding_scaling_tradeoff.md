# Stage 2F ADC encoding and scaling architecture tradeoff

Date: 2026-08-05
Decision status: hardened recommendation for a later implementation

## Decision

Select candidate C for the initial digital foundation:

```text
SELECTED_INITIAL_ARCHITECTURE=C_DECODE_NOMINAL_ZERO_AND_POLARITY
INITIAL_DIGITAL_TRANSFORM=ENCODING_THEN_NOMINAL_ZERO_REMOVAL_THEN_POLARITY
NORMALIZED_UNIT=SIGNED_CODE_COUNT
GENERIC_RATIONAL_DIVIDER=NO
CALIBRATION_ARITHMETIC=DEFERRED
```

The current repository has strong authority for raw transport, atomic CDC,
raw protection, and raw readback. It has no production ADC/AFE/sensor profile
or calibration evidence. Candidate C resolves the useful digital ambiguity
without fabricating physical scaling or changing the safety path.

## First-principles comparison

`II` means initiation interval. Costs are relative architecture estimates, not
post-route measurements.

| Candidate | Current requirement | Available authority | FPGA cost | Latency and II | Timing risk | Verification burden | Software alternative | Physical-accuracy dependency | Disposition |
|---|---|---|---|---|---|---|---|---|---|
| A. Decode-only signed code counts | Partly: explicit coding is required, but unsigned sources still lack a meaningful zero and direction | Source profile can name coding; current production profile is unconfigured | Very low: sign interpretation or widening | Fixed implementation-derived latency; II=1 is straightforward | Low | Encoding endpoints and sign extension | Software can decode telemetry, but hardware observability stays ambiguous | None for digital correctness; still no physical accuracy | Do not select alone; incomplete for unsigned bipolar sources |
| B. Decode + polarity | Partly: channel direction must be explicit | Source profile can own polarity after wiring/source review | Very low: conditional widened negation | Fixed implementation-derived latency; II=1 | Low | Both polarities, most-negative input, channel independence | Software can apply polarity | None for digital direction; still lacks unsigned nominal zero | Do not select alone; unsigned codes remain uncentered |
| C. Decode + nominal zero + polarity | Yes: minimum complete signed code-count meaning | Small source profile owns encoding, nominal zero, and per-channel polarity | Low: widened subtract/sign extension and conditional negation; no DSP or divider required | Fixed implementation-derived latency; II=1 required | Low | Encoding/zero/polarity matrix, sequence alignment, reset, raw-path regression | Software conversion is possible, but parallel hardware telemetry gives deterministic correlation | No physical-accuracy dependency; nominal zero is not measured calibration | Include; selected initial architecture |
| D. Decode + per-channel offset | No present requirement for arbitrary or measured board offset in FPGA | No board-specific calibration record, bounds, or identity authority exists | Low to moderate subtractors and wider range proofs | Can remain fixed and II=1, but width follows coefficient bounds | Low to moderate | Bounds, update identity, overflow, validity, reset, and channel coefficient tests | Apply measured offsets in software after calibration exists | Measured accuracy depends directly on board calibration and drift | Defer; do not add arbitrary runtime offset |
| E. Decode + arbitrary rational gain | No present requirement | No coefficient, denominator, rounding, range, or update authority exists | High relative cost: wide multiply plus generic signed divide or large reciprocal machinery | Divider can threaten fixed latency and II=1; exact architecture unknown | High | Sign, division, rounding, saturation, denominator, overflow, throughput, and timing matrix | Software naturally handles flexible rational conversion | Fully dependent on physical transfer and calibration authority | Reject from initial foundation; generic rational divider forbidden |
| F. Software-only physical conversion | Potentially useful after a physical profile exists; never for the real-time fault path | Future approved hardware profile and calibration record could own formula and units | No added FPGA arithmetic | No FPGA latency; software is not deterministic fault latency | None in FPGA | Formula/version/identity tests and snapshot consistency | This is the candidate itself | Fully dependent on hardware facts and calibration | Keep as a future telemetry option; not currently functional or authoritative |
| G. Source-specific generated constant transform | Possible future need if physical conversion must be in FPGA | Requires an approved source profile, bounded constants, error budget, and calibration policy | Usually lower and more predictable than generic runtime division; exact cost source-specific | Fixed latency and II=1 can be designed after constants are known | Moderate and reviewable only with concrete constants | Generated-model equivalence, width, rounding, saturation, timing, identity, and regression tests | Same conversion can remain in software if fault policy does not need it | Fully dependent on approved physical profile; calibration may still be needed | Prefer over E if later justified, but defer now |

## Candidate A: decode-only signed code counts

For two's-complement input, sign extension alone provides a centered signed
count. For an unsigned source, merely widening `0..4095` does not identify the
zero-current point. A general `signed` declaration is not a source contract and
would reinterpret codes incorrectly. Candidate A is therefore insufficient as
the common digital foundation.

## Candidate B: decode plus polarity

Polarity makes channel direction explicit, but it cannot center an unsigned
source. Applying polarity before widened zero removal can also obscure the
meaning of the profile. Polarity belongs after decode and nominal zero removal.

## Candidate C: decode, nominal zero, and polarity

Candidate C uses the minimum useful taxonomy:

```text
UNSIGNED_WITH_ZERO_CODE: signed_count = polarity * (unsigned(raw) - zero_code)
TWOS_COMPLEMENT:         signed_count = polarity * sign_extend_12(raw)
```

Offset binary is the first form with `zero_code=2048`; it needs no separate
mode. A signed 13-bit output exactly contains every legal result, including
negation of the 12-bit two's-complement minimum. The architecture adds no
rounding, saturation, divider, measured offset, or gain identity. Its accuracy
claim is strictly digital: output equals the selected profile transform.

This is the selected initial foundation because it has a clear authority
boundary, low cost, fixed data-independent behavior, initiation interval one,
and a compact independent reference model.

## Candidate D: per-channel offset

A board offset is not the same as nominal encoding zero. Adding an arbitrary
runtime offset would require all of the following before a fixed-width claim is
defensible: signed bounds, ownership, update atomicity, reset value, invalid
behavior, profile/calibration identity binding, intermediate-width proof, and a
reason the correction must occur in FPGA. None currently exists.

```text
ARBITRARY_RUNTIME_OFFSET=NO
BOARD_CALIBRATION_ARITHMETIC=DEFERRED
```

Software can apply a future measured offset to coherent signed-code snapshots
without expanding the safety-critical hardware surface.

## Candidate E: arbitrary rational gain

An arbitrary numerator/denominator interface creates a general signed divider,
rounding policy, saturation policy, coefficient validation problem, and timing
risk before any requirement supplies real coefficients. Even a pipelined
divider must prove II=1 under a no-ready input; a multicycle iterative divider
would violate that contract or require buffering and backpressure redesign.

```text
ARBITRARY_RUNTIME_RATIONAL_GAIN=NO
GENERIC_SIGNED_DIVIDER=NO
GENERIC_RATIONAL_DIVIDER=NO
```

The flexibility has no present authority and is rejected from the initial
architecture.

## Candidate F: software-only physical conversion

Software is a reasonable future home for code-to-current conversion when
physical units are telemetry-only. It can express source-specific formulas,
calibration identity checks, and error reporting without changing raw fault
latency. It cannot make an unapproved formula accurate, and Python must never
be inserted into the real-time protection path. The current unconfigured
production profile means no such conversion is functional today.

## Candidate G: source-specific generated constant transform

If later safety or telemetry requirements justify FPGA physical conversion, a
generator tied to one approved source profile is preferable to a universal
runtime divider. Concrete constants allow deliberate reciprocal/multiply/shift
selection, bounded intermediates, exact rounding, fixed latency, II=1, and
timing evidence. This candidate remains deferred until the physical closure
prerequisite is met.

## Protection-domain alternatives

The above comparison concerns the telemetry transform. The protection-domain
decision remains independent:

| Protection path | Compatibility | Current authority | Disposition |
|---|---|---|---|
| Existing unsigned raw-code protection | Preserves every frozen threshold, health, readback, and fault behavior | Implemented and verified through Stage 2E | Retain |
| Signed code-count protection | Reinterprets thresholds and health endpoints | No versioned safety contract | Future review only |
| Integer or fixed-point physical-unit protection | Reinterprets thresholds and adds conversion failure modes | No production hardware or calibration authority | Unsupported |

```text
STAGE2G_FAULT_INPUT_AUTHORITY=RAW_PROTECTION_EVALUATION
NORMALIZED_TELEMETRY_GATES_FAULT_POLICY=NO
NORMALIZED_DOMAIN_PROTECTION=FUTURE_VERSIONED_SAFETY_CONTRACT_REQUIRED
```

## Final rationale

Candidate C is the only option that resolves encoding, zero, and direction with
current architectural needs while keeping every physical claim explicitly
open. Candidates D and E add cost and failure modes without authority. Candidate
F is viable only after hardware facts exist. Candidate G is the disciplined
future FPGA option if an approved requirement eventually needs it.

```text
BOARD_CALIBRATION_ACCURACY=EXTERNAL_EVIDENCE_REQUIRED
PHYSICAL_SCALING_STATUS=BLOCKED_EXTERNAL_HARDWARE_FACTS
DIGITAL_FOUNDATION_CLOSES_FROZEN_GAP=NO
```
