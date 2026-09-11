# Current-Sensing Protection IP

Current maintenance architecture, capability boundaries and G1 status:
[Current architecture](docs/architecture/current_architecture.md).
G1 is tool/CI/documentation maintenance; new physical build, board campaign and
candidate verification are NOT_RUN. Existing v2r2 evidence keeps its original identity.


Stage 2 engineering delivery for PYNQ-Z2. The repository contains the complete
source inputs used for independent digital regression and Vivado reconstruction
as ordinary files under `rtl`, `fpga`, `sw`, `tb`, `spec`, `sim` and `tools`.
Source is maintained in the engineering repository and synchronized here by the
versioned delivery generator. Build caches and historical Git objects are not
dependencies. `VERSION.json` identifies the exact source and executions, with
the hardware input commit and later publication tooling commit recorded separately.

## Verify This Delivery

```text
python -B verify.py
```

Python 3.10 or later is sufficient. The verifier checks every delivered file,
source and artifact identities, report findings, and all 20 original ILA CSVs.
This rechecks recorded evidence; it does not execute a new FPGA build or board test.

## Deploy The Verified Overlay

Transfer the complete `deploy` directory to PYNQ-Z2. On the board:

```text
python3 -B deploy/load.py
sudo env XILINX_XRT=/usr /usr/local/share/pynq-venv/bin/python3 -B deploy/load.py --execute --output ./new-deployment-run
```

The first command is offline verification. The explicit load checks the live
ABI, IP map and 100/125 MHz clocks and leaves PWM disabled. It records a new
load receipt and does not claim a new board verification campaign. The reference
board environment was PYNQ 3.1.1, Python 3.10.4 and PynqLinux 3.0.

## Rebuild From Source

Install Python, Icarus Verilog, PowerShell 7 and Vivado 2024.1 build 5076996
with Zynq-7000 support. Install PYNQ-Z2 board files for
`tul.com.tw:pynq-z2:part0:1.0`, available from the AMD/Xilinx Board Store.
The tools and board files are external toolchain dependencies, not project data.
See [environment and configuration](docs/bringup/independent_rebuild.md).
This release was actually tested with Python 3.12.10, Icarus 13.0 and
PowerShell 7.6.5. The source reference guide's earlier Icarus 12.x recommendation
is not an additional simulator-version test claim for this execution.

```text
python -B tools/rebuild_delivery.py preflight --config ../toolchain.json --build-root ../preflight-run
python -B tools/rebuild_delivery.py all --config ../toolchain.json --build-root ../fresh-run --execution-id MY-NEW-B2-RUN --profile READY_AWARE_SYNTHETIC_DIGITAL_STIMULUS
```

Each build root must be new, external and short enough for the checked Windows
Vivado path budget. The wrapper verifies the delivered source files and creates
an isolated source directory and fresh outputs there. It uses no main-repository
checkout, external evidence/data directory, Git database or old cache.
Configuration precedence is command line, `CSIP_*` environment, JSON, then PATH.
JSON paths are relative to the JSON file. Output and source hashes are recorded.

The default B1 `SAFE_INERT` profile has no active sample producer. B2 is the
explicit synthetic digital test profile above; the two are distinct configurations.
Mac can run Python/Icarus checks; this Vivado execution flow requires Windows.

Newly generated BIT/HWH/LTX/XSA files start with `BOARD_VERIFIED=NOT_RUN`.
Use `tools/board_validation/build_stage2_board_session.py` and the
[board session workflow](docs/bringup/windows_board_session.md) with a new
execution ID to test new artifacts and retain raw ILA/configuration/run records.

## Evidence And Limits

The included execution has `REBUILT=PASS` and `BOARD_VERIFIED=PASS` for eight
required and two supporting scenarios. `EVIDENCE_ANNEX.json` and
`EVIDENCE_PROVENANCE.json` bind source, tool versions, artifacts and receipts.
Raw BIT/HWH/LTX and ILA CSV bytes are preserved. Reports containing local paths
have explicitly identified portable derivatives with separate original hashes.
Full original workspaces, XSA and logs remain in the indexed local data archive.

CDC-4 remains **Critical**. Its bounded FIFO engineering review is included;
warnings have not been waived or reclassified. Formal project acceptance remains
`NOT_FORMALLY_ACCEPTED`. Real ADC, external-pin PWM, external power stage,
persistent boot and soak testing are `NOT_RUN`. Stage 3 has not started.
This is an engineering/research prototype, not a production protection system.

AMD tools, device libraries and generated vendor IP retain their respective
license terms and are not redistributed as tool installations. Use an appropriate
Vivado license for the target. The project currently has no separate open-source
license grant; no new license is asserted by this delivery. Historical releases,
frozen tags and accepted evidence retain their original identities.
