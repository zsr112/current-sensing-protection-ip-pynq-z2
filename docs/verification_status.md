# Verification Status

## Digital Simulation

The canonical Icarus regression covers ten self-checking testbenches and is expected to report PASS=10 FAIL=0. This task reruns it in both staging and the final local repository.

## Deployment Release

The 22-file deploy subtree preserves the verified release byte for byte. Its own standard-library verifier validates the release manifest, BIT/HWH identity, persistent runtime, credentials, stale paths, and duplicate payload groups.

## Board Evidence

Stage 1G proves one real PYNQ-Z2 cold boot autoload, Overlay load and programming, device/clock/IP discovery, read-only MMIO/GPIO checks, one worker, one attempt, no retry, and clean terminal publication. Four persistent runtime files in deploy are byte-identical to the board-validated payload.

Simulation and software tests do not create a new board result.
