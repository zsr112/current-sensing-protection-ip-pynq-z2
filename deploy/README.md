# Current-Sensing Protection IP Release

This is the lightweight current-use, deployment, and delivery layer for PYNQ-Z2. It is not the full source
repository, a Vivado workspace, an evidence archive, or a historical handoff.

Engineering source: `e0f8dfdf481d91edd35b50848c86fa0c484e513d` (tree `99ad1db325caed406d23e5966abb1f7305010641`). Board runtime anchor: `1a365d5139f963ac4d8f92158dcd2928e86ccf36` (tree `244cba11579c7fdc39353391ac35a78ede20ec97`).

The included BIT SHA-256 is `f7dd0823e577cfee2aecfa3bf0a48e80d11108bdb12967e567ca64dc2e8ecfab` and the included HWH SHA-256 is `c97138493f8c4c568790a75bcc77551ad1f24952f6eb28c4238e6bda975b1e29`. The four
persistent runtime files are byte-identical to the Stage 1G board-validated package payload. Current engineering
source adds living documentation, the authority contract, and read-only validation tools; current `main` as a
whole was not rerun on the board.

## Start

- [Quick start](QUICK_START.md)
- [Release notes](RELEASE_NOTES.md)
- [Proof boundary](PROOF_BOUNDARY.md)
- [Register map](docs/register_map.md)
- Run `python tools/verify_release.py` before deployment.

## Layout

`pynq/artifacts/` contains the sole BIT/HWH pair and the board runtime manifest. `pynq/runtime/` and
`pynq/systemd/` contain byte-identical board runtime files. `pynq/install/` contains release management scripts;
`examples/` contains a read-only observation example; `docs/` contains the required interface/safety guidance.
