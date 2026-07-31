# Stage 1 Board Functional Closure

## Status

- `STAGE1_FUNCTIONAL_CLOSURE=PASS`
- Accepted execution:
  `STAGE1-BOARD-FUNCTIONAL-CLOSURE-ATTEMPT06-RERUN02-20250506T201111Z`
- Evidence closeout:
  `STAGE1-BOARD-FUNCTIONAL-CLOSURE-ATTEMPT06-RERUN02-20250506T201111Z-EVIDENCE-CLOSEOUT-20260730T233831322Z`
- Board sequence terminal class: `STAGE1_BOARD_MMIO_SEQUENCE_PASS_AWAITING_ILA`
- Analyzer terminal class: `STAGE1_BOARD_FAULT_CLEAR_RECOVERY_FUNCTIONAL_CLOSURE_PASS`
- Read-only audit: `RERUN02_CLOSEOUT_READONLY_AUDIT_PASS`
- Data archive: `STAGE1_BOARD_FUNCTIONAL_CLOSURE_DATA_ARCHIVE_PASS`

The execution ID retains the observed 2025 board time. The board wall clock is `UNTRUSTED`; monotonic
ordering is `AUTHORITATIVE_FOR_SEQUENCE`; host/operator time comes from external host evidence.

## Proved Behavior

- Healthy baseline
- CH1-only overcurrent response
- CH2-only overcurrent response
- Differential fault response
- Live-fault clear rejection
- Latch/code retention after source removal and before clear
- Recovery after source removal and clear
- Direct internal PWM shutdown during each fault class
- Internal PWM pass-through before fault and after recovery
- Final GPIO, register, and test-input restoration

Operation counts are protection writes 13, GPIO writes 7, Overlay downloads 1, automatic retries 0, reboots
0, power cycles 0, and SSH operations 0. Eight required scenarios passed within nine scenario records. Final
state is `RESTORED_AND_TEST_INPUT_DISABLED`.

## ILA Captures

1. `normal_pwm`
2. `ch1_trip`
3. `live_clear_rejected`
4. `source_removed_preclear`
5. `clear_recovery`
6. `post_recovery_pwm`
7. `ch2_trip`
8. `differential_trip`

Each capture has 4096 analyzer-counted samples, 844452 CSV bytes, and `BINARY` probe radix. All eight analyzer
checks pass and `errors` is empty.

## Cryptographic Identities

| Object | SHA-256 |
|---|---|
| Formal analysis | `66bf897bc44327726cfd69d3d36abb9069f6035683e61667bd4ce367396d7076` |
| Board result | `1fa7c73de68459a4d9c89d812b2f6d85fd6293bb4dcb3b167e8685f351285677` |
| Board receipt archive | `c00c5f525a38c70d941908dc157b757a1141f5c5aad0b780c49be537063d046a` |
| Evidence archive | `0f558dad6335b46cace732fe59caf5734dd87a7b62e9a772a16cfebc3bc3962a` |
| Canonical inventory | `14f55b6205a5d0ea888eea2c3973f8497a6aef7dff940c82f54078c67be29b98` |
| BIT | `f7dd0823e577cfee2aecfa3bf0a48e80d11108bdb12967e567ca64dc2e8ecfab` |
| HWH | `c97138493f8c4c568790a75bcc77551ad1f24952f6eb28c4238e6bda975b1e29` |
| LTX | `5cf63856626892ff0483a90eef7531f1c100caabd53b27b49e4d9ca7e06af274` |

Raw CSV, board receipts, Vivado logs, analyzer logs, evidence archives, and data-layer history are not
included in this repository. Their authority is the logical data-layer path
`accepted/stage1-board-functional-closure/rerun02`.

## Engineering Authority

This status is synchronized from engineering `main` commit
`68ef6d99d6b523447b39be004e85fa10558a03af`, tree
`5e44f26f443edea4a7a4401bca1530133cc25da2`. No development script or raw evidence was promoted by this
status-only update.

## Proof Boundary

This PASS is limited to PYNQ-Z2 low-voltage internal digital functional validation and the accepted ILA
evidence loop. `sample_valid` was fixed low, so sensor-health behavior is not proved.

This validation does not represent a pass for a real power stage, external drive chain, load, thermal
behavior, EMI, or production safety. It also does not prove external ADC/AFE, calibrated current,
external-pin PWM, gate-driver behavior, motor behavior, electrical safety, production reliability, or
system/aviation certification.
