# Stage 1 Board Functional Closure Attempt06 Execution Package

## Scope and proof boundary

Attempt06 reuses the accepted Stage 1E BIT/HWH/LTX without changing RTL, the
protection register map, or the accepted workspace. It corrects only the
Vivado 2024.1 host capture-configuration preflight's LTX-binding path.

Attempt01 stopped in the host ILA matcher. Attempt02 passed binding but stopped
when `CONTROL.CAPTURE_MODE` proved read-only. Attempt03 passed its real binding
preflight, then stopped because the capture-configuration preflight reopened
Hardware Manager without binding the accepted LTX; runtime `PROBES.FILE` was
empty. All three attempts remain `NOT_PROVEN`, and none proves a board
protection-function or PWM failure. Read `ATTEMPT01_NON_CLAIM.md`,
`ATTEMPT02_NON_CLAIM.md`, and `ATTEMPT03_NON_CLAIM.md`.

The internal path under test is:

```text
AXI GPIO DATA[23:0]
  -> xlslice_stage1d_ch1 / xlslice_stage1d_ch2
  -> protection i_ch1 / i_ch2
  -> comparator / classifier / FSM
  -> internal pwm_gate
  -> AXI-Lite status plus System ILA
```

`sample_valid` is fixed at zero in the accepted HWH. Sensor-health fault
stimulus is `NOT_SUPPORTED` and must not be reported as PASS.

Safety rules:

- Disconnect real gate drivers, motors, power stages, and external loads.
- The board script writes only AXI GPIO `DATA` and protection `CTRL`.
- It performs one Overlay download and has no automatic retry.
- It never reboots, power-cycles, changes systemd, or programs from Vivado.
- Board timestamps are observed but `UNTRUSTED`; monotonic order and the
  external operator receipt govern chronology.
- Any failure performs bounded fail-closed restoration.

Accepted artifact identities:

| Artifact | SHA-256 |
|---|---|
| BIT | `f7dd0823e577cfee2aecfa3bf0a48e80d11108bdb12967e567ca64dc2e8ecfab` |
| HWH | `c97138493f8c4c568790a75bcc77551ad1f24952f6eb28c4238e6bda975b1e29` |
| LTX | `5cf63856626892ff0483a90eef7531f1c100caabd53b27b49e4d9ca7e06af274` |

## Ordered execution

Do not reorder these gates. A failure stops the attempt without retrying into
an existing package, receipt, or capture path.

### 1. Verify the local ZIP identity

Use the complete values from the external attempt06 preparation receipt:

```powershell
$PackageZip = '<ABSOLUTE_ATTEMPT06_PACKAGE_ZIP>'
$ExpectedZipSha256 = '<ATTEMPT06_PACKAGE_ZIP_SHA256>'
$ManifestSha256 = '<ATTEMPT06_MANIFEST_SHA256>'
$PackageId = '<ATTEMPT06_PACKAGE_ID>'

$Observed = (Get-FileHash -LiteralPath $PackageZip -Algorithm SHA256).Hash.ToLowerInvariant()
if ($Observed -ne $ExpectedZipSha256) {
    throw "Package ZIP SHA-256 mismatch: $Observed"
}
```

### 2. Transfer the immutable ZIP

```powershell
$BoardHost = '<PYNQ_HOST>'
scp -- $PackageZip "xilinx@${BoardHost}:/tmp/${PackageId}.zip"
```

### 3. Run the board package preflight only

This verifies ZIP-extracted package and artifact identities. It does not
execute the functional sequence.

```bash
set -eu
PACKAGE_ID='<ATTEMPT06_PACKAGE_ID>'
MANIFEST_SHA256='<ATTEMPT06_MANIFEST_SHA256>'
PACKAGE_ROOT="/tmp/${PACKAGE_ID}"
RECEIPT_ROOT="/tmp/${PACKAGE_ID}-receipt-06"

test ! -e "$PACKAGE_ROOT"
test ! -e "$RECEIPT_ROOT"
mkdir -m 0700 "$PACKAGE_ROOT"
python3 -m zipfile -e "/tmp/${PACKAGE_ID}.zip" "$PACKAGE_ROOT"
cd "$PACKAGE_ROOT"
printf '%s  %s\n' "$MANIFEST_SHA256" SHA256_MANIFEST.tsv | sha256sum -c -

sudo env XILINX_XRT=/usr \
  /usr/local/share/pynq-venv/bin/python3 \
  board/stage1_board_functional_validation.py \
  --package-root "$PACKAGE_ROOT" \
  --expected-manifest-sha256 "$MANIFEST_SHA256" \
  --preflight-only
```

