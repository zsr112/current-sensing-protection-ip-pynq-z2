# Stage 2A normative sampling and CDC boundary specification

Date: 2026-08-03
Baseline: `837bbdd71fec2d7e5a554db4ffa99e2cfccc425b` / `stage2-verification-foundation-v1`

This specification is extracted from current source behavior and then states
the Stage 2 normative boundary.  It does not design or implement an ADC/AFE.
Every substantive statement is labeled as one of:

- `CURRENT_IMPLEMENTED_BEHAVIOR`
- `STAGE2_NORMATIVE_CONTRACT`
- `DEFERRED_IMPLEMENTATION_REQUIREMENT`

## 1. Interface definition

### 1.1 Sample payload

`CURRENT_IMPLEMENTED_BEHAVIOR`

- There is no singular RTL signal named `sample`.  A sample is the ordered
  pair `sample_pair := {i_ch1, i_ch2}`.
- `protection_core_top.DATA_WIDTH` defaults to 12 and both channels are
  declared unsigned `wire [DATA_WIDTH-1:0]` (`rtl/protection_core_top.v:1-19`).
  The current register-controlled integration is effectively fixed at 12 bits
  because the register bank monitor/threshold ports are 12 bits
  (`rtl/protection_reg_bank.v:16-24`).
- At the current 12-bit integration width, the digital range is 0 through
  4095.  Physical unit, volts/count, amperes/count, offset, polarity, ADC code
  format, and saturation meaning are `UNRESOLVED_FROM_CURRENT_SOURCE`.
- Overcurrent uses strict unsigned `>`; equality is safe.  Mismatch uses
  `abs(i_ch1-i_ch2) > th_diff`; equality is safe
  (`rtl/current_compare_dual.v:16-21`).
- Health open is `i_chN <= th_open`, saturation is `i_chN >= th_sat`, and stuck
  stability is both per-channel deltas `<= th_stuck_delta`
  (`rtl/sensor_health_monitor.v:21-28`).

`STAGE2_NORMATIVE_CONTRACT`

`i_ch1` and `i_ch2` are one atomic sample pair.  They must be captured from the
same source transaction and must never be allowed to represent different ADC
sample indices.  No physical interpretation is assigned until an approved
ADC/AFE encoding specification exists.

### 1.2 Valid, clock, and reset

`CURRENT_IMPLEMENTED_BEHAVIOR`

- `sample_valid` is active high and is consumed as a level in
  `else if (sample_valid)` (`rtl/sensor_health_monitor.v:37-64`).
- Sequential protection blocks use the rising edge of `clk`; the AXI wrapper
  maps this to `ACLK` (`rtl/protection_ip_top_axi_lite.v:96-188, :197-214`).
- Reset is active-low `rst_n`/`ARESETN`.  RTL sensitivity lists are
  `posedge clk or negedge rst_n`, so assertion is asynchronous and has priority
  over every normal update.
- The plain RTL contains no reset-release synchronizer.  Exact asynchronous
  assert / synchronous deassert behavior at the integrated boundary is
  `UNRESOLVED_FROM_CURRENT_SOURCE`; the BD explicitly routes PS reset through
  `proc_sys_reset`, but this round did not elaborate that vendor IP.

The current integrated clock is:

```text
processing_system7_0/FCLK_CLK0 (100 MHz integration intent)
  -> protection_ip_axi_lite_0/ACLK
  -> protection_core_top.clk and all protection sequential blocks
```

Evidence is in
`fpga/vivado/build/runtime/runner/stage1e_production_vivado_runner_v2.tcl:594-608,
:933-947` and
`fpga/vivado/package_protection_ip_stage2_axi_lite.tcl:65-73, :253-271`.

## 2. Health sample acceptance and protection events

`STAGE2_NORMATIVE_CONTRACT`

The health-path sample acceptance event is:

```text
health_sample_accept_event := rising_edge(clk)
                              && (rst_n === 1'b1)
                              && (sample_valid === 1'b1)
                              && sample_pair_is_known
```

where `sample_pair_is_known` means neither channel contains X or Z in digital
simulation.  The pair is accepted once per rising edge satisfying this
predicate.

