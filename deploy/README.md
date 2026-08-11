# Current-Sensing Protection IP Release

This is the Stage2I current-use PYNQ-Z2 release. Engineering main commit: `7ad1681f5c49128ec2f10b13d6a41e7be0de62f4` (tree `d5de93f366ecd4f15e5371e110b8ffc701336783`). Physical artifact source commit: `75e5251cd4878a44f5b77d34dc6da160178102a8` (tree `d5de93f366ecd4f15e5371e110b8ffc701336783`), execution `S2IB-RECLOSE-B1-20260810T1838Z-75e5251`. The two trees are equal.

The release packages one SAFE_INERT BIT/HWH pair and the current one-shot ABI 1.1 runtime. LTX and XSA are
required physical-provenance artifacts but are intentionally not deployment payloads. Persistent deployment is
explicitly `NOT_CLAIMED`.

Run `python tools/verify_release.py` before use. Offline validation is:

`python pynq/runtime/stage2i_current_release.py --release-root .`

Physical Overlay loading is opt-in only through `--execute` and remains a separately authorized board action.
