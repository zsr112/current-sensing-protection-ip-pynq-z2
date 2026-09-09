# Stage 2A sampling / clock / reset / CDC inventory

Date: 2026-08-03
Baseline: `837bbdd71fec2d7e5a554db4ffa99e2cfccc425b` / `stage2-verification-foundation-v1`
Scope: source audit only; no RTL, synthesis, implementation, bitstream, ADC/AFE, or board action.

> Historical snapshot: the findings below describe the named 2026-08-03
> baseline. The current production-referenced
> `create_pynq_z2_stage2_bd.tcl` has since converged to `PROFILE=SAFE_INERT`,
> `adc_sample_valid=0`, and `FUNCTIONAL_ADC_STIMULUS=NO`. The Stage 2D result
> and pre-merge convergence result are the current authorities; the old
> valid-high inventory below is retained only as baseline audit evidence.

## 1. Context and naming

The RTL has no port literally named `sample`.  Its sample payload is the atomic
two-channel tuple `{i_ch1, i_ch2}`.  Both channels default to 12-bit unsigned
vectors.  `sample_valid` is a separate active-high bit.

Two existing integration descriptions must not be conflated:

1. The frozen Stage 1 construction in
   `fpga/vivado/build/runtime/runner/stage1e_production_vivado_runner_v2.tcl`
   drives `i_ch1/i_ch2` from two slices of a 24-bit AXI GPIO output and fixes
   `sample_valid` to zero.  GPIO, protection IP, SmartConnect, and ILA use the
   same `processing_system7_0/FCLK_CLK0` net (`:675-699`, `:918-947`).
2. The earlier minimal Stage 2 BD source
   `fpga/vivado/create_pynq_z2_stage2_bd.tcl` fixes `sample_valid=1` and both
   samples to 1024 (`:50-52`, `:209-237`).  These constants are explicitly
   described as non-ADC stimulus.  This is not evidence of an ADC boundary.

The reusable packaged top connects its complete AXI/register/protection path to
`ACLK`; the IP metadata declares a 100 MHz clock association and active-low
reset (`fpga/vivado/package_protection_ip_stage2_axi_lite.tcl:65-73,
:253-271`).

## 2. Traceable inventory

