# 仿真使用说明

推荐优先使用 Icarus Verilog、ModelSim/Questa 或 Vivado xsim。代码采用 Verilog-2001 RTL + SystemVerilog testbench。

## Icarus Verilog 示例

```bash
bash sim/run_iverilog.sh all
bash sim/run_iverilog.sh tb_protection_ip_top_reg_controlled
bash sim/run_iverilog.sh tb_protection_ip_top_axi_lite
```

脚本会自动定位仓库根目录。编译产物输出到 `sim/build/`，VCD 波形输出到 `sim/waves/`。

如果环境没有 `iverilog`，可以直接在 Vivado 中添加 `rtl/*.v` 与 `tb/*.sv` 后运行行为仿真。

## 必跑自检

`all` 当前运行 10 个 testbench，并输出 PASS/FAIL 汇总。

1. `tb_pwm_gen.sv`：PWM边界条件。
2. `tb_current_compare_dual.sv`：双通道过流、差分失配。
3. `tb_moving_avg_filter.sv`：滑动平均滤波基础行为。
4. `tb_sensor_health_monitor.sv`：断路/饱和/卡死计数。
5. `tb_fault_classifier.sv`：fault priority。
6. `tb_protection_fsm.sv`：锁存、清故障、恢复。
7. `tb_protection_core_top.sv`：端到端过流切PWM闭环。
8. `tb_protection_reg_bank.sv`：寄存器读写与 clear pulse。
9. `tb_protection_ip_top_reg_controlled.sv`：寄存器控制阈值、PWM、故障锁存、clear_fault 和读回闭环。
10. `tb_protection_ip_top_axi_lite.sv`：AXI-Lite 写阈值、PWM 参数、fault latch、clear_fault 和寄存器读回闭环。
