[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputRoot,

    [switch]$RequireClean,

    [string]$VivadoBin = $env:CSIP_VIVADO_BIN
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$BaseCommit = "3399e4fdc28f9d4c66cf90cb5c1dc1e386eda6ae"
$PreviousImplementationCommit = "1e93cda247a80d2fdd9186a2e21cc90777abeaec"
$ExpectedBranch = "codex/stage2f-digital-encoding-normalization"
$AllowedOutputBase = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($OutputRoot))
if (-not $VivadoBin) { $VivadoBin = Split-Path (Get-Command vivado -ErrorAction Stop).Source }

function Normalize-Path {
    param([Parameter(Mandatory = $true)][string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetPathRoot($full)
    if ($full.Equals($root, [StringComparison]::OrdinalIgnoreCase)) {
        return $root
    }
    return $full.TrimEnd([char[]]"\/")
}

function New-Dir {
    param([Parameter(Mandatory = $true)][string]$Path)
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

function Write-Lines {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines
    )
    [IO.File]::WriteAllLines($Path, $Lines, [Text.UTF8Encoding]::new($false))
}

function Invoke-Tool {
    param(
        [Parameter(Mandatory = $true)][string]$Exe,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][string]$LogPath
    )
    Push-Location $WorkingDirectory
    $saved = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = @(& $Exe @Arguments 2>&1)
        $code = [int]$LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $saved
        Pop-Location
    }
    $lines = @($output | ForEach-Object { [string]$_ })
    Write-Lines -Path $LogPath -Lines $lines
    return [PSCustomObject]@{
        ExitCode = $code
        Text = ($lines -join "`n")
        LogPath = $LogPath
    }
}

function Assert-Pass {
    param([Parameter(Mandatory = $true)]$Result, [Parameter(Mandatory = $true)][string]$Label)
    if ($Result.ExitCode -ne 0) {
        throw "$Label failed (exit=$($Result.ExitCode)); log=$($Result.LogPath)"
    }
}

function Assert-Marker {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][string]$Marker,
        [Parameter(Mandatory = $true)][string]$Label
    )
    if ($Text -notmatch [regex]::Escape($Marker)) {
        throw "$Label omitted marker '$Marker'; log output is incomplete"
    }
}

function Git-State {
    param([Parameter(Mandatory = $true)][string]$Root)
    $head = (@(& git -C $Root rev-parse HEAD) -join "").Trim()
    if ($LASTEXITCODE -ne 0) { throw "Unable to resolve Git HEAD" }
    $branch = (@(& git -C $Root branch --show-current) -join "").Trim()
    if ($LASTEXITCODE -ne 0) { throw "Unable to resolve Git branch" }
    $status = @(& git -C $Root status --porcelain --untracked-files=all)
    if ($LASTEXITCODE -ne 0) { throw "Unable to inspect Git status" }
    $rows = @($status | ForEach-Object { ([string]$_).TrimEnd() } |
        Where-Object { $_ -ne "" })
    return [PSCustomObject]@{
        Head = $head
        Branch = $branch
        Clean = ($rows.Count -eq 0)
        Status = $rows
    }
}

function Compile-Icarus {
    param(
        [Parameter(Mandatory = $true)][string]$Top,
        [Parameter(Mandatory = $true)][string[]]$Sources,
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$Directory
    )
    New-Dir $Directory
    $image = Join-Path $Directory "$Label.vvp"
    $compile = Invoke-Tool -Exe $Iverilog -Arguments (@(
        "-g2012", "-I", $RtlDirectory, "-s", $Top, "-o", $image
    ) + $Sources) -WorkingDirectory $Directory `
        -LogPath (Join-Path $Directory "$Label.compile.log")
    Assert-Pass $compile "$Label Icarus compile"
    return Invoke-Tool -Exe $Vvp -Arguments @($image) -WorkingDirectory $Directory `
        -LogPath (Join-Path $Directory "$Label.run.log")
}

