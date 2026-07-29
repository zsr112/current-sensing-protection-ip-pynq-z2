## Pre-board draft. Not validated on PYNQ-Z2 hardware yet.
##
## Draft-only constraint placeholder for future PYNQ-Z2 work.
## Do not use directly on hardware without checking the PYNQ-Z2 schematic,
## board master XDC, IO voltage, pin routing, and measurement setup.

## Clock/reset should normally come from Zynq PS FCLK/reset in block design.
## External pins for pwm_out/protect_trip/gate_inhibit are not assigned here.

## TODO after board planning:
## - Confirm output pin for low-voltage pwm_out observation.
## - Confirm optional protect_trip debug pin only after wrapper exists.
## - Confirm XADC pins only after AFE/XADC safety plan is approved.
## - Add IOSTANDARD and timing constraints from real board documentation.
