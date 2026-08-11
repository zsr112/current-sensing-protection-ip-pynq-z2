# PYNQ-Z2 Deployment

Use the complete release under `deploy/`. Run its self-verifier before programming, then use the one-shot runtime described by `deploy/QUICK_START.md`.

The release does not install a persistent systemd service and does not claim reboot persistence. It validates ABI 1.1, HWH address metadata, and the SAFE_INERT artifact binding offline before board use.
