# Architecture

The production path accepts an atomic pair of digital ADC sample codes through a valid/ready source interface, assigns source transaction identity, crosses the asynchronous clock boundary through a Gray-pointer FIFO, normalizes the configured code representation, evaluates over-current, mismatch, and sensor-health conditions, and applies first-fault and recovery policy before gating PWM safe.

The AXI-Lite register bank exposes ABI 1.1 status, configuration, snapshot, capability, and observability registers. PYNQ software discovers the IP and GPIO addresses from the accepted HWH metadata. Software is not in the real-time protection path.