The earlier shorthand `sample_accept` denotes this
`health_sample_accept_event`; it is not the only current protection evaluation
event.  The current RTL has four distinct event boundaries:

```text
health_sample_accept_event := valid, known pair on a reset-inactive rising edge
comparator_evaluation_event := combinational evaluation of i_ch1/i_ch2
fault_registration_event := classifier registration on a rising edge
fault_latch_event := FSM registration of a visible fault on a later rising edge
```

Only `health_sample_accept_event` is gated by `sample_valid` today.  Comparator
evaluation is not gated by `sample_valid`, so comparator results can register
and subsequently latch even when `sample_valid=0`.

Consequences:

- `sample_valid` need not be a one-cycle pulse.  It may remain high.
- Every consecutive high edge represents a new sample; back-to-back and
  held-high valid are supported.
- No ready/backpressure signal exists in the current RTL interface.
- A high valid during reset is ignored.  If valid is already high at the first
  rising edge after reset release, that edge can accept the first sample.

`CURRENT_IMPLEMENTED_BEHAVIOR / CONTRACT GAP`

The acceptance event is already true for the health-history path: only
`sensor_health_monitor` updates on it.  It is **not** true for the complete
protection path.  `current_compare_dual` evaluates continuously and
`fault_classifier` registers comparator results on every rising edge without
`sample_valid` (`rtl/current_compare_dual.v:16-21`;
`rtl/fault_classifier.v:15-36`; `rtl/protection_core_top.v:40-59`).  Therefore
invalid-cycle data can currently create an overcurrent/mismatch fault and
latch safe output.  This is proved, not hidden, by dedicated scenario SC09.

Until that gap is closed or the interface contract is deliberately changed,
an integration must keep `i_ch1/i_ch2` meaningful on every classifier clock,
even when `sample_valid=0`.  It may not assume that invalid data is globally
ignored.

## 3. Four-state and data stability contract

`STAGE2_NORMATIVE_CONTRACT`

1. At every checked rising edge, `rst_n` and `sample_valid` must each be exactly
   0 or 1.  X and Z are illegal.
2. On `sample_accept`, every bit of both channels must be 0 or 1.  X or Z is
   illegal and must fail the checker.
3. In an invalid cycle, changing the sample pair must not increment or alter
   accepted health history/counters/status.
4. Once the complete-path valid-gating gap is closed, invalid sample changes
   must not be interpreted by any protection consumer as a new sample.
5. The RTL testbench drives data and valid away from the active edge and checks
   digital edge behavior.  These tests do not and cannot prove analog or
   device-level setup/hold time.

The executable predicate is case-inequality based (`condition !== 1'b1`), so
false, X, and Z all fail.  Independent self-tests exercise true, false, X, Z,
`sample_valid=X`, valid-data X/Z, and dedicated `rst_n=X/Z` fixtures.

## 4. Invalid and gap behavior

### 4.1 Health path

`CURRENT_IMPLEMENTED_BEHAVIOR`

On any rising edge with reset inactive and `sample_valid != 1` in ordinary
two-state operation, the health `else if` body does not execute.  These
registered objects hold:

- `prev_ch1`, `prev_ch2`
- `open_cnt`, `sat_cnt`, `stuck_cnt`
- `sensor_open_flag`, `sensor_sat_flag`, `sensor_stuck_flag`

This follows directly from the absence of an `else` assignment in
`rtl/sensor_health_monitor.v:37-64`.

- `gap_start`: first invalid edge after a valid edge; all listed state holds.
- `gap_body`: every additional invalid edge; the same state continues to hold.
- `after_gap_first_valid`: the next valid edge compares against the last
  accepted pre-gap sample, not an invalid-cycle value, and continues the held
  persistence counts.  A gap does not reset history.

Counters saturate rather than wrap (`sensor_health_monitor.v:30-35`).  Flags
are assigned from the **old** counter value on a valid edge (`:51-62`).  From a
zero counter and threshold `N`, a continuously qualifying condition becomes
visible on qualifying valid edge `N+1`.  A non-qualifying valid edge resets its
counter but can leave the old flag visible for that edge; the following valid
edge clears it.  Invalid cycles pause both trigger and recovery progress.

### 4.2 Comparator, classifier, latch, and recovery

`CURRENT_IMPLEMENTED_BEHAVIOR`

