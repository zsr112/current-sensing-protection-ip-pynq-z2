# Stage 2D pre-merge profile and observability convergence

Date: 2026-08-05
Branch: `codex/stage2d-async-adc-atomic-cdc`
Reviewed hardening commit: `5621ede92c3bc0ee32baf9e64d72a7742935f32f`

## Result

The production-referenced standalone Stage 2 block-design Tcl now declares the
`SAFE_INERT` profile and fixes `adc_sample_valid=0`. The controlled production
runner remains `SAFE_INERT_EXPLICIT`, with canonical profile class
`SAFE_INERT`. Both paths explicitly state that they provide no functional ADC
stimulus and make no source-acceptance or fault-stimulus claim.

The fail-closed static convergence gate validates the actual BD assignments,
Phase 2 configuration, runtime topology, machine execution contract, production
references, and documentation. Production classes are limited to
`SAFE_INERT` and `FUNCTIONAL_READY_AWARE`. A future functional profile is
accepted only when a valid source exists, ready is consumed, payload is not
overwritten while ready is low, and the transaction pulse is bounded.

Required negative fixtures reject:

- production valid high without ready-aware behavior;
- a missing profile classification;
- `SAFE_INERT` with valid high; and
- a demo/test-only profile referenced by production.

## Ready-observation boundary

```text
STAGE2_BD_PROFILE=SAFE_INERT
SAMPLE_VALID_DEFAULT=0
FUNCTIONAL_ADC_STIMULUS=NO
CURRENT_ADC_SRC_CLK_EQUALS_ACLK=YES
ACLK_ILA_READY_OBSERVATION_VALID_ONLY_WHILE_CLOCKS_IDENTICAL=YES
ACLK_ILA_READY_OBSERVATION_BOUNDARY=DOCUMENTED
DISTINCT_ADC_CLOCK_REQUIRES_SOURCE_CLOCK_ILA_OR_SYNCHRONIZED_OBSERVATION=YES
DISTINCT_CLOCK_DEBUG_POLICY=SOURCE_DOMAIN_ILA_OR_SYNCHRONIZED_OBSERVATION
DIRECT_ASYNC_READY_OBSERVATION_AS_CDC_PROOF=FORBIDDEN
```

The present block design drives `adc_src_clk` and `ACLK` from the identical
`FCLK_CLK0` net. Consequently, ready captured by the `ACLK`-clocked ILA can be
used for current-profile acceptance observation. That probe is not proof of an
asynchronous CDC path. If the clocks become distinct, ready must be captured by
a source-clock ILA or by a deliberately synchronized observation.

## Closure boundary

This convergence does not expand hardware closure. Current production uses no
distinct clocks and routed hardware CDC closure was not run. Vivado
`report_cdc`, timing, and implemented bus-skew reports remain mandatory at a
separately authorized synthesis/implementation gate. No synthesis,
implementation, bitstream generation, Hardware Manager, board, ADC/AFE, or
power-stage action is performed or claimed here.
