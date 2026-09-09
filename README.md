# Current-Sensing Protection IP for PYNQ-Z2

This branch contains the Stage 2 Windows R4 engineering delivery. The complete
development authority is [current-sensing-protection-ip](https://github.com/zsr112/current-sensing-protection-ip),
engineering release tag `stage2-windows-board-verified-v1` at commit
`cd7b39091fdc3b057096952f32e8501f8d72beee`.

The [release directory](release/) preserves the exact selected snapshot and its
1,601-entry manifest. Repository navigation and publication notes live outside
that directory so the reviewed snapshot remains unchanged.

```text
python -B release/tools/verify_windows_board_release.py release
```

Python 3.10 or newer is required. Verification needs no Git, Vivado, or board
connection and reanalyzes the 20 original ILA CSV files.

## Evidence State

| Item | Status |
| --- | --- |
| Fresh Vivado 2024.1 B2 build | REBUILT=PASS |
| PYNQ-Z2 R4: eight required and two supporting scenarios | BOARD_VERIFIED=PASS |
| Formal acceptance | NOT_FORMALLY_ACCEPTED |
| CDC-4 | Critical retained; bounded FIFO engineering review attached |
| Real ADC, external power stage, persistent boot and soak | NOT_RUN |

This is a Stage 2 engineering release, not a production or formally accepted
protection system. Stage 3 has not started. B2 uses synthetic digital samples;
the earlier B1 SAFE_INERT artifacts belong to a different configuration.

See [release notes](RELEASE_NOTES.md), [VERSION](release/VERSION.json),
[evidence annex](release/EVIDENCE_ANNEX.json), and
[provenance](release/EVIDENCE_PROVENANCE.json) for source and artifact identities.

Expected final ZIP: `current-sensing-protection-ip-windows-board-verified-v1.zip`

SHA-256: `37df15b6444abcae031015f7ec8f1b6cb3b728168efb77987c3bfc0a1f0191c6`

The ZIP is a release asset; the full build workspace is not repository content.
The historical delivery remains available on unchanged `main` and the unchanged
tags `pynq-z2-stage1-functional-closure-v1` and
`pynq-z2-stage2-digital-protection-delivery-v1`. Historical accepted evidence is
not relabeled as fresh evidence.
