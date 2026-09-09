# Windows PYNQ-Z2 Board Evidence Release

This selected engineering snapshot contains freshly rebuilt B2 hardware and a new board campaign. It is not a production or formally accepted protection system.

Run `python -B tools/verify_windows_board_release.py .` after extraction. Verification requires Python 3.10 or newer, uses no Git or FPGA tools, and reanalyzes all raw ILA captures.

BIT/HWH/LTX and ILA CSV files retain their original bytes. EVIDENCE_PROVENANCE.json identifies original evidence and every portable derivative by separate size and SHA-256. Full original Vivado logs, XSA, routed checkpoint and build workspace remain in the external evidence authority.

The root board profile is a portable derivative suitable for the included PYNQ runtime. The original session profile and manifest remain evidence under evidence/session. This snapshot is not a replayable authenticated session package; prepare a fresh execution with the complete repository tooling.

Hardware-source, board-tooling and release-tooling commits are separate fields in VERSION.json. Selected RTL/constraints are included for inspection; a complete rebuild uses the full engineering repository at the recorded physical-source commit, with a new external build root.

The eight required scenarios and two supporting scenarios passed. Sample removal covers the synthetic digital producer, not a physical analog ADC. CDC-4 remains Critical in the raw report; the bounded FIFO review is attached. Formal acceptance remains NOT_FORMALLY_ACCEPTED.
