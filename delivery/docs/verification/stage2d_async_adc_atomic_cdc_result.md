# Stage 2D asynchronous ADC atomic CDC result

Date: 2026-08-04
Baseline: `1b500f4679f6e7de10a85b9813ad9d27ff53e46f`
Branch: `codex/stage2d-async-adc-atomic-cdc`
Reviewed feature commit: `9b1f02d19bbb221135856970e5e22bd78f7b7bcd`

> **Stage2I-B current-authority correction (2026-08-10):** The result below is
> historical evidence for the pre-elastic Stage2D implementation and remains
> valid as historical truth about that tree. The current bridge has an elastic
> destination register: `u_fifo.rd_fire`/`fifo_read_enable` prefetches into the
> register, while the later accepted `dst_sample_valid` edge is the atomic raw
> CDC destination delivery, Stage2B N0, and Stage2G authority. The frozen
> delivery-to-policy latency remains three ACLK edges.

## Result

Stage 2D closes the asynchronous ADC atomic CDC contract in the feature
branch. The production hierarchy now contains one ADC source clock domain and
one `ACLK` destination domain. It uses an eight-word dual-clock asynchronous
FIFO rather than a request/acknowledge bridge because the producer contract
must support back-to-back samples and does not establish a round-trip payload
hold interval.

The source acceptance event is a rising `adc_src_clk` edge with
`adc_sample_valid && adc_sample_ready`. Both channel values form the single
FIFO word `{adc_sample_ch1, adc_sample_ch2}`. The destination delivery event is
the actual FIFO dequeue on an `ACLK` rising edge. The FIFO non-empty level is
never used as the Stage 2B event. Consequently the existing Stage 2B N0 pulse,
atomic accepted-pair register, comparator, and health monitor all consume the
same dequeued transaction.

The review-hardening revision also makes the deployed integration contract
match that RTL boundary. The machine execution contract, request fixture,
runtime preflight, block-design authorities, and exact ILA topology now use
`adc_src_clk`, `adc_sample_valid`, `adc_sample_ready`, `adc_sample_ch1`, and
`adc_sample_ch2`; the obsolete synchronous pin names have an explicit
negative fixture. The ILA has 12 probes, with probe 11 bound to
`protection_ip_axi_lite_0/adc_sample_ready`.

## Atomicity and flow control

Only Gray-coded pointers cross domains, through two-stage `ASYNC_REG`
synchronizers. Payload bits remain in dual-port FIFO storage: a word is fully
written before its pointer becomes visible in the destination and its address
cannot be reused until the synchronized read pointer returns space. Exact
payload/order scoreboards, a strong channel transform, wraparound, changing
payloads, randomized clocks, and controlled tearing/reorder fixtures provide
dynamic evidence for this invariant. Outside a qualified dequeue, the exposed
destination bus holds a destination-clocked copy of the last delivered pair;
an empty-address source write therefore cannot leak into the AXI monitor path.

Held-high valid means one source transaction on every edge where ready is
high. Back-to-back operation is supported. Ready is low during source reset or
FIFO full, and the write pointer does not advance while full. A conforming
producer must hold or retry a transaction while ready is low. A future
observability stage still owns status/counters for an upstream producer that
violates this contract; Stage 2D does not claim that gap closed.

The current controlled block-design stimulus is deliberately
`SAFE_INERT_EXPLICIT`: its `adc_sample_valid` is fixed low, its channel values
may be driven for plumbing checks, and it makes neither a source-acceptance
claim nor a fault-stimulus claim. Ready is nevertheless carried to ILA probe
11 so a later functional ready-aware producer has an exact acceptance
evidence path. This limited profile must not be cited as functional ADC or
fault-injection evidence.

The standalone production-referenced Stage 2 BD authority is likewise
classified `SAFE_INERT` and now fixes `adc_sample_valid=0`; there is no
unclassified production valid-high entry. The current observation boundary is:

```text
FUNCTIONAL_ADC_STIMULUS=NO
CURRENT_ADC_SRC_CLK_EQUALS_ACLK=YES
ACLK_ILA_READY_OBSERVATION_VALID_ONLY_WHILE_CLOCKS_IDENTICAL=YES
ACLK_ILA_READY_OBSERVATION_BOUNDARY=DOCUMENTED
DISTINCT_ADC_CLOCK_REQUIRES_SOURCE_CLOCK_ILA_OR_SYNCHRONIZED_OBSERVATION=YES
DISTINCT_CLOCK_DEBUG_POLICY=SOURCE_DOMAIN_ILA_OR_SYNCHRONIZED_OBSERVATION
DIRECT_ASYNC_READY_OBSERVATION_AS_CDC_PROOF=FORBIDDEN
```

