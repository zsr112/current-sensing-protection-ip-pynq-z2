# PYNQ-Z2 Deployment Guide

## Direct Deployment

deploy is the sole deployment authority. It is the complete verified release and preserves the original internal paths, manifest, VERSION, provenance, verifier, artifacts, installers, runtime, service unit, documents, and example.

Run the release verifier before use:

    python deploy/tools/verify_release.py

Then follow deploy/QUICK_START.md. Deployment and service operations should be performed only by an operator who understands the board and system boundary.

## Source Interface

pynq/source/protection_ip_interface.py provides a small MMIO-facing interface and a safe recovery sequence. Its host-side contract tests do not access a board:

    python -m unittest discover -s pynq/source/tests -p "test_*.py" -v

This source is not a duplicate of the persistent runtime in deploy.
