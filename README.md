# Current-Sensing Protection IP for PYNQ-Z2

This repository is the reviewed Stage2 delivery candidate for the PYNQ-Z2 digital current-protection prototype. The engineering repository remains the sole development authority.

## Delivery State

```text
STAGE1_COMPLETE=YES
STAGE2_COMPLETE=YES
STAGE3_STARTED=NO
PUBLIC_ABI=1.1
PROTECTION_IP_BASE=0x43C00000
GPIO_BASE=0x41200000
PRODUCTION_PROFILE=SAFE_INERT
```

The included production release is `current-sensing-protection-ip-7ad1681f5c49-pynq-z2-stage2i`. Its BIT/HWH pair, runtime, ABI metadata, and offline verifier are bound to the accepted Stage2 authority.

## Use

- Start with [deploy/QUICK_START.md](deploy/QUICK_START.md) for the accepted SAFE_INERT release.
- Run `python tools/verify_public_snapshot.py` for the complete delivery check.
- Run `bash sim/run_iverilog.sh all` for the ten canonical RTL tests when Icarus Verilog is installed.
- Follow [docs/vivado_build_guide.md](docs/vivado_build_guide.md) for the compact Vivado 2024.1 B1 structural reconstruction adapter.
- Inspect [spec/register_map.json](spec/register_map.json) for the single register-map source authority and [deploy/docs/register_map.md](deploy/docs/register_map.md) for its rendered user reference.

## Scope

Stage2 closes the digital protection architecture, ABI 1.1, implementation, SAFE_INERT production artifacts, and bounded PYNQ-Z2 digital board validation. The delivery does not claim a real ADC/AFE signal chain, physical current scaling, calibration, a power stage, or production safety.

```text
REAL_ANALOG_ADC_SIGNAL_CHAIN_VALIDATED=NO
PHYSICAL_CURRENT_SCALING_VALIDATED=NO
CURRENT_MEASUREMENT_CALIBRATION_CLOSED=NO
```

Stage3 has not started. Production hardware selection, analog integration, physical scaling, and calibration remain Stage3 work.

## Authority

The engineering source is fixed at commit `9c5e6f6ac7dc311f12755c8b1713433d35e39bff`, tree `b1cfec1b073770c03bad9fa5b298b0bd1f3923c3`, tag `stage2-digital-protection-engineering-closure-v1`. The canonical Stage2 package SHA-256 is `4916cdd574955c15e1d6eaa29b7760243fdfc47e19d06c68573c460ed484f1c0`. See [PUBLIC_SNAPSHOT_PROVENANCE.json](PUBLIC_SNAPSHOT_PROVENANCE.json).

The supported public Vivado entrypoint is a delivery adapter derived from the current engineering production runner, not from the historical standalone project, package, or BD scripts. It reconstructs the accepted B1 `SAFE_INERT` structure and wrapper only. The accepted BIT/HWH pair remains the reviewed programming authority; newly reconstructed output is unvalidated until separately synthesized, implemented, and validated.
