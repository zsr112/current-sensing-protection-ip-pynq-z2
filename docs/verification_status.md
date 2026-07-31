# Verification Status

## Digital Simulation

The canonical Icarus regression covers ten self-checking testbenches and is expected to report PASS=10 FAIL=0. This task reruns it in both staging and the final local repository.

## Deployment Release

The 22-file deploy subtree preserves the verified release byte for byte. Its own standard-library verifier validates the release manifest, BIT/HWH identity, persistent runtime, credentials, stale paths, and duplicate payload groups.

## Board Evidence

Stage 1G proves one real PYNQ-Z2 cold boot autoload, Overlay load and programming, device/clock/IP discovery, read-only MMIO/GPIO checks, one worker, one attempt, no retry, and clean terminal publication. Four persistent runtime files in deploy are byte-identical to the board-validated payload.

The accepted Stage 1 board functional closure is
`STAGE1-BOARD-FUNCTIONAL-CLOSURE-ATTEMPT06-RERUN02-20250506T201111Z`. Its board sequence terminal class is
`STAGE1_BOARD_MMIO_SEQUENCE_PASS_AWAITING_ILA`; its formal analyzer terminal class is
`STAGE1_BOARD_FAULT_CLEAR_RECOVERY_FUNCTIONAL_CLOSURE_PASS`; and `STAGE1_FUNCTIONAL_CLOSURE=PASS`.

The accepted analyzer proves CH1-only, CH2-only, and differential fault response; live-fault clear rejection;
source-removal latch/code retention; clear recovery; internal PWM shutdown; post-recovery PWM pass-through;
and final state restoration. Eight of eight named ILA checks pass and `errors` is empty.

The formal analysis SHA-256 is
`66bf897bc44327726cfd69d3d36abb9069f6035683e61667bd4ce367396d7076`; the evidence archive SHA-256 is
`0f558dad6335b46cace732fe59caf5734dd87a7b62e9a772a16cfebc3bc3962a`; and the canonical inventory SHA-256
is `14f55b6205a5d0ea888eea2c3973f8497a6aef7dff940c82f54078c67be29b98`.

The original snapshot payload remains anchored to its existing development and release authorities. This
status update is synchronized from engineering `main` commit
`68ef6d99d6b523447b39be004e85fa10558a03af`, tree
`5e44f26f443edea4a7a4401bca1530133cc25da2`. It does not alter the verified deploy payload.

Simulation and software tests do not create a new board result. This closeout does not rerun the board.
