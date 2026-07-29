# Current-Sensing Protection IP for PYNQ-Z2

Public project snapshot for technical demonstration, reproducibility evaluation, and PYNQ-Z2 deployment.

## Project Overview

This repository is the current stable public snapshot of an FPGA/Zynq current-sensing protection prototype. It contains the readable RTL, canonical simulation suite, portable Vivado reconstruction inputs, PYNQ software source, and the complete verified deployment release.

## Problem Addressed

The design converts synchronous digital current samples into deterministic over-current, channel-mismatch, and sensor-health decisions. It classifies the primary fault, latches the first fault, and forces a demonstration PWM output low without relying on processing-system software in the real-time protection path.

## System Architecture

The main chain is digital current input and sample model, over-current and differential comparison, sensor health, fault classification, fault latch and recovery FSM, PWM safety gate, AXI-Lite registers, Vivado IP and block design, then PYNQ Overlay, MMIO, and autoload. See [architecture](docs/architecture.md).

## Main Features

- Dual-channel strict-greater-than over-current and mismatch comparison.
- Open, saturation, and stuck sensor-health monitoring.
- Fixed-priority fault classification and first-fault latching.
- Fault-aware clear and reset-wait behavior.
- Safe-low protection gating of the low-voltage demonstration PWM.
- Shared register bank behind direct and AXI-Lite wrappers.
- Ten canonical self-checking Icarus testbenches.

## Safety and Clear/Recovery Semantics

Live fault prevents false recovery. Clear is a recovery request, not an unconditional unlock. Fault removal and clear are separate actions. Clear-only does not automatically enable PWM. CTRL value 0x2 requests clear with PWM disabled; CTRL value 0x3 combines enable and clear and is not the safe recovery sequence. STATUS value 0x3 means both live and latched fault bits are set. Sensor history is not blindly cleared by a software request. See [clear and recovery semantics](docs/clear_recovery_semantics.md).

## Repository Structure

- rtl contains stable design source.
- tb and sim contain the canonical simulation flow.
- vivado contains portable reconstruction inputs, not generated workspaces.
- pynq contains non-duplicated software source and tests.
- deploy is the complete verified direct-deployment release.
- docs and verification describe behavior, provenance, evidence, and limits.

## Simulation Reproduction

Install Icarus Verilog and run:

    bash sim/run_iverilog.sh all

The expected canonical summary is PASS=10 FAIL=0. See [simulation guide](docs/simulation_guide.md).

## Vivado Rebuild

Use Vivado 2024.1, install the PYNQ-Z2 board files, set PROTECTION_IP_VIVADO_BUILD_ROOT to an external empty build root, and follow [the Vivado build guide](docs/vivado_build_guide.md). Rebuilding creates new artifacts; it does not inherit the accepted BIT/HWH proof.

## PYNQ-Z2 Deployment

The direct deployment authority is deploy. Begin with [deploy quick start](deploy/QUICK_START.md) and [PYNQ deployment guide](docs/pynq_deployment_guide.md). The public software source under pynq/source is not a second copy of the persistent deployment runtime.

## Verification Status

The canonical digital regression passes 10 of 10 testbenches. The included deploy release self-verifies. Stage 1G proves one real PYNQ-Z2 cold boot autoload with Overlay load, discovery, read-only MMIO/GPIO checks, one worker, one attempt, and no retry. See [verification status](docs/verification_status.md).

## Proof Boundary

This snapshot does not prove repeated cold boots, power-cycle behavior, soak, power-stage load, board fault injection or clear/recovery, EMI, thermal behavior, electrical safety, a new Vivado implementation, or newly generated BIT/HWH. See [proof boundary](docs/proof_boundary.md).

## Development Repository Relationship

The engineering repository is the sole development authority. This public repository does not independently maintain feature changes; updates must be generated or synchronised from the development repository. Development repository: https://github.com/zsr112/current-sensing-protection-ip.git

## Provenance

Source content is anchored to development commit 309a84bff651f73891309e02e1d02fc1f54bd3e6. The deploy subtree is anchored to release source e0f8dfdf481d91edd35b50848c86fa0c484e513d, while its persistent board runtime is anchored to 1a365d5139f963ac4d8f92158dcd2928e86ccf36. Public repository remote: not created in this local snapshot step.

## Known Limitations

This is an engineering, research, and teaching prototype. Inputs are digital sample codes, not a complete ADC/AFE chain. The PWM is a low-voltage demonstration carrier, not a complete motor controller or certified protection output. No usage or redistribution permission should be inferred from the absence of a license.