### 4. Run the host binding preflight

Hardware Server must already be running under explicit user control. This
preflight may bind the accepted LTX but does not program, reset, arm, wait,
upload, or export.

```powershell
$Vivado = '<VIVADO_2024_1_BAT>'
$LocalPackageDir = '<LOCAL_ATTEMPT06_EXTRACTED_PACKAGE_DIR>'
$Ltx = Join-Path $LocalPackageDir 'artifacts\protection_system_board_functional_validation.ltx'

$BindingOutput = @(& $Vivado -mode batch -nolog -nojournal `
  -source "$LocalPackageDir\host\stage1_board_ila_binding_preflight.tcl" `
  -tclargs -ltx $Ltx 2>&1)
$BindingRc = $LASTEXITCODE
$BindingOutput | ForEach-Object { Write-Host $_ }
$BindingTerminalSeen = @($BindingOutput | Where-Object {
    $_.ToString().Trim() -eq 'STAGE1_ILA_BINDING_PREFLIGHT_PASS'
}).Count -gt 0
if ($BindingRc -ne 0 -or -not $BindingTerminalSeen) {
    throw "ILA binding preflight failed; RC=$BindingRc; stop attempt06"
}
Write-Host 'STAGE1_ILA_BINDING_PREFLIGHT_PROCESS_PASS'
```

Process PASS is printed only when Vivado returns RC `0` and its captured output
contains the exact terminal `STAGE1_ILA_BINDING_PREFLIGHT_PASS`.

### 5. Run the capture-configuration preflight

Run this against the same already-running Hardware Server after the binding
preflight. It invokes the exact same shared helper: selects the unique
`xc7z020` device, binds both LTX metadata properties before refresh, validates
the `PROBES.FILE` readback, then proves one accepted ILA with 39 leaf and 11
logical probes. Only then does it read Vivado `report_property` output and
construct all five mode plans. It performs no capture/trigger property write,
ILA reset, arm, wait, upload, export, or programming command.

```powershell
$ConfigurationOutput = @(& $Vivado -mode batch -nolog -nojournal `
  -source "$LocalPackageDir\host\stage1_board_ila_capture_configuration_preflight.tcl" `
  -tclargs -ltx $Ltx 2>&1)
$ConfigurationRc = $LASTEXITCODE
$ConfigurationOutput | ForEach-Object { Write-Host $_ }
$ConfigurationTerminalSeen = @($ConfigurationOutput | Where-Object {
    $_.ToString().Trim() -eq 'STAGE1_ILA_CAPTURE_CONFIGURATION_PREFLIGHT_PASS'
}).Count -gt 0
if ($ConfigurationRc -ne 0 -or -not $ConfigurationTerminalSeen) {
    throw "ILA capture-configuration preflight failed; RC=$ConfigurationRc; stop attempt06"
}
Write-Host 'STAGE1_ILA_CAPTURE_CONFIGURATION_PREFLIGHT_PROCESS_PASS'
```

Required terminals:

```text
STAGE1_ILA_CONFIGURATION_MODE_PLAN_PASS mode=trigger_now
STAGE1_ILA_CONFIGURATION_MODE_PLAN_PASS mode=fault_latched_1
STAGE1_ILA_CONFIGURATION_MODE_PLAN_PASS mode=fsm_reset_wait
STAGE1_ILA_CONFIGURATION_MODE_PLAN_PASS mode=fault_valid_0
STAGE1_ILA_CONFIGURATION_MODE_PLAN_PASS mode=fault_latched_0
STAGE1_ILA_CONFIGURATION_PREFLIGHT_BINDING_PROPERTY_WRITE_COUNT=2
STAGE1_ILA_CONFIGURATION_PREFLIGHT_CAPTURE_TRIGGER_WRITE_COUNT=0
STAGE1_ILA_CONFIGURATION_PREFLIGHT_NO_CAPTURE_TRIGGER_WRITE_PASS
STAGE1_ILA_CAPTURE_CONFIGURATION_PREFLIGHT_PASS
```

The process PASS line is forbidden unless the Vivado RC is `0` and the exact
capture-configuration terminal above was observed. Any nonzero RC stops the
PowerShell block before `PROCESS_PASS`.

