# PYNQ-Z2 digital protection — v2r3

Formal digital release: **PROJECT_OWNER_ACCEPTED**. Internal project-owner review and independent Windows/macOS post-seal validation are complete.

The current GitHub Actions entry is [.github/workflows/portable.yml](.github/workflows/portable.yml). It uses the current supported Windows Icarus installation and validates the delivery under `delivery/`. There is no fallback to historical workflows.

## Verify and use

```text
python -B verify.py
python -B delivery/deploy/load.py
```

Python 3.10+ is sufficient for offline verification. Deployment without `--execute` performs an offline check. Read [the delivery guide](delivery/README.md) before executing a hardware load or rebuild.

The `delivery/` directory preserves all 2,008 files of the accepted release archive byte-for-byte. Its nested workflow files are frozen source/publication evidence, not GitHub Actions entry points. Historical runnable versions remain available through Git history and previous release tags.

## Formal release assets

Download `stage2-self-contained-v2r3.zip` and both external post-seal JSON receipts from the formal **v2r3** release. The ZIP is 5,130,902 bytes and its SHA256 is:

```text
de73b0983e976e6daa500b929eb1cd0d48473d21ced45906406f27de6dcc8c50
```

The repository layout and GitHub-generated source archives are not that exact release ZIP. Do not substitute them when checking its post-seal receipts. The [external receipt copies](verification/) identify the immutable ZIP.

Physical source: `fb81a9a004bdcb900e5b678d8a424403aeafb602`. Publication tooling: `a16851427f4a3c48f655d5a7b1a46ba5efb79486`. Current repository maintenance can update the root workflow without modifying these sealed identities.

## Accepted scope

Digital source, recorded routed build, portable regression and recorded synthetic-digital PYNQ-Z2 scenarios are covered. Real ADC/AFE input, calibration, external-pin PWM, power stage, persistent boot, long-duration soak and analog-system validation remain outside the accepted scope. See [architecture and limitations](delivery/publication/docs/architecture/current_architecture.md).
