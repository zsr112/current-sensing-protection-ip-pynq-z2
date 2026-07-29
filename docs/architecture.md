# Architecture

## Mainline Hierarchy

    protection_ip_top_axi_lite
      protection_ip_top_reg_controlled
        protection_reg_bank
        protection_core_top
          current_compare_dual
          sensor_health_monitor
          fault_classifier
          protection_fsm
          pwm_gen
          pwm_gate

moving_avg_filter is stable and tested but is not instantiated in the mainline hierarchy.

## Data and Protection Flow

The synchronous digital inputs i_ch1, i_ch2, and sample_valid feed current comparison and sensor-health logic. The classifier selects a primary code. The FSM captures the first observable code, keeps protection latched through a live fault, and requires a later clear request plus reset-wait completion after the input becomes safe. fault_latched drives pwm_gate so pwm_out is forced low.

## Platform Flow

protection_ip_top_axi_lite exposes the register bank through a single-outstanding AXI-Lite wrapper. The Vivado inputs package this top, create a PYNQ-Z2 processing-system and SmartConnect block design, and add controlled stimulus and observation logic. PYNQ uses the accepted Overlay/HWH pair and MMIO runtime in deploy.

## Boundary

The input values are digital codes. This snapshot does not implement the analog front end, isolation, ADC acquisition, calibration into physical units, or a complete power-stage gate-drive chain.