Every reported property must use only `SET`, `KEEP_EXISTING`,
`SKIP_READ_ONLY_OPTIONAL`, `FAIL_MISSING_REQUIRED`,
`FAIL_READ_ONLY_REQUIRED`, or `FAIL_INVALID_VALUE`. Any `FAIL_*` action stops
the preflight. A read-only `CONTROL.CAPTURE_MODE=ALWAYS` is expected to be
`KEEP_EXISTING`; it is not written.

### 6. Create one unique attempt06 capture directory

```powershell
$CaptureDir = Join-Path (Get-Location) "${PackageId}-captures-attempt06"
if (Test-Path -LiteralPath $CaptureDir) {
    throw "Refusing to reuse capture directory: $CaptureDir"
}
New-Item -ItemType Directory -Path $CaptureDir -ErrorAction Stop | Out-Null
```

### 7. Start the board sequence once

Only after both host preflights pass:

```bash
sudo env XILINX_XRT=/usr \
  /usr/local/share/pynq-venv/bin/python3 \
  board/stage1_board_functional_validation.py \
  --package-root "$PACKAGE_ROOT" \
  --expected-manifest-sha256 "$MANIFEST_SHA256" \
  --execute \
  --interactive-ila \
  --receipt-dir "$RECEIPT_ROOT"
```

### 8. Perform exactly one capture per checkpoint

| Checkpoint | CSV | Mode |
|---|---|---|
| `normal_pwm` | `normal_pwm.csv` | `trigger_now` |
| `ch1_trip` | `ch1_trip.csv` | `fault_latched_1` |
| `live_clear_rejected` | `live_clear_rejected.csv` | `fsm_reset_wait` |
| `source_removed_preclear` | `source_removed_preclear.csv` | `fault_valid_0` |
| `clear_recovery` | `clear_recovery.csv` | `fault_latched_0` |
| `post_recovery_pwm` | `post_recovery_pwm.csv` | `trigger_now` |
| `ch2_trip` | `ch2_trip.csv` | `fault_latched_1` |
| `differential_trip` | `differential_trip.csv` | `fault_latched_1` |

Conditional modes must print `STAGE1_ILA_ARMED` before the board transition;
they never downgrade to `-trigger_now`. Immediate checkpoints complete the
capture before the operator continues.

```powershell
& $Vivado -mode batch -nolog -nojournal `
  -source "$LocalPackageDir\host\stage1_board_ila_capture.tcl" `
  -tclargs `
  -ltx $Ltx `
  -output (Join-Path $CaptureDir '<CSV_FROM_TABLE>') `
  -mode '<MODE_FROM_TABLE>'
if ($LASTEXITCODE -ne 0) {
    throw 'ILA capture failed; do not continue or retry into this directory'
}
```

The capture tool uses runtime property capability plans. It does not require
or write `CONTROL.CAPTURE_MODE` for `trigger_now`; it uses the current/default
capture filtering. The four conditional modes require exact probe
comparators. The strict sequence is configuration, arm, wait, upload, unique
ILA-data selection, partial CSV export, nonempty verification, and sealing.

### 9. Copy the complete board receipt without editing it

```powershell
$LocalEvidence = Join-Path (Get-Location) "${PackageId}-evidence-attempt06"
if (Test-Path -LiteralPath $LocalEvidence) {
    throw "Refusing to reuse evidence directory: $LocalEvidence"
}
New-Item -ItemType Directory -Path $LocalEvidence -ErrorAction Stop | Out-Null
scp -r -- "xilinx@${BoardHost}:/tmp/${PackageId}-receipt-06" $LocalEvidence
```

### 10. Run the analyzer

```powershell
$AnalysisDir = Join-Path (Get-Location) "${PackageId}-analysis-attempt06"
if (Test-Path -LiteralPath $AnalysisDir) {
    throw "Refusing to reuse analysis directory: $AnalysisDir"
}
New-Item -ItemType Directory -Path $AnalysisDir -ErrorAction Stop | Out-Null

python "$LocalPackageDir\host\stage1_board_evidence_analyzer.py" `
  --board-result '<COPIED_RECEIPT_DIR>\execution_result.json' `
  --capture-dir $CaptureDir `
  --output "$AnalysisDir\stage1_board_functional_result.json"
```

Final PASS may only come from the analyzer after eight real, nonempty,
Vivado-generated CSVs pass. Keep the `Radix - ...` row intact.

### 11. Seal the new attempt

Hash and preserve the package ZIP, manifest, board receipt, every CSV and
metadata TSV, analyzer result, and the external operator date. Do not edit,
rename into attempt01/attempt02/attempt03 paths, or reuse any directory. A new
retry requires a new package and receipt identity.
