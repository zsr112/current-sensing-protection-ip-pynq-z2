# Stage 2G functional RTL verification

The current Stage 2G verification set runs the live B2 topology without a
frozen Git identity gate or historical replay. It uses an executable Python
reference model, directed SystemVerilog fixtures, current live-runner source
closure, and optional mutation-connected RTL copies.

```text
python tools/run_stage2g_functional_rtl.py --output <fresh-output> --no-mutations
```

## Directed fixtures

| Fixture | Coverage |
|---|---|
| `tb/stage2g/tb_stage2g_core_directed.sv` | Raw CH1/CH2/differential behavior, reset races, source-integrity recovery, production-facing episode behavior |
| `tb/stage2g/tb_stage2g_policy_matrix.sv` | All 64 bitmaps and priority codes, II=1 alignment, first/live/seen invariants, clear fence, sequence wrap, reset at each pipeline offset |
| `tb/stage2g/tb_stage2g_reference_vectors.sv` | Cycle replay of the independent model, including healthy zero evaluations and randomized episodes |
| `tb/stage2g/tb_stage2g_production_path.sv` | Real asynchronous FIFO, AXI W1P clear, source-offer mutation, public recovery snapshots, and safe-output behavior |
| `tb/stage2h/tb_stage2h_b2_destination_sequence.sv` | Connected destination ownership at widths 16/24/32: first zero/nonzero, duplicate, gap/resync, stale/reorder, wrap, policy/observability agreement, clear/recovery, and latency |

The matrix prints `BITMAP_COMBINATIONS=PASS_64_OF_64`,
`PRIORITY_CODE_MATRIX=PASS_64_OF_64`, `II1_ALIGNMENT=PASS`,
`CLEAR_FENCE_MATRIX=PASS`, and `RESET_PIPELINE_FLUSH_MATRIX=PASS`.

## Reference model and longevity

`tools/stage2g_reference_model.py` models modulo-width destination sequence
classification, capture, decision, evaluation, retirement, integrity, episode
fields, clear capture/resolution, reset, and safe output without copying RTL
expressions. The default generated trace has
at least 1,000 completed episodes, sequence wrap, continuous and gapped
traffic, held/repeated clear, resets, and non-clean transactions. The replay
fixture compares every row and every aligned field.

## Mutation-connected checks

`tools/run_stage2g_mutations.py` creates temporary source mutants, compiles the
actual mutated file with the full connected source closure, and requires the
directed oracle to observe a failure. The inventory covers completion-valid
ambiguity, zero-evaluation loss, drop/duplicate/reorder/alignment, priority and
simultaneous-cause loss, first/live/seen corruption, clear-fence races,
unsafe release, source-removal auto-clear, reset flushing, delayed-counter and
W1C gating, and normalized-policy gating. The current escalation retains those
28 policy/episode mutants. Eight recovery-observability mutants cover clear-time
public latch/code loss, false post-clear recovery, no-sample/non-clean
retention, healthy clearing, pre-rearm cause replacement, and internal-state
register wiring. The obsolete 11 core-local sequence mutations are superseded
by the connected B2 destination suite rather than adapted to removed mutable
state. Icarus and XSim are run when requested.

The production fixture exports actual AXI STATUS, FAULT_CODE, CTRL, and current
snapshots. `tools/check_stage2g_recovery_snapshots.py` passes those RTL values
to the unchanged `sw/protection_ip_interface.py::recovery_is_verified()`
predicate. Post-clear RESET_WAIT, no-sample, and non-clean snapshots must be
false; only the later clean healthy ARMED snapshot may be true.

## Static and closure guards

`tools/check_stage2g_implementation.py` is a frozen historical oracle. It
compares modified legacy or public
module interfaces and the complete 25-entry register map to immutable
frozen-base fingerprints. Archive mode consumes those fingerprints without
executing Git. It rejects fixed 32-bit Stage 2G sequence ports, missing
propagation, bit-31 classification, implicit resize warnings, new AXI offsets,
external ports, physical/calibration/watchdog claims, and policy dependencies
on normalized telemetry or diagnostic status. It also fingerprints the
unchanged software recovery predicate, verifies the register bank consumes the
compatibility state, rejects clear-time public status loss, and validates the
17 baseline plus 10 implementation source-map entries and path trace.
`fpga/vivado/build/tests/stage2g_source_closure_tests.tcl` is the current
closure check. It calls the live production runner's RTL and XDC procedures,
checks the B2 destination tracker and source-integrity dependencies, and
validates the generated IP-XACT binding on live `S_AXI/reg0`.

Current live Stage 2G verification uses the repository's normally supported
current Python. Historical replay requires an explicitly supplied frozen source
archive and CPython 3.12.x:

```text
py -3.12 tools/run_stage2g_functional_rtl.py --output <fresh-output> --historical-replay-archive <frozen-stage2g-source.zip>
```

That mode safely extracts the archive and runs the frozen static checker with
`--no-git-check`. CPython 3.12 is required because the immutable historical
oracle contains a Python-version-sensitive interpreter-default `ast.dump`
fingerprint. The newer Stage 2H canonical AST authority does not retroactively
redefine that frozen oracle. Successful evidence prints
`SOURCE_ARCHIVE_STATIC_REPLAY=PASS` and `REPOSITORY_FALLBACK_USED=NO`.

No synthesis, implementation, bitstream, Hardware Manager, or board action is
part of this verification. The fixed three-edge value is an internal ACLK
contract, not a physical end-to-end latency claim.
