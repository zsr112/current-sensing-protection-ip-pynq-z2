# v2r3 Release Seal

This release uses two immutable layers because a ZIP cannot contain a hash of
its own final bytes.

1. Build and freeze the pre-seal payload.
2. Validate that payload on Mac and write `mac_validation.json` outside it.
3. Aggregate the pre-seal records and write the internal acceptance decision.
4. Build `stage2-self-contained-v2r3.zip` once.
5. Validate those exact ZIP bytes independently on Windows and Mac.
6. Require both external receipts before Tag movement, merge or publication.

## Evidence Preparation

After the final three-platform Actions run, build `online_ci.json` from the
three downloaded artifact ZIPs with `tools/build_online_ci_evidence.py`.
Artifact IDs and the run URL are mandatory. The tool checks every command
result, every portable result and the selected Git origin before recording each
platform ZIP identity.

Build `windows_validation.json` with `tools/build_windows_validation.py`. It
binds the immutable Windows full-regression receipt, junction rejection, board
receipt, source manifest, hardware artifacts and current online CI evidence.

## Pre-Seal Payload

Run the delivery builder with:

```text
python -B tools/build_self_contained_release.py <all normal input options> --phase preseal --output <handoff>/stage2-self-contained-v2r3-payload --release-id stage2-self-contained-v2r3
```

Transfer the resulting `stage2-self-contained-v2r3-payload.zip` without
repacking it. On Mac, run the validator shipped in the extracted payload:

```text
python -B tools/validate_release_payload.py stage2-self-contained-v2r3-payload.zip --output mac_validation.json
```

The Mac record binds the pre-seal ZIP and `PAYLOAD_MANIFEST.json` after fresh
publication tests, portable preflight and portable regression.

Place that record beside `online_ci.json` and `windows_validation.json`, then
run:

```text
python -B tools/build_release_final_evidence.py <final-evidence-directory>
```

## Final Seal

Run the delivery builder with `--phase final`, an explicit UTC
`--accepted-at`, and output directory name `stage2-self-contained-v2r3`. The
builder regenerates the payload, requires its manifest identity to equal the
Mac-validated identity, writes acceptance, verifies the directory, creates the
formal ZIP and verifies a fresh extraction.

Do not rename a pre-seal ZIP into the formal filename. Do not modify or repack
the formal ZIP after creation.

Windows and Mac must each create a receipt against the same formal ZIP:

```text
python -B tools/verify_post_seal_release.py stage2-self-contained-v2r3.zip --output stage2-self-contained-v2r3.windows-post-seal.json --platform WINDOWS --validation-id CSIP-V2R3-WINDOWS-POSTSEAL-001
python -B tools/verify_post_seal_release.py stage2-self-contained-v2r3.zip --output stage2-self-contained-v2r3.macos-post-seal.json --platform MACOS --validation-id CSIP-V2R3-MACOS-POSTSEAL-001
```

Finally, verify the publication gate using both receipts:

```text
python -B tools/verify_post_seal_release.py stage2-self-contained-v2r3.zip --receipt stage2-self-contained-v2r3.windows-post-seal.json --receipt stage2-self-contained-v2r3.macos-post-seal.json
```

The two post-seal JSON files remain outside the archive. A PASS from only one
platform, a differently named ZIP, a repacked ZIP or a changed byte fails the
publication gate.
