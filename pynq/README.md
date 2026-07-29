# PYNQ Source

pynq/source contains the non-duplicated MMIO interface source and its host-side tests. The unique deployment runtime, installers, service unit, accepted BIT/HWH pair, and direct-use guidance are under ../deploy.

Run source tests from the repository root:

    python -m unittest discover -s pynq/source/tests -p "test_*.py" -v

The recovery helper keeps PWM disabled, requires external safety confirmation from its caller, writes clear-only CTRL value 0x2, verifies recovery with a finite bound, and enables PWM separately.
