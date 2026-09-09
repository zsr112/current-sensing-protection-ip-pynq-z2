# Stage 2 Windows Rebuilt and Board-Verified Engineering Release

REBUILT=PASS; BOARD_VERIFIED=PASS.

Fresh B2 hardware was built with Vivado 2024.1 build 5076996 and verified on
PYNQ-Z2 with PynqLinux 3.0, PYNQ 3.1.1 and Python 3.10.4. Eight required and
two supporting digital scenarios passed, with 20 byte-exact original ILA CSVs.

This is a Stage 2 engineering release. Formal acceptance=NOT_FORMALLY_ACCEPTED.
It is not a production or formally accepted protection system. Real ADC,
external-pin PWM, external power stage, persistent boot and soak test=NOT_RUN.
Stage 3 has not started.

CDC-4 Critical remains in the raw report, with the bounded asynchronous FIFO
engineering review attached. No waiver or severity reduction was applied.
WNS=0.902 ns; WHS=0.020 ns; WPWS=2.750 ns. Setup, hold and pulse-width failing
endpoints are zero; unconstrained internal endpoints are zero. DRC and
methodology warnings retain their original severity and engineering disposition.

## Artifact Identity

The final artifact set is from the B2 profile
`READY_AWARE_SYNTHETIC_DIGITAL_STIMULUS`, with a 125 MHz synthetic source and
100 MHz destination. The earlier B1 `SAFE_INERT` build is a different
configuration with no active sample source. Its artifact hashes and WNS
1.309 ns are not the reference for the B2 R4 campaign. B1 evidence is not
used as proof of the eight R4 scenarios.

| Artifact | B2 SHA-256 |
| --- | --- |
| BIT | `2ef091e6550ba01d00cd677d9b9676fc38f3cdd4380d9925244fb705342ec518` |
| HWH | `0b011b48829ef1e29c917a83ecdbe1e96c012dd86fda4ac7cf4d5abcc4ee71fc` |
| LTX | `7f7c67eb6851ebaa2e9b67d1efd79a7591cb375ab855eae8450393dc4110dc21` |
| XSA (external provenance only) | `e80324278450b0e1bccc713931d229adb025d9a1f30549029a77aab5eb010adf` |

Final asset: `current-sensing-protection-ip-windows-board-verified-v1.zip`

ZIP bytes: 2584818

ZIP SHA-256: `37df15b6444abcae031015f7ec8f1b6cb3b728168efb77987c3bfc0a1f0191c6`

Manifest SHA-256: `70c9f9f4a20c058bc06c38407a658c369af7879ef322ad9d6b8bbbe3c08c7519`

## Evidence Chain

- Physical source commit: `3cf68b27c7e30c1ac3729bd9f3b79598531d0be2`.
- Physical source tree: `338bbcc360c82f2ce9b4e6747bc98a60e72ffd26`.
- Engineering release tooling commit: `cd7b39091fdc3b057096952f32e8501f8d72beee`.
- Physical execution: `S1E-B2-REBUILT-WINDOWS-20260909T000000Z`.
- Board execution: `S1E-B2-BOARD-20260909-R4`.
- Final regression: `S1E-WINDOWS-FINAL-VERIFICATION-20260909-R4-V2`.
- Original board receipt SHA-256: `85602e2f71b5950340fa680f4d6ea0f44ce95b5fc9d950e44bcd0c249cb71354`.

The physical-source and release-tooling commits differ because subsequent
changes corrected test tooling, portability and documentation. Hardware RTL,
constraints and software runtime did not change after the physical build.
Original artifacts and ILA CSV bytes are preserved. Portable log derivatives
carry both original and delivered hashes in `EVIDENCE_PROVENANCE.json`.

Historical accepted Stage 1/2 tags and archives remain HISTORICAL_ACCEPTED.
They are preserved and are not relabeled as fresh evidence.

## Verification

After extracting the asset, run:

```text
python -B tools/verify_windows_board_release.py .
```

For a checkout of the selected delivery branch, run:

```text
python -B release/tools/verify_windows_board_release.py release
```

The verifier needs Python 3.10 or newer and no Git, Vivado or board connection.
It verifies the complete manifest and reanalyzes the raw ILA captures.