| Signal | Width | Producer | Consumer | Producer clock | Consumer clock | Reset domain | Current crossing | Evidence |
|---|---:|---|---|---|---|---|---|---|
| `i_ch1` | 12 | Frozen Stage 1: `axi_gpio_stage1d_0/gpio_io_o[11:0]` through `xlslice_stage1d_ch1`; minimal BD: constant 1024 | `current_compare_dual`, `sensor_health_monitor`, register monitor | Frozen Stage 1 GPIO `s_axi_aclk = FCLK_CLK0`; constant has no sequential clock | `protection_ip_axi_lite_0/ACLK = FCLK_CLK0` | `peripheral_aresetn` for GPIO/protection sequential state | `SAME_DOMAIN`; constant variant is stable, not a CDC | `stage1e_production_vivado_runner_v2.tcl:675-699, :933-947`; `protection_core_top.v:40-52`; `protection_ip_top_reg_controlled.v:64-65, :85-86` |
| `i_ch2` | 12 | Frozen Stage 1: GPIO `[23:12]` through `xlslice_stage1d_ch2`; minimal BD: constant 1024 | Same consumers as `i_ch1` | Same `FCLK_CLK0` | Same `ACLK/FCLK_CLK0` | Same reset | `SAME_DOMAIN`; constant variant is stable, not a CDC | Same Tcl ranges; `protection_core_top.v:40-52` |
| `{i_ch1,i_ch2}` pair | 24 | Current GPIO word or constants | Comparator pair and health-history pair | Same `FCLK_CLK0` for current GPIO construction | Same `ACLK` | Same reset | `SAME_DOMAIN`; no current multibit async crossing | `stage1e_production_vivado_runner_v2.tcl:682-695, :944-947`; `current_compare_dual.v:4-21`; `sensor_health_monitor.v:8-9, :47-62` |
| `sample_valid` (frozen Stage 1) | 1 | `sample_valid_const`, value 0 | `sensor_health_monitor` through all RTL wrappers | Constant | `ACLK/FCLK_CLK0` | Consumer reset only | Stable constant; no CDC | `stage1e_production_vivado_runner_v2.tcl:695, :918-920, :945`; `protection_ip_top_axi_lite.v:199`; `sensor_health_monitor.v:47` |
| `sample_valid` (minimal BD) | 1 | `sample_valid_const`, value 1 | Same health path | Constant | `ACLK/FCLK_CLK0` | Consumer reset only | Stable constant; no CDC | `create_pynq_z2_stage2_bd.tcl:50, :209, :235` |
| `sample_valid` (RTL/test contract) | 1 | Public top input; canonical and Stage 2 TB drive it at `negedge clk` | Only `sensor_health_monitor` state-update enable | Testbench `clk`; production source is integration-defined | `clk` / `ACLK`, rising edge | `rst_n` / `ARESETN` | `SAME_DOMAIN` in current tests/integration; future producer unresolved | `protection_core_top.v:6-8, :47-52`; `tb/tb_protection_core_top.sv:106-127`; `tb/tb_sensor_health_monitor.sv:42-63` |
| `th_oc_ch1`, `th_oc_ch2` | 12 each | `protection_reg_bank` registers | `current_compare_dual` | `ACLK` | Combinational logic feeding `ACLK` classifier | `ARESETN` | `SAME_DOMAIN` | `protection_reg_bank.v:37-63`; `protection_ip_top_reg_controlled.v:50-110`; `current_compare_dual.v:6-20` |
| `th_diff` | 12 | `protection_reg_bank` register | `current_compare_dual` | `ACLK` | Same `ACLK` path | `ARESETN` | `SAME_DOMAIN` | `protection_reg_bank.v:22, :43, :56`; `current_compare_dual.v:8, :16, :21` |
| `th_open`, `th_sat`, `th_stuck_delta`, `th_persist` | 12/12/12/8 | Constants in `protection_ip_top_reg_controlled`; direct ports in core-level use | `sensor_health_monitor` | Constants or same testbench domain | `clk/ACLK` | Health `rst_n` | No crossing in current top | `protection_ip_top_reg_controlled.v:29-32, :90-93`; `sensor_health_monitor.v:10-13` |
| `clear_fault_pulse` | 1 | `protection_reg_bank`, one-cycle pulse on control write | `protection_fsm.clear_fault` | `ACLK` | `ACLK` | `ARESETN` | `SAME_DOMAIN`; no pulse crossing | `protection_reg_bank.v:37-63`; `protection_ip_top_reg_controlled.v:67, :84`; `protection_fsm.v:47-68` |
| `pwm_enable`, `pwm_period`, `pwm_duty` | 1/16/16 | `protection_reg_bank` | `pwm_gen` | `ACLK` | `ACLK` | `ARESETN` | `SAME_DOMAIN` | `protection_reg_bank.v:18-24, :37-63`; `protection_core_top.v:68-70` |
| `sensor_*_flag` | 3 x 1 | Registered `sensor_health_monitor` outputs | Registered `fault_classifier` | `clk/ACLK` | Same `clk/ACLK` | Same `rst_n` | `SAME_DOMAIN` | `sensor_health_monitor.v:37-64`; `protection_core_top.v:47-59` |
| `oc_any`, `oc_both`, `mismatch_flag`, `abs_diff` | 1/1/1/12 | Combinational `current_compare_dual` | `fault_classifier` and public observation | Combinational from current sample/config | Registered on `clk/ACLK` | Classifier `rst_n` | Same-domain combinational-to-register path; **not gated by `sample_valid`** | `current_compare_dual.v:16-21`; `protection_core_top.v:40-59`; `fault_classifier.v:15-36` |
| `fault_valid`, `fault_code` | 1/8 | Registered `fault_classifier` | `protection_fsm`, register/status readback, public outputs | `clk/ACLK` | Same `clk/ACLK` | Same `rst_n` | `SAME_DOMAIN` | `fault_classifier.v:15-36`; `protection_core_top.v:54-66`; `protection_reg_bank.v:65-79` |
| `fault_latched`, `fault_code_latched`, `fsm_state`, internal `pwm_disable` | 1/8/4/1 | Registered `protection_fsm` | PWM gate, register/status path, ILA/public outputs | `clk/ACLK` | Same domain or combinational gate | Same `rst_n` | `SAME_DOMAIN` | `protection_fsm.v:22-77`; `protection_core_top.v:61-74`; `stage1e_production_vivado_runner_v2.tcl:623-629` |
| AXI request/control and register readback | AXI-Lite plus 32-bit data | PS GP0 / SmartConnect / AXI top / register bank | Register controls and PS read response | `FCLK_CLK0` | `ACLK = FCLK_CLK0` | `peripheral_aresetn` | `SAME_DOMAIN`; no AXI-to-protection CDC | `protection_ip_top_axi_lite.v:96-214`; `stage1e_production_vivado_runner_v2.tcl:600-608, :930-936` |
| `FCLK_RESET0_N -> ext_reset_in -> peripheral_aresetn -> ARESETN/rst_n` | 1 | Zynq PS through `proc_sys_reset` | SmartConnect, AXI GPIO, protection top, ILA, every RTL async-reset block | Raw PS reset relation | `slowest_sync_clk = FCLK_CLK0`; consumers use same `FCLK_CLK0` | One shared active-low reset distribution | `RESET_CROSSING`; conditioning boundary is explicit, but async-assert/sync-deassert implementation is `UNKNOWN_REQUIRES_ELABORATED_ANALYSIS` from repository RTL alone | `stage1e_production_vivado_runner_v2.tcl:600-603, :933-943`; all RTL blocks use `posedge clk or negedge rst_n` |
| Future `{sample_valid,i_ch1,i_ch2}` ADC/AFE ingress | 25 | `UNRESOLVED_FROM_CURRENT_SOURCE` | Packaged protection boundary | Future ADC clock | `ACLK/FCLK_CLK0` unless architecture changes | Future source and destination resets | `DEFERRED_IMPLEMENTATION_REQUIREMENT`; no CDC bridge exists | Public ports at `protection_ip_top_axi_lite.v:8-10, :31-32`; no synchronizer/FIFO/handshake module exists in `rtl/**` |

