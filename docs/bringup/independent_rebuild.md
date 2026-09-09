# Independent source rebuild

The R4 v1 deployment snapshot remains a separate, immutable evidence authority.
Rebuilding its design creates new artifacts; R4 board verification does not apply
to their new hashes. Formal project acceptance remains NOT_FORMALLY_ACCEPTED.

## Dependencies

- Python 3.10 or newer, including Tcl/Tk, for tools and fixture tests. The full
  historical source replay is optional and has its own Python 3.12 requirement.
- Icarus Verilog 12.x (`iverilog` and `vvp`) from the Icarus project or MSYS2.
- Vivado 2024.1, build 5076996, with Zynq-7000 device support, from AMD.
  Use a license appropriate to the installed edition and device. Licenses and
  vendor tools are not redistributed. Mac can run Python and Icarus checks;
  this project's supervised Vivado entrypoint requires Windows and PowerShell 7.
- PYNQ-Z2 board files, board part `tul.com.tw:pynq-z2:part0:1.0`, from
  https://github.com/Xilinx/XilinxBoardStore/tree/2024.1/boards/TUL .
  Install them in Vivado or configure `board_repo` explicitly. Board file hashes
  are recorded when an explicit board repository is supplied.
- PYNQ 3.1.1 / Python 3.10.4 was the R4 board environment. A new board run must
  record the actual board, image, Python and PYNQ versions before programming.
- Git is used to create an export from the engineering repository. Exported
  source verification and the clean physical build use SHA-256 and do not need
  a Git object database. Tests specifically exercising Git require Git.

## Configuration

Precedence is command line, `CSIP_*` environment, toolchain JSON, then PATH.
Select JSON with `--config` or `CSIP_CONFIG`; the optional repository default is
`config/toolchain.json`. Values are strings. A relative path in the JSON resolves
against its containing directory. Malformed JSON and invalid explicit tools
are errors. Keep machine-specific JSON outside the public delivery.

Supported keys are `vivado_bin`, `iverilog`, `vvp`, `pwsh`, `board_repo`, and
`build_root`. `CSIP_BUILD_ROOT` is required when `--build-root` is omitted; a build
root must be fresh and outside the source tree. Keep the build root short enough
for Vivado's checked generated-path budget. No previous cache is imported.

## Export and Execute

Create the export from a clean committed engineering checkout:

```text
python -B tools/source_export.py --output ../source-export
python -B tools/source_export.py --selection config/self_contained_source.json --output ../selected-source
```

The export preserves committed bytes and records a complete file manifest.
Its origin commit/tree describe provenance; they are not a fabricated local
Git checkout. Local inventory exports are not automatically public deliveries:
publication must separately pass the source-scope and private-path audit.
The committed selection profile records included families, excluded historical
material and mandatory inputs. The selected export preserves the original
directory relationships and exact committed file bytes; it does not rewrite
source while packaging. Its dependency closure is validated by fresh execution.

From the exported directory:

```text
python -B tools/source_export.py
python -B tools/rebuild.py preflight --config ../toolchain.json
python -B tools/rebuild.py all --config ../toolchain.json --build-root ../fresh-build --execution-id CSIP-SC-V2-B2-001 --profile READY_AWARE_SYNTHETIC_DIGITAL_STIMULUS
```

The default physical profile is B1 `SAFE_INERT`. Select B2 explicitly for the
synthetic digital producer and its two ILA cores. B1 and B2 are distinct builds.
Digital-only and Vivado-only runs use `digital` and `vivado` respectively, each
with a fresh build root and execution ID.

`rebuild_receipt.json` records the input manifest, origin, tool versions, command
outcomes, output hashes and source recheck. Process completion is not timing,
DRC, CDC or methodology acceptance. Review reports separately and retain all
original severities. A new build starts with BOARD_VERIFIED=NOT_RUN.

## Board and Acceptance

Use the board package builder and session tools in `tools/board_validation` to
bind new BIT/HWH/LTX/XSA identities to a new board campaign. The eight required
and two supporting scenarios require raw source and destination ILA CSVs,
probe and trigger settings, logs, and an analyzed receipt. See
[Windows board sessions](windows_board_session.md).

Real ADC, external-pin PWM, external power stage, persistent boot and soak
remain NOT_RUN. A successful synthetic campaign does not expand this boundary.