- Comparator outputs and `abs_diff` may change immediately when an invalid
  sample changes.
- `fault_valid` and live `fault_code` may change at the following classifier
  edge even while invalid.
- In `ST_NORMAL`, the FSM may latch that visible fault at the next edge.  Thus
  `fault_latched`, `fault_code_latched`, `fsm_state`, and `pwm_out` are not
  generally required to hold merely because `sample_valid=0`.
- Once in `ST_FAULT_LATCHED`, the first fault code and latch hold across valid
  and invalid cycles until clear/reset.  A clear edge enters `ST_RESET_WAIT`
  while retaining the latch/code (`rtl/protection_fsm.v:44-50`).
- In `ST_RESET_WAIT`, a visible live fault has priority and may update
  `fault_code_latched` (`:53-68`).  Therefore “first-fault forever” is not true
  after a clear attempt; it is true while remaining in `ST_FAULT_LATCHED`.
- FSM recovery counting is controlled by `fault_valid` and `clear_fault`, not
  by `sample_valid`.  Holding clear high pauses `RESET_WAIT`; a live fault
  returns to `ST_FAULT_LATCHED`.

`STAGE2_NORMATIVE_CONTRACT`

The health hold behavior remains normative.  For a future sampling boundary,
all sample-derived protection decisions must be causally associated with
`sample_accept`; the current comparator bypass is classified
`BLOCKING_FOR_ASYNC_ADC`.

## 5. Reset contract

`CURRENT_IMPLEMENTED_BEHAVIOR`

| Block | Reset values | Evidence |
|---|---|---|
| `sensor_health_monitor` | previous samples, all counters, and all flags = 0 | `sensor_health_monitor.v:37-46` |
| `fault_classifier` | `fault_valid=0`, `fault_code=FAULT_NONE` | `fault_classifier.v:15-19` |
| `protection_fsm` | `ST_NORMAL`, wait count 0, latch 0, disable 0, code none | `protection_fsm.v:22-29` |
| `pwm_gen` | count 0, `pwm_raw=0` | `pwm_gen.v:15-19` |
| register bank | PWM disabled; thresholds/period/duty at documented defaults; clear pulse 0 | `protection_reg_bank.v:37-46` |
| AXI wrapper | request/response state and held data/valid state cleared | `protection_ip_top_axi_lite.v:96-113` |

Because reset is the first branch in every sequential block, it dominates a
same-edge `sample_valid`, live comparator condition, clear, or AXI action.
`pwm_disable` resets low, but `pwm_raw` also resets low, so observable
`pwm_out` is low during reset.

The RTL accepts reset release without local synchronization.  The first rising
edge after `rst_n` is high executes normal logic and may accept a high valid.
Integration must provide a destination-clock-safe release.  Repository Tcl
connects `FCLK_RESET0_N` to `proc_sys_reset.ext_reset_in`, its
`slowest_sync_clk` to `FCLK_CLK0`, and `peripheral_aresetn` to every current
consumer; the exact generated implementation and future ADC reset relation
must be rechecked with elaborated Vivado evidence.

## 6. CDC boundary contract

`CURRENT_IMPLEMENTED_BEHAVIOR`

```text
Current Stage 1/Stage 2A protection sample interface is same-domain.
No synchronizer may be inserted between sample and sample_valid independently.
Future asynchronous ADC source must terminate at an explicit atomic CDC boundary.
```

The frozen Stage 1 GPIO producer and protection consumer share
`FCLK_CLK0/ACLK`; `sample_valid` is a constant.  No current multibit unsafe CDC
is present under that construction.  This does not prove a future ADC path.

`STAGE2_NORMATIVE_CONTRACT`

The complete transaction is `{sample_valid,i_ch1,i_ch2}`.  Valid and either
channel must never use independent two-flop synchronizers.  Permitted future
architectures are:

1. source-synchronous capture followed by same-domain processing;
2. request/acknowledge handshake with the entire pair held stable until ack;
3. asynchronous FIFO carrying both channels in one payload;
4. explicitly reviewed toggle/pulse handshake with held atomic data.

For any selected mechanism:

- Exactly one destination `sample_accept` is generated per delivered source
  sample.  Duplicate delivery is forbidden.
