# Quick Start

1. Run `python tools/verify_release.py` from the expanded release root.
2. Review `PROOF_BOUNDARY.md` and `docs/recovery_safety.md`.
3. Run `python pynq/runtime/stage2i_current_release.py --release-root .` for offline HWH and ABI validation.
4. Use `--execute` only in an explicitly authorized physical-board gate.

There is no systemd unit, boot installer, reboot action, or persistent-deployment claim in this release.
