# Windows B2 FIFO CDC-4 Review

Physical execution: `S1E-B2-REBUILT-WINDOWS-20260909T000000Z`.
Source commit: `3cf68b27c7e30c1ac3729bd9f3b79598531d0be2`.
Source tree: `338bbcc360c82f2ce9b4e6747bc98a60e72ffd26`.
Tool: Vivado 2024.1, Windows build 5076996.

The one CDC-4 Critical finding is the 57-bit asynchronous FIFO storage to
destination-register crossing. It remains visible in the unmodified CDC report.
No waiver, severity change, false path, clock-group exception, or RTL change was
introduced to remove it. The current evidence supports a reviewed custom FIFO
crossing; it does not support reporting zero Critical findings.

## Structural Basis

`async_fifo_gray.v` writes a complete word on a source acceptance, advances a
registered Gray write pointer, and transfers that pointer through two
ASYNC_REG stages. The destination can capture a word only after the synchronized
write pointer makes the FIFO nonempty. The return Gray read pointer prevents
reuse of the slot until the destination has captured the word. Binary pointers
stay within their respective clock domains. This provides a payload stability
interval; synchronizing each payload bit independently would not preserve it.

`stage2g_adc_sample_cdc_bridge` captures the complete 57-bit payload into its
destination register. Its internal FIFO prefetch is distinct from the later
accepted destination delivery. Both resets derive from common ARESETN through
local reset-release synchronizers. Independently resetting only one FIFO side
is outside this integration contract.

## Current Routed Checks

`tools/board_validation/stage2_fifo_routed_audit.tcl` opens the new routed
checkpoint without modifying it. It checks all eight FIFO words and all 57
destination bits, not just the one representative CDC report row.

| Check | Current Result |
| --- | --- |
| Payload paths with an effective 8 ns requirement | PASS, 456/456 |
| Worst payload setup slack under that requirement | +4.467 ns |
| Gray pointer first-stage paths with 8 ns requirement | PASS, 8/8 |
| Worst Gray pointer path slack | +6.519 ns |
| Direct synchronizer stage fanin and ASYNC_REG | PASS, 16/16 stages |
| Write-pointer bus skew | 1.030 ns actual, 8 ns limit |
| Read-pointer bus skew | 0.912 ns actual, 8 ns limit |
| Timing WNS / WHS / WPWS | +0.902 / +0.020 / +2.750 ns |
| Unconstrained internal endpoints | 0 |

Payload max delay is shorter than the interval imposed by two destination
synchronizer stages before capture. Gray-pointer max delay and bus skew are
bounded by the faster clock period (8 ns). The data is not a false-pathed bus.

The fresh full regression also passed with Icarus and XSim, including the
dedicated Stage2D asynchronous CDC and wrapper cases, Stage2I CDC delivery event
authority, reset/no-stale-replay cases, and Stage2G functional and connected
mutation tests. These checks substantiate the implementation contract; digital
simulation does not model analog metastability or establish a quantitative MTBF.

## Decision And Limits

No hardware correction is justified by the current CDC-4 evidence. Replacing
the FIFO merely to change tool recognition would change a verified design and
require a new physical implementation and board campaign. Retain the current
RTL and constraints, retain the raw Critical finding, and attach this review
and the hashed current routed evidence to the new execution.

The prior B2 CDC and timing report bodies match after excluding execution
metadata. That comparison is supporting context only; current hashes and
current test runs establish this execution. DRC has the same PDCN-1569 (three)
and RTSTAT-10 (one) warning categories, with some different displayed
SmartConnect net names. DRC and methodology are separate review items.

This decision is engineering review evidence. Eight-scenario board verification,
final delivery audit, and formal acceptance remain separate gates. It does not
promote historical accepted evidence or constitute final release approval.
