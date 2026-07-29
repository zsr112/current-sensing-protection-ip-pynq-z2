# Quick Start

Target: PYNQ-Z2 with PYNQ 3.1.1, Python 3.10.4 and XRT at `/usr`.

1. Copy this expanded directory to the board, for example `/home/xilinx/current-sensing-protection-ip-release`.
2. Run `python3 tools/verify_release.py` from the release root.
3. Review `PROOF_BOUNDARY.md` and `docs/recovery_safety.md`.
4. Install with `sudo ./pynq/install/install.sh`.
5. Check with `./pynq/install/status.sh` and `systemctl status current-sensing-protection-ip-load.service`.
6. The installer enables the service but does not start it and does not reboot. Any reboot remains an explicit
   human operation outside this release procedure.
7. After an already loaded/verified Overlay exists, the non-mutating example is
   `/usr/local/share/pynq-venv/bin/python3 examples/read_only_status.py`.

Stop on any verifier failure, identity mismatch, unexpected existing release, active service during uninstall,
unknown board state, or need for credentials. This release contains no credentials; enter `<password>` only in
the interactive environment that owns it. Do not place a password in a command line or file.

Uninstall requires explicit confirmation: `sudo ./pynq/install/uninstall.sh --confirm`. It refuses while the
service is active and preserves logs/state for review.
