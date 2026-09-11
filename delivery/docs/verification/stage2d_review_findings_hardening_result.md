# Stage 2D concrete-review findings hardening result

Date: 2026-08-04
Branch: `codex/stage2d-async-adc-atomic-cdc`
Previous feature commit: `9b1f02d19bbb221135856970e5e22bd78f7b7bcd`

## Closure result

The five concrete-review findings are closed in the same feature branch.

| Finding | Closure |
|---|---|
| Machine execution contract | Contract, request, runtime preflight, Tcl/PowerShell convergence fixtures, and published identity use the exact asynchronous ADC pins and 12-probe ILA. An obsolete synchronous-pin fixture fails. |
| CDC constraint authority | A packaged production XDC constrains both Gray-pointer buses with narrow fail-closed matching, datapath-only maximum delay, and bus skew. Static positive and negative Tcl fixtures pass. |
| Controlled stimulus | The current source is explicitly `SAFE_INERT_EXPLICIT`, fixes valid low, makes no acceptance or fault-stimulus claim, and probes ready at ILA probe 11. |
| IP interface version | All active exact authorities bind custom IP v0.2. |
| Parameter guards | Package ranges and RTL elaboration guards reject `DATA_WIDTH < 1` and `FIFO_ADDR_WIDTH < 2`; FIFO and bridge negative fixtures cover both simulator flows. |

## Verification boundary

The Stage 2D runner covers dedicated Icarus and XSim scenarios, checker true
and 12-negative self-tests, production-wrapper tests, Stage 2C 27/27, Stage
2B 26/26 in both simulators, canonical Icarus 10/10, Python contracts, the
affected Tcl suites, execution-contract negatives, CDC static tests, source
closure, and `git diff --check`. The final handoff reports the immutable
timestamped evidence root produced from the clean pushed hardening commit.

No synthesis, implementation, bitstream generation, Hardware Manager, board,
ADC/AFE, or power-stage action is authorized or claimed. Accordingly,
Vivado-generated `report_cdc`, timing, and implemented bus-skew reports remain
deferred to the authorized hardware-build gate.

## Pre-merge profile and observation convergence

The production-referenced standalone BD and the controlled runtime path are
now both in the `SAFE_INERT` class with `adc_sample_valid=0`. The runtime keeps
the more specific implementation label `SAFE_INERT_EXPLICIT`; neither path is
functional ADC stimulus. Static convergence tests reject a missing profile, a
safe profile with valid high, a production valid-high producer without ready
handling, and a demo/test-only profile referenced by production.

```text
FUNCTIONAL_ADC_STIMULUS=NO
CURRENT_ADC_SRC_CLK_EQUALS_ACLK=YES
ACLK_ILA_READY_OBSERVATION_VALID_ONLY_WHILE_CLOCKS_IDENTICAL=YES
ACLK_ILA_READY_OBSERVATION_BOUNDARY=DOCUMENTED
DISTINCT_ADC_CLOCK_REQUIRES_SOURCE_CLOCK_ILA_OR_SYNCHRONIZED_OBSERVATION=YES
DISTINCT_CLOCK_DEBUG_POLICY=SOURCE_DOMAIN_ILA_OR_SYNCHRONIZED_OBSERVATION
DIRECT_ASYNC_READY_OBSERVATION_AS_CDC_PROOF=FORBIDDEN
```

The `ACLK` ILA ready probe is acceptance evidence only for the current
identical-clock profile. It is not asynchronous CDC proof. A future distinct
clock profile must observe in the source domain or synchronize the observation
explicitly, while routed hardware CDC/timing/bus-skew closure remains pending.
