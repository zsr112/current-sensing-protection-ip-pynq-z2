# Current-Sensing Protection IP

Source architecture, capability boundaries and v2r3 status:
[Current architecture](publication/docs/architecture/current_architecture.md).
The G1 source snapshot predates the v2r3 physical build and board validation.
For the exact executions, final validation and project-owner decision, read
`VERSION.json`, `EVIDENCE_ANNEX.json` and `ACCEPTANCE.json`. Existing v2r2
evidence keeps its original identity.
`SOURCE_MANIFEST.json` binds the exact physical build inputs. Later publication
tools have a separate commit in `publication_origin`; differing copies live in
`publication/` and never overwrite those build inputs. Log derivatives retain
original/delivered hashes and escape non-UTF-8 bytes; raw ILA and artifacts are unchanged.


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
source and artifact identities, report findings, all 20 original ILA CSVs,
the three-platform online CI record, the Windows validation record, the Mac
frozen-payload validation and the bounded `PROJECT_OWNER_ACCEPTED` decision.
This rechecks recorded evidence; it does not execute a new FPGA build or board test.

`PAYLOAD_MANIFEST.json` freezes the files independently validated on Mac before
`ACCEPTANCE.json` is written. A final ZIP cannot contain a truthful hash of
itself because adding that record changes the hash. Final ZIP byte validation is
therefore external. Before Tag movement, merge or GitHub Release publication,
both Windows and Mac must independently run:

```text
python -B tools/verify_post_seal_release.py stage2-self-contained-v2r3.zip --output stage2-self-contained-v2r3.<platform>-post-seal.json --platform <WINDOWS-or-MACOS> --validation-id <unique-id>
python -B tools/verify_post_seal_release.py stage2-self-contained-v2r3.zip --receipt stage2-self-contained-v2r3.windows-post-seal.json --receipt stage2-self-contained-v2r3.macos-post-seal.json
```

The external receipts bind the exact final ZIP SHA-256, extracted acceptance,
frozen payload manifest, ZIP integrity and a fresh self-verification. They must
remain beside the ZIP and must never be inserted into or written back to it.

## Deploy The Verified Overlay

Transfer the complete `deploy` directory to PYNQ-Z2. On the board:

```text
python3 -B deploy/load.py
sudo env XILINX_XRT=/usr /usr/local/share/pynq-venv/bin/python3 -B deploy/load.py --execute --output ./new-deployment-run
```

The first command is offline verification of the deployment inventory and its
copy of `ACCEPTANCE.json`. The explicit load checks the live
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

The included execution has `REBUILT=PASS`, `BOARD_VERIFIED=PASS` for eight
required and two supporting scenarios, and `FINAL_VERIFIED=PASS`.
`ACCEPTANCE.json`, `PAYLOAD_MANIFEST.json`, `EVIDENCE_ANNEX.json` and
`EVIDENCE_PROVENANCE.json` bind the build, board, pre-seal final, online CI,
source, tool, artifact and manifest identities. Acceptance also declares the
external two-platform post-seal gate; it does not claim that self-referential
final-ZIP evidence is embedded in the archive.
Raw BIT/HWH/LTX and ILA CSV bytes are preserved. Reports containing local paths
have explicitly identified portable derivatives with separate original hashes.
Full original workspaces, XSA and logs remain in the indexed local data archive.

CDC-4 remains **Critical**. Its bounded FIFO engineering review is included;
warnings have not been waived or reclassified. Formal acceptance is
`PROJECT_OWNER_ACCEPTED` by `PROJECT_OWNER_INTERNAL_REVIEW` for
`V2R3_DIGITAL_RELEASE`. This bounded decision does not claim the real ADC input
chain, actual calibration, external-pin PWM, external power stage, persistent
boot, long-duration soak or analog-system validation; those remain `NOT_RUN`.
Stage 3 has not started.
This is an engineering/research prototype, not a production protection system.

AMD tools, device libraries and generated vendor IP retain their respective
license terms and are not redistributed as tool installations. Use an appropriate
Vivado license for the target. The project currently has no separate open-source
license grant; no new license is asserted by this delivery. Historical releases,
frozen tags and accepted evidence retain their original identities.