Because both logical clocks currently use `FCLK_CLK0`, the `ACLK`-clocked ILA
ready probe can support current-profile acceptance observation. It is not
evidence for a genuinely asynchronous ready crossing. A distinct source clock
requires source-domain ILA capture or a purposefully synchronized observation;
hardware `report_cdc`, timing, and bus-skew reports remain a separate gate.

## CDC constraint and interface authority

`fpga/vivado/constraints/stage2d_async_adc_atomic_cdc.xdc` is the production
CDC constraint authority. It matches only the two exact Gray-pointer
first-stage synchronizer buses under
`u_adc_sample_cdc_bridge/u_fifo`, requires at least three contiguous indexed
bits, requires one source clock per bus, and fails closed on missing,
duplicated, or ambiguous objects. It applies both datapath-only maximum delay
and bus-skew bounds derived conservatively from the source and destination
periods. It contains no payload false path and no blanket asynchronous clock
group.

Static Tcl tests exercise the positive distinct-clock case and fail-closed
cases for too few or missing bits, duplicate matches, missing or multiple
clocks, and invalid periods. Vivado `report_cdc`, timing, and implemented
bus-skew execution remain explicitly deferred to an authorized hardware-build
gate; this hardening task does not claim those reports.

The incompatible external port change is published as
`zsr112.local:protection:protection_ip_axi_lite:0.2` across all active exact
VLNV authorities. Packaged `DATA_WIDTH` is constrained to 1 through 1024 and
`ADC_FIFO_ADDR_WIDTH` to 2 through 16. RTL elaboration fails closed for
`DATA_WIDTH < 1` and `FIFO_ADDR_WIDTH < 2`; dedicated negative elaboration
fixtures cover the FIFO and bridge in both simulator flows.

## Reset semantics

Common `ARESETN` asserts asynchronously. Separate two-flop reset-release
synchronizers deassert local reset in `adc_src_clk` and `ACLK` independently.
Reset cancels every word that has not been delivered, clears both pointer
epochs, produces no phantom transaction, and never replays stale storage. The
source-first, destination-first, near-simultaneous, in-flight, pending/full,
and randomized reset cases pass. The first accepted post-reset transaction is
delivered exactly once.

## Verification result

The complete development runner passed before commit and also verifies its
inventory and SHA-256 manifest. The authoritative evidence is regenerated
from the clean feature commit after commit and its exact absolute root is
reported in the final handoff.

| Gate | Result |
|---|---|
| Stage 2D directed scenarios | 30/30 in Icarus and XSim |
| Random asynchronous stress | 1,247 Icarus; 1,276 XSim transactions |
| Checker self-test | true case plus 12 negative fixtures pass in both simulators |
| Production-wrapper integration | pass in Icarus and XSim |
| Stage 2C regression | 27/27 in both simulators |
| Stage 2B regression | 26/26 in both simulators |
| Canonical Icarus | 10/10 |
| Python contracts | 42 repository plus 7 software tests |
| Tcl build/configuration/source closure | pass |
| Machine execution-contract convergence and old-pin negative | pass |
| CDC constraint authority and static negatives | pass |
| Safe-inert profile and ready evidence path | pass |
| IP v0.2 authority and FIFO parameter guards | pass |
| `git diff --check` | pass |

The unloaded phase scan measured source acceptance to destination delivery at
exactly 3 destination cycles, or 38-48 ns for the tested clock/phase cases.
Queue occupancy or destination pause can increase that interval. Destination
delivery to the established Stage 2B safe result remains 3 destination cycles;
the Stage 2B N0/N3/N4 definition and latency did not change.

Production source closure covers every active configuration authority, direct
packaging/project Tcl list, and the production runtime runner. Negative static
fixtures prove detection of a missing top, missing parameterized FIFO,
direct-Tcl-only update, and simulation-only update.

## Remaining boundaries

The remaining contract gaps are exactly:

1. overflow/drop/duplicate/error observability;
2. ADC encoding and physical scaling; and
3. `RESET_WAIT` first-fault policy.

Hardware-only CDC, timing, and implemented bus-skew reports are an execution
gate, not a missing static authority; they remain pending until synthesis or
implementation is separately authorized.

No synthesis, implementation, bitstream generation, Hardware Manager, board,
real ADC/AFE, or power-stage action was performed.