function Compile-Xsim {
    param(
        [Parameter(Mandatory = $true)][string]$Top,
        [Parameter(Mandatory = $true)][string[]]$Sources,
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$Directory
    )
    New-Dir $Directory
    $xvlog = Invoke-Tool -Exe $Xvlog -Arguments (@(
        "--sv", "-i", $RtlDirectory, "--log", (Join-Path $Directory "$Label.xvlog.log")
    ) + $Sources) -WorkingDirectory $Directory `
        -LogPath (Join-Path $Directory "$Label.xvlog.console.log")
    Assert-Pass $xvlog "$Label XSim compile"
    $snapshot = "${Label}_snapshot"
    $xelab = Invoke-Tool -Exe $Xelab -Arguments @(
        "work.$Top", "-s", $snapshot, "--timescale", "1ns/1ps",
        "--log", (Join-Path $Directory "$Label.xelab.log")
    ) -WorkingDirectory $Directory `
        -LogPath (Join-Path $Directory "$Label.xelab.console.log")
    Assert-Pass $xelab "$Label XSim elaboration"
    return Invoke-Tool -Exe $Xsim -Arguments @(
        $snapshot, "-runall", "--onerror", "quit", "--onfinish", "quit",
        "--log", (Join-Path $Directory "$Label.xsim.log")
    ) -WorkingDirectory $Directory `
        -LogPath (Join-Path $Directory "$Label.xsim.console.log")
}

function Run-PythonScript {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$Directory
    )
    New-Dir $Directory
    return Invoke-Tool -Exe $Python -Arguments $Arguments -WorkingDirectory $RepoRoot `
        -LogPath (Join-Path $Directory "$Label.log")
}