## 3. Clock and constraint findings

- All protection RTL sequential blocks use one rising-edge `clk`; the AXI top
  maps that clock to `ACLK` (`protection_ip_top_axi_lite.v:96, :197-214`).
- The accepted construction connects PS `FCLK_CLK0` to PS GP0, SmartConnect,
  `proc_sys_reset.slowest_sync_clk`, protection `ACLK`, GPIO `s_axi_aclk`, and
  ILA clock (`stage1e_production_vivado_runner_v2.tcl:600, :687, :933`).
- `fpga/constraints/pynq_z2_preboard_draft.xdc` is only a placeholder and has
  no `create_clock`, asynchronous clock group, input-delay, or ADC constraint
  (`:1-13`).  The existing IP/BD clock metadata is enough to describe the
  current internal 100 MHz intent, not a future ADC timing relationship.
- No repository RTL module implements `ASYNC_REG`, an atomic handshake, or an
  asynchronous FIFO for the sample tuple.

## 4. Classification totals

Counts below group related signals rather than counting every bit:

| Classification | Count | Meaning |
|---|---:|---|
| same-domain | 13 | Current sample, AXI configuration, control, fault/status, and PWM groups sharing `FCLK_CLK0/ACLK` |
| safe explicit CDC primitive | 0 | No sample CDC primitive is needed or present in the current same-domain construction |
| current unsafe multibit CDC | 0 | No current source evidence shows a multibit signal crossing between unrelated clocks |
| deferred | 1 | Future atomic ADC/AFE ingress boundary |
| unknown | 1 | Exact reset deassert behavior requires generated-IP/elaborated `report_cdc` confirmation |

```text
CURRENT_CDC_CLASSIFICATION=SAME_DOMAIN
CURRENT_SAMPLE_CLOCK_DOMAIN=processing_system7_0/FCLK_CLK0 -> protection_ip_axi_lite_0/ACLK
CURRENT_SAMPLE_PATH_CDC_RISK=NONE_WITHIN_CURRENT_SINGLE_DOMAIN_ASSUMPTION
CURRENT_MULTIBIT_UNSAFE_CDC_COUNT=0
CURRENT_RESET_CDC_RISK_COUNT=1
FUTURE_ADC_BOUNDARY_CDC_REQUIREMENT=OPEN
```

`CURRENT_RESET_CDC_RISK_COUNT=1` is a conservative proof-gap count.  It does
not assert that `proc_sys_reset` is defective; it records that this round did
not elaborate vendor IP or rerun Vivado CDC analysis and therefore cannot
prove reset release behavior from plain RTL/Tcl text alone.