- No loss is permitted within the declared normal-rate envelope.
- If the source can accept backpressure, it must retain the tuple until ack or
  FIFO space.  If an ADC cannot backpressure and the boundary is full, the
  required overload policy is drop-newest; it must increment a saturating drop
  counter and set a sticky overflow flag.  Silent loss is forbidden.
- Reset must suppress phantom accepts.  Handshake state or FIFO pointers must
  be reset by a mechanism safe in each domain, and delivery must remain
  disabled until both sides have re-armed.
- CDC/overload observability must include sticky overflow, a sample-drop count,
  boundary reset/re-arm state, and a clear method in the destination domain.

`DEFERRED_IMPLEMENTATION_REQUIREMENT`

No such boundary, backpressure wire, FIFO, telemetry register, or ADC clock is
implemented in this round.  Selection and implementation require a later
authorized Stage 2 change and CDC/timing review.

```text
FUTURE_ADC_ATOMIC_CDC_CONTRACT=DEFINED
INDEPENDENT_VALID_DATA_SYNCHRONIZERS_ALLOWED=NO
```

## 7. Digital latency boundaries

The cycle names below refer only to RTL clock edges.  They are not an
ADC-to-power-stage end-to-end measurement.

### 7.1 Comparator fault path

Let `C0` be a rising edge at which known current data is presented and the
combinational comparator relation is faulting.

| Boundary | Visibility |
|---|---|
| sample / comparator observation | Comparator outputs are already combinational before `C0` |
| classifier recognition | `fault_valid/fault_code` visible after `C0` |
| fault latch | `fault_latched/fault_code_latched` visible after `C1`, the next rising edge |
| safe output | `pwm_disable` updates at `C1`; combinational `pwm_gate` makes `pwm_out=0` in the same post-edge simulation cycle |

This path currently behaves the same whether `sample_valid` is 0 or 1; that is
the recorded gap.

### 7.2 Health fault path

Let `H0` be the valid edge on which a registered health flag first becomes
visible.  The exact number of preceding accepts depends on the threshold and
previous accepted history; from counter zero it is normally `th_persist+1`
qualifying valid edges because the flag uses the old count.

| Boundary | Visibility |
|---|---|
| health recognition | health flag visible after `H0` |
| classifier recognition | `fault_valid/fault_code` visible after `H1` |
| fault latch | latch/code visible after `H2` |
| safe output | `pwm_out=0` in the same post-edge simulation cycle as `H2` |

## 8. Contract gaps and disposition

| ID | Severity | Gap | Required later action |
|---|---|---|---|
| G1 | `BLOCKING_FOR_ASYNC_ADC` | Comparator/classifier can consume invalid-cycle data | Gate or stage the complete protection decision at the unique accept event, or approve a different explicit interface contract |
| G2 | `BLOCKING_FOR_ASYNC_ADC` | No atomic ADC/AFE CDC implementation exists | Implement one permitted atomic mechanism and prove it with CDC/timing/functional evidence |
| G3 | `REQUIRED_BEFORE_BOARD_EXPANSION` | Destination-safe reset release is not proved from plain RTL/Tcl alone | Elaborate generated reset IP and rerun `report_cdc`/reset analysis for the selected boundary |
| G4 | `REQUIRED_BEFORE_BOARD_EXPANSION` | No overload, drop, duplicate, or CDC-error telemetry exists | Implement the specified overflow/drop/re-arm observability with the boundary |
| G5 | `DOCUMENTATION_ONLY` | ADC code format and physical scale are unknown | Supply an approved ADC/AFE encoding and unit specification; do not infer it from 12-bit width |
| G6 | `DEFERRED_TO_LATER_STAGE2` | First-fault code can update in `ST_RESET_WAIT` after clear | Decide whether this is the intended campaign policy before extending fault management |

```text
CONTRACT_GAPS=6
BLOCKING_FOR_ASYNC_ADC=2
REQUIRED_BEFORE_BOARD_EXPANSION=2
DOCUMENTATION_ONLY=1
DEFERRED_TO_LATER_STAGE2=1
IMPLEMENTATION_CLOSURE_CLAIMED=NO
FULL_STAGE2_COMPLETION_CLAIMED=NO
```