function Run-Tcl {
    param([Parameter(Mandatory = $true)][string]$RelativeScript, [Parameter(Mandatory = $true)][string]$Label)
    $directory = Join-Path $TclRoot ($Label.ToLowerInvariant())
    New-Dir $directory
    return Invoke-Tool -Exe $Tcl -Arguments @((Join-Path $RepoRoot $RelativeScript)) `
        -WorkingDirectory $RepoRoot -LogPath (Join-Path $directory "$Label.log")
}

$RepoRoot = Normalize-Path (Join-Path $PSScriptRoot "..\..")
$OutputRoot = Normalize-Path $OutputRoot
$AllowedOutputBase = Normalize-Path $AllowedOutputBase
$repoPrefix = $RepoRoot + "\"
$outputPrefix = $AllowedOutputBase + "\"
if ($OutputRoot.Equals($RepoRoot, [StringComparison]::OrdinalIgnoreCase) -or
    $OutputRoot.StartsWith($repoPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputRoot must be outside the Git worktree"
}
if (-not $OutputRoot.StartsWith($outputPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputRoot must be below $AllowedOutputBase"
}
if (Test-Path -LiteralPath $OutputRoot) {
    throw "OutputRoot must not exist before the run: $OutputRoot"
}

$start = Git-State $RepoRoot
if ($start.Branch -cne $ExpectedBranch) { throw "Unexpected branch: $($start.Branch)" }
& git -C $RepoRoot merge-base --is-ancestor $BaseCommit $start.Head
if ($LASTEXITCODE -ne 0) { throw "HEAD is not descended from the required base commit" }
& git -C $RepoRoot merge-base --is-ancestor $PreviousImplementationCommit $start.Head
if ($LASTEXITCODE -ne 0) { throw "HEAD is not descended from the previous implementation commit" }
$localMain = (@(& git -C $RepoRoot rev-parse main) -join "").Trim()
$remoteMain = (@(& git -C $RepoRoot rev-parse refs/remotes/origin/main) -join "").Trim()
if ($localMain -cne $BaseCommit -or $remoteMain -cne $BaseCommit) {
    throw "local main/origin main does not match the frozen base"
}
if ($RequireClean -and -not $start.Clean) { throw "RequireClean was requested but worktree is dirty" }

$Iverilog = (Get-Command iverilog.exe -ErrorAction Stop).Source
$Vvp = (Get-Command vvp.exe -ErrorAction Stop).Source
$Python = (Get-Command python.exe -ErrorAction Stop).Source
$Bash = $env:CSIP_BASH
if (-not $Bash) { $Bash = (Get-Command bash -ErrorAction Stop).Source }
$Tcl = Join-Path $VivadoBin "xtclsh.bat"
$Xvlog = Join-Path $VivadoBin "xvlog.bat"
$Xelab = Join-Path $VivadoBin "xelab.bat"
$Xsim = Join-Path $VivadoBin "xsim.bat"
foreach ($tool in @($Tcl, $Xvlog, $Xelab, $Xsim)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw "Missing tool: $tool" }
}

New-Dir $OutputRoot
$IcarusRoot = Join-Path $OutputRoot "icarus"
$XsimRoot = Join-Path $OutputRoot "xsim"
$TclRoot = Join-Path $OutputRoot "tcl"
$PythonRoot = Join-Path $OutputRoot "python"
$StaticRoot = Join-Path $OutputRoot "static"
foreach ($directory in @($IcarusRoot, $XsimRoot, $TclRoot, $PythonRoot, $StaticRoot)) {
    New-Dir $directory
}
Write-Lines (Join-Path $OutputRoot "git_status_start.txt") (@(
    "BRANCH=$($start.Branch)", "HEAD=$($start.Head)", "CLEAN=$($start.Clean)",
    "PORCELAIN_BEGIN"
) + $start.Status + @("PORCELAIN_END"))

$RtlDirectory = Join-Path $RepoRoot "rtl"
$TbStage2f = Join-Path $RepoRoot "tb\stage2f"
function Rtl([string]$Name) { return (Join-Path $RtlDirectory $Name) }
function Tb2f([string]$Name) { return (Join-Path $TbStage2f $Name) }

$CoreRtl = @(
    (Rtl "reset_release_sync.v"), (Rtl "async_fifo_gray.v"),
    (Rtl "transaction_source_observer.v"), (Rtl "adc_sample_cdc_bridge.v"),
    (Rtl "current_compare_dual.v"), (Rtl "sensor_health_monitor.v"),
    (Rtl "fault_classifier.v"), (Rtl "protection_fsm.v"),
    (Rtl "pwm_gen.v"), (Rtl "pwm_gate.v"), (Rtl "protection_core_top.v")
)
$FullRtl = $CoreRtl + @(
    (Rtl "adc_sample_code_normalizer.sv"), (Rtl "source_observability_cdc.v"),
    (Rtl "transaction_destination_observer.v"), (Rtl "protection_reg_bank.v"),
    (Rtl "protection_ip_top_reg_controlled.v"), (Rtl "protection_ip_top_axi_lite.v"),
    (Rtl "protection_ip_top_async_adc_axi_lite.v")
)

# Profile/reference/static gates.
$result = Run-PythonScript @("tools/build_stage2f_digital_review.py", "self-test") "review_builder_self_test" $StaticRoot
Assert-Pass $result "Stage 2F evidence/review builder self-test"
Assert-Marker $result.Text "STAGE2F_DIGITAL_REVIEW_SELF_TEST=PASS" "Stage 2F evidence/review builder self-test"
$result = Run-PythonScript @("tools/check_stage2f_implementation.py") "implementation_static" $StaticRoot
Assert-Pass $result "Stage 2F implementation static checker"
Assert-Marker $result.Text "STAGE2F_IMPLEMENTATION_STATIC=PASS" "Stage 2F implementation static checker"
$result = Run-PythonScript @("tools/generate_stage2f_adc_profile.py", "--profile", "spec/stage2f_adc_source_profile_unconfigured.json", "--check") "profile_generation" $StaticRoot
Assert-Pass $result "Stage 2F profile generation"
Assert-Marker $result.Text "STAGE2F_PROFILE_GENERATION=PASS" "Stage 2F profile generation"
$result = Run-PythonScript @("tools/stage2f_adc_contract_audit.py", "--root", ".", "--no-git-check", "--no-reference-check") "frozen_contract_audit" $StaticRoot
Assert-Pass $result "Frozen Stage 2F contract audit"
Assert-Marker $result.Text "STAGE2F_ADC_CONTRACT_AUDIT=PASS" "Frozen Stage 2F contract audit"

$result = Run-PythonScript @("-m", "unittest", "tools.tests.test_stage2f_profile_generator", "tools.tests.test_stage2f_adc_contract_audit", "-v") "stage2f_python_tests" $PythonRoot
Assert-Pass $result "Stage 2F Python tests"
$result = Run-PythonScript @("-m", "unittest", "discover", "-s", "tests", "-v") "repository_python_tests" $PythonRoot
Assert-Pass $result "Repository Python tests"
$result = Run-PythonScript @("-m", "unittest", "discover", "-s", "sw/tests", "-v") "software_python_tests" $PythonRoot
Assert-Pass $result "Software Python tests"

$result = Run-PythonScript @("tools/stage2f_normalization_reference.py") "python_reference_exhaustive" $PythonRoot
Assert-Pass $result "Stage 2F Python exhaustive reference"
Assert-Marker $result.Text "PYTHON_REFERENCE_EXHAUSTIVE=PASS_57344_CASES" "Stage 2F Python exhaustive reference"
Assert-Marker $result.Text "PYTHON_REFERENCE_MUTATIONS=PASS_5_OF_5" "Stage 2F Python reference mutations"

$result = Run-PythonScript @(
    "tools/run_stage2f_generated_profile_rtl.py", "--output",
    (Join-Path $OutputRoot "generated_profile_rtl"), "--xsim"
) "generated_profile_rtl" $StaticRoot
Assert-Pass $result "Stage 2F generated-profile RTL matrix"
Assert-Marker $result.Text "GENERATED_PROFILE_RTL_MATRIX=PASS_6_OF_6_ICARUS_AND_XSIM" "Stage 2F generated-profile RTL matrix"
Assert-Marker $result.Text "PYTHON_REFERENCE_TO_RTL_COMPARISON=PASS" "Stage 2F Python-to-RTL comparison"
Assert-Marker $result.Text "PRODUCTION_INCLUDE_CURRENT=PASS" "Stage 2F production include current"

$result = Run-PythonScript @(
    "tools/run_stage2f_generator_mutations.py", "--output",
    (Join-Path $OutputRoot "generator_mutations"), "--xsim"
) "generator_mutations" $StaticRoot
Assert-Pass $result "Stage 2F generator-to-RTL mutations"
Assert-Marker $result.Text "GENERATOR_TO_RTL_PROFILE_FIXTURES=PASS_12_OF_12" "Stage 2F generator-to-RTL mutations"

$result = Run-PythonScript @(
    "tools/run_stage2f_width_sequence_boundary.py", "--output",
    (Join-Path $OutputRoot "width_sequence_boundary"), "--xsim"
) "width_sequence_boundary" $StaticRoot
Assert-Pass $result "Stage 2F width/sequence boundary"
Assert-Marker $result.Text "WIDTH_SEQUENCE_BOUNDARY=PASS" "Stage 2F width/sequence boundary"
Assert-Marker $result.Text "IMPLICIT_NORMALIZER_PORT_RESIZE=NO" "Stage 2F normalizer width binding"

$result = Run-PythonScript @(
    "tools/run_stage2f_boundary_mutations.py", "--output",
    (Join-Path $OutputRoot "boundary_mutations"), "--xsim"
) "boundary_mutations" $StaticRoot
Assert-Pass $result "Stage 2F boundary mutations"
Assert-Marker $result.Text "NEW_BOUNDARY_MUTATION_FIXTURES=PASS_6_OF_6" "Stage 2F boundary mutations"

# Stage 2F direct, mutation, and frozen raw-path comparisons.
$normalizerSources = @((Rtl "adc_sample_code_normalizer.sv"), (Tb2f "tb_stage2f_digital_normalization.sv"))
$result = Compile-Icarus "tb_stage2f_digital_normalization" $normalizerSources "stage2f_directed" (Join-Path $IcarusRoot "stage2f_directed")
Assert-Pass $result "Stage 2F Icarus directed/exhaustive/random"
Assert-Marker $result.Text "STAGE2F_DIGITAL_NORMALIZATION=PASS" "Stage 2F Icarus directed/exhaustive/random"
Assert-Marker $result.Text "STAGE2F_NO_DROP=PASS_INPUT_CYCLES=9402_OUTPUT_CYCLES=9402" "Stage 2F Icarus no-drop"
Assert-Marker $result.Text "STAGE2F_RANDOM_RESET_POINTS=PASS_3" "Stage 2F Icarus randomized reset"
$result = Compile-Xsim "tb_stage2f_digital_normalization" $normalizerSources "stage2f_directed" (Join-Path $XsimRoot "stage2f_directed")
Assert-Pass $result "Stage 2F XSim directed/exhaustive/random"
Assert-Marker $result.Text "STAGE2F_DIGITAL_NORMALIZATION=PASS" "Stage 2F XSim directed/exhaustive/random"
Assert-Marker $result.Text "STAGE2F_NO_DROP=PASS_INPUT_CYCLES=9402_OUTPUT_CYCLES=9402" "Stage 2F XSim no-drop"
Assert-Marker $result.Text "STAGE2F_RANDOM_RESET_POINTS=PASS_3" "Stage 2F XSim randomized reset"

$result = Run-PythonScript @("tools/run_stage2f_mutations.py", "--output", (Join-Path $OutputRoot "mutations_icarus")) "mutations_icarus" $StaticRoot
Assert-Pass $result "Stage 2F Icarus mutation matrix"
Assert-Marker $result.Text "STAGE2F_MUTATION_TESTS=PASS_14_CONNECTED" "Stage 2F Icarus mutation matrix"
$result = Run-PythonScript @("tools/run_stage2f_mutations.py", "--output", (Join-Path $OutputRoot "mutations_xsim"), "--xsim") "mutations_xsim" $StaticRoot
Assert-Pass $result "Stage 2F XSim mutation matrix"
Assert-Marker $result.Text "STAGE2F_MUTATION_TESTS=PASS_28_CONNECTED" "Stage 2F XSim mutation matrix"
$result = Run-PythonScript @("tools/run_stage2f_raw_path_invariance.py", "--output", (Join-Path $OutputRoot "raw_invariance_icarus")) "raw_invariance_icarus" $StaticRoot
Assert-Pass $result "Stage 2F Icarus raw-path invariance"
Assert-Marker $result.Text "STAGE2F_RAW_PATH_INVARIANCE=PASS_1" "Stage 2F Icarus raw-path invariance"
$result = Run-PythonScript @("tools/run_stage2f_raw_path_invariance.py", "--output", (Join-Path $OutputRoot "raw_invariance_xsim"), "--xsim") "raw_invariance_xsim" $StaticRoot
Assert-Pass $result "Stage 2F XSim raw-path invariance"
Assert-Marker $result.Text "STAGE2F_RAW_PATH_INVARIANCE=PASS_2" "Stage 2F XSim raw-path invariance"

# Existing Stage 2B/2C/2D/2E Icarus regressions. The normalizer is included in
# the full-wrapper sources but is not connected to these raw protection inputs.
$stage2dTb = Join-Path $RepoRoot "tb\stage2d\tb_stage2d_async_adc_atomic_cdc.sv"
$stage2dWrapperTb = Join-Path $RepoRoot "tb\stage2d\tb_stage2d_production_wrapper.sv"
$stage2eTb = Join-Path $RepoRoot "tb\stage2e\tb_stage2e_transaction_error_observability.sv"
$stage2bTb = Join-Path $RepoRoot "tb\stage2b\tb_stage2b_unified_sample_acceptance.sv"
$stage2cTb = Join-Path $RepoRoot "tb\stage2c\tb_stage2c_reset_release_cdc.sv"
$result = Compile-Icarus "tb_stage2d_async_adc_atomic_cdc" ($CoreRtl + @($stage2dTb)) "stage2d_regression" (Join-Path $IcarusRoot "stage2d")
Assert-Pass $result "Stage 2D Icarus regression"
Assert-Marker $result.Text "STAGE2D_POSITIVE_SCENARIOS=PASS_30_OF_30" "Stage 2D Icarus regression"
Assert-Marker $result.Text "SCOREBOARD_PENDING=0" "Stage 2D Icarus scoreboard"
$result = Compile-Icarus "tb_stage2d_production_wrapper" ($FullRtl + @($stage2dWrapperTb)) "stage2d_wrapper" (Join-Path $IcarusRoot "stage2d_wrapper")
Assert-Pass $result "Stage 2D wrapper Icarus regression"
Assert-Marker $result.Text "PRODUCTION_WRAPPER_INTEGRATION=PASS" "Stage 2D wrapper Icarus regression"
$result = Compile-Icarus "tb_stage2e_transaction_error_observability" ($FullRtl + @($stage2eTb)) "stage2e_regression" (Join-Path $IcarusRoot "stage2e")
Assert-Pass $result "Stage 2E Icarus regression"
Assert-Marker $result.Text "STAGE2E_POSITIVE_SCENARIOS=PASS_35_OF_35" "Stage 2E Icarus regression"
$result = Compile-Icarus "tb_stage2b_unified_sample_acceptance" @(
    (Rtl "current_compare_dual.v"), (Rtl "sensor_health_monitor.v"),
    (Rtl "fault_classifier.v"), (Rtl "protection_fsm.v"), (Rtl "pwm_gen.v"),
    (Rtl "pwm_gate.v"), (Rtl "protection_core_top.v"),
    (Join-Path $RepoRoot "tb\stage2b\stage2b_sample_acceptance_checker.sv"), $stage2bTb
) "stage2b_regression" (Join-Path $IcarusRoot "stage2b")
Assert-Pass $result "Stage 2B Icarus regression"
Assert-Marker $result.Text "TOTAL_POSITIVE_SCENARIOS=PASS_26_OF_26" "Stage 2B Icarus regression"
$result = Compile-Icarus "tb_stage2c_reset_release_cdc" ($FullRtl + @(
    (Join-Path $RepoRoot "tb\stage2c\stage2c_reset_release_checker.sv"), $stage2cTb
)) "stage2c_regression" (Join-Path $IcarusRoot "stage2c")
Assert-Pass $result "Stage 2C Icarus regression"
Assert-Marker $result.Text "STAGE2C_POSITIVE_SCENARIOS=PASS_27_OF_27" "Stage 2C Icarus regression"

# XSim raw regressions for the two widest wrapper benches.
$result = Compile-Xsim "tb_stage2d_async_adc_atomic_cdc" ($CoreRtl + @($stage2dTb)) "stage2d_regression" (Join-Path $XsimRoot "stage2d")
Assert-Pass $result "Stage 2D XSim regression"
Assert-Marker $result.Text "STAGE2D_POSITIVE_SCENARIOS=PASS_30_OF_30" "Stage 2D XSim regression"
$result = Compile-Xsim "tb_stage2e_transaction_error_observability" ($FullRtl + @($stage2eTb)) "stage2e_regression" (Join-Path $XsimRoot "stage2e")
Assert-Pass $result "Stage 2E XSim regression"
Assert-Marker $result.Text "STAGE2E_POSITIVE_SCENARIOS=PASS_35_OF_35" "Stage 2E XSim regression"

# Canonical and source/static closure gates.
$result = Invoke-Tool -Exe $Bash -Arguments @("sim/run_iverilog.sh", "all") `
    -WorkingDirectory $RepoRoot -LogPath (Join-Path $OutputRoot "canonical_regression.log")
Assert-Pass $result "Canonical regression"
Assert-Marker $result.Text "SUMMARY: PASS=10 FAIL=0" "Canonical regression"

$tclScripts = @(
    @{ Path = "fpga/vivado/build/tests/stage1e_reconstruction_profile_tests.tcl"; Label = "STAGE1E_RECONSTRUCTION"; Marker = "SUMMARY PASS=12 FAIL=0" },
    @{ Path = "fpga/vivado/build/tests/stage1e_ip_packaging_adapter_tests.tcl"; Label = "STAGE1E_IP_PACKAGING"; Marker = "SUMMARY PASS=29 FAIL=0" },
    @{ Path = "fpga/vivado/build/tests/stage1e_base_design_adapter_tests.tcl"; Label = "STAGE1E_BASE_DESIGN"; Marker = "SUMMARY PASS=13 FAIL=0" },
    @{ Path = "fpga/vivado/build/tests/stage1e_debug_design_adapter_tests.tcl"; Label = "STAGE1E_DEBUG_DESIGN"; Marker = "SUMMARY PASS=18 FAIL=0" },
    @{ Path = "fpga/vivado/build/tests/stage2d_source_closure_tests.tcl"; Label = "STAGE2D_SOURCE_CLOSURE"; Marker = "STAGE2D_SOURCE_CLOSURE_TESTS=PASS" },
    @{ Path = "fpga/vivado/build/tests/stage2d_cdc_constraint_tests.tcl"; Label = "STAGE2D_CDC_CONSTRAINTS"; Marker = "STAGE2D_CDC_CONSTRAINT_TESTS=PASS" },
    @{ Path = "fpga/vivado/build/tests/stage2d_profile_convergence_tests.tcl"; Label = "STAGE2D_PROFILE_CONVERGENCE"; Marker = "PROFILE_CONVERGENCE_TESTS=PASS" },
    @{ Path = "fpga/vivado/build/tests/stage2e_source_closure_tests.tcl"; Label = "STAGE2E_SOURCE_CLOSURE"; Marker = "STAGE2E_SOURCE_CLOSURE_TESTS=PASS" },
    @{ Path = "fpga/vivado/build/tests/stage2e_observability_cdc_constraint_tests.tcl"; Label = "STAGE2E_CDC_CONSTRAINTS"; Marker = "STAGE2E_OBSERVABILITY_CDC_CONSTRAINT_TESTS=PASS" }
)
foreach ($case in $tclScripts) {
    $result = Run-Tcl $case.Path $case.Label
    Assert-Pass $result "Tcl $($case.Label)"
    Assert-Marker $result.Text $case.Marker "Tcl $($case.Label)"
}

$headEnd = (@(& git -C $RepoRoot rev-parse HEAD) -join "").Trim()
if ($headEnd -cne $start.Head) { throw "Git HEAD changed during validation" }
$diffCheck = Invoke-Tool -Exe "git" -Arguments @("-C", $RepoRoot, "diff", "--check", $BaseCommit) `
    -WorkingDirectory $RepoRoot -LogPath (Join-Path $OutputRoot "git_diff_check.log")
Assert-Pass $diffCheck "Git diff check"
if ($diffCheck.Text.Trim().Length -ne 0) { throw "git diff --check emitted output" }

$end = Git-State $RepoRoot
Write-Lines (Join-Path $OutputRoot "git_status_end.txt") (@(
    "BRANCH=$($end.Branch)", "HEAD=$($end.Head)", "CLEAN=$($end.Clean)",
    "PORCELAIN_BEGIN"
) + $end.Status + @("PORCELAIN_END"))
if ($RequireClean -and -not $end.Clean) { throw "RequireClean validation ended dirty" }
Write-Lines (Join-Path $OutputRoot "runner_summary.txt") @(
    "STAGE2F_VALIDATION_RUNNER=PASS",
    "BASE_COMMIT=$BaseCommit",
    "PREVIOUS_IMPLEMENTATION_COMMIT=$PreviousImplementationCommit",
    "BRANCH=$ExpectedBranch",
    "HEAD=$($end.Head)",
    "PRODUCTION_PROFILE=UNCONFIGURED",
    "PRODUCTION_INCLUDE_CURRENT=PASS",
    "GENERATED_PROFILE_RTL_MATRIX=PASS_6_OF_6_ICARUS_AND_XSIM",
    "GENERATOR_TO_RTL_PROFILE_FIXTURES=PASS_12_OF_12",
    "PYTHON_REFERENCE_EXHAUSTIVE=PASS_57344_CASES",
    "PYTHON_REFERENCE_TO_RTL_COMPARISON=PASS",
    "DUPLICATE_JSON_KEY_REJECTION=PASS",
    "DATA_WIDTH_COMPATIBILITY_POLICY=RAW_GENERIC_NORMALIZATION_ONLY_AT_12",
    "IMPLICIT_NORMALIZER_PORT_RESIZE=NO",
    "NEW_BOUNDARY_MUTATION_FIXTURES=PASS_6_OF_6",
    "NORMALIZED_WIDTH=13",
    "NORMALIZED_UNIT=SIGNED_CODE_COUNT",
    "NORMALIZER_PIPELINE_LATENCY_ACLK=1",
    "PIPELINE_INITIATION_INTERVAL=1",
    "NO_SYNTHESIS_IMPLEMENTATION_BITSTREAM_BOARD_ACTION=YES",
    "STAGE2F_CONTRACT_GAP_CLOSED=NO",
    "PHYSICAL_SCALING_STATUS=BLOCKED_EXTERNAL_HARDWARE_FACTS",
    "REMAINING_CONTRACT_GAPS=2",
    "STAGE2_COMPLETE=NO"
)
Write-Output "STAGE2F_VALIDATION_RUNNER=PASS"
Write-Output "OUTPUT_ROOT=$OutputRoot"
Write-Output "HEAD=$($end.Head)"
