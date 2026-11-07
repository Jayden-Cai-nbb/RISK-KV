`timescale 1ps/1ps
// 只观察厂商公开基础时钟/复位RTL；PLL锁定由夹具驱动，不包含DDR PHY。
module tb_mig_reset_observation;
    reg input_clock = 1'b0;
    reg clock_enabled = 1'b1;
    reg sys_rst = 1'b0;
    reg phy_pll_lock = 1'b1;
    wire mmcm_lock;
    wire ui_clk;
    wire riu_clk;
    wire rst_ui;
    wire rst_riu;
    wire rst_mb;
    wire pll_gate;
    integer samples;
    integer checks = 0;

    initial forever begin
        #10416;
        if (clock_enabled) input_clock = 1'b1;
        #10417;
        input_clock = 1'b0;
    end

    ddr4_v2_2_17_infrastructure #(
        .CLKIN_PERIOD_MMCM(20833),
        .CLKFBOUT_MULT_MMCM(20),
        .DIVCLK_DIVIDE_MMCM(1),
        .CLKOUT0_DIVIDE_MMCM(5),
        .CLKOUT1_DIVIDE_MMCM(5),
        .CLKOUT2_DIVIDE_MMCM(5),
        .CLKOUT3_DIVIDE_MMCM(5),
        .CLKOUT4_DIVIDE_MMCM(5),
        .CLKOUT6_DIVIDE_MMCM(10),
        .C_FAMILY("virtexu"),
        .TCQ(100)
    ) dut (
        .sys_rst(sys_rst),
        .sys_clk_in(input_clock),
        .mmcm_clk_in(input_clock),
        .pll_lock(phy_pll_lock),
        .mmcm_lock(mmcm_lock),
        .div_clk(ui_clk),
        .riu_clk(riu_clk),
        .addn_ui_clkout1(),
        .addn_ui_clkout2(),
        .addn_ui_clkout3(),
        .addn_ui_clkout4(),
        .dbg_clk(),
        .rstdiv0(rst_ui),
        .rstdiv1(rst_riu),
        .reset_ub(rst_mb),
        .pllgate(pll_gate)
    );

    task automatic snapshot(input string label);
        $fdisplay(samples,"%s\t%0t\t%b\t%b\t%b\t%b\t%b\t%b\t%b\t%b\t%b",
            label,$time,clock_enabled,sys_rst,phy_pll_lock,mmcm_lock,
            dut.input_rst_design,dut.input_rst_mmcm,rst_ui,rst_riu,pll_gate);
        $fflush(samples);
    endtask

    task automatic wait_ready(input string label);
        integer ticks;
        ticks=0;
        while (!(mmcm_lock===1'b1 && rst_ui===1'b0 && rst_riu===1'b0 && rst_mb===1'b0 && pll_gate===1'b1)) begin
            #100000;
            ticks++;
            if (ticks>1000) $fatal(1,"No ready state in 100us: %s",label);
        end
        checks++;
        snapshot(label);
    endtask

    task automatic wait_reset(input string label);
        integer ticks;
        ticks=0;
        while (!(rst_ui===1'b1 && rst_riu===1'b1)) begin
            #10000;
            ticks++;
            if (ticks>1000) $fatal(1,"Reset did not propagate within 10us: %s",label);
        end
        checks++;
        snapshot(label);
    endtask

    initial begin
        samples=$fopen("observations.tsv","w");
        if (!samples) $fatal(1,"Cannot open observations");
        $fdisplay(samples,"label\ttime_ps\tsource_running\tsys_rst\tphy_pll_lock\tmmcm_lock\tinput_reset\tmmcm_reset\tui_reset\triu_reset\tpll_gate");
        snapshot("configuration_initial");
        wait_ready("initial_ready");
        // 文档允许5ns输入脉冲；特意放在参考时钟两次采样之间。
        @(negedge input_clock);
        #1000; sys_rst=1;
        #5000; snapshot("5ns_pulse_end"); sys_rst=0;
        wait_reset("short_pulse_propagated");
        wait_ready("short_pulse_recovered");
        // PHY锁定撤回的数字刺激；验证局部复位自动恢复并不提供粘滞隔离。
        phy_pll_lock=0;
        wait_reset("phy_unlock_reset");
        #2000000;
        phy_pll_lock=1;
        wait_ready("phy_relocked_auto_release");
        // 参考停钟时，异步输入捕获仍可置位，但参考域寄存链不能推进。
        @(negedge input_clock);
        clock_enabled=0;
        #2000000;
        snapshot("source_stopped");
        sys_rst=1;
        #2000000;
        snapshot("reset_while_source_stopped");
        if (dut.rst_input_async !== 2'b11 || dut.input_rst_design !== 1'b0)
            $fatal(1,"Unexpected reference-domain behavior during stopped clock");
        checks++;
        clock_enabled=1;
        wait_reset("source_restored_reset_propagated");
        #2000000;
        sys_rst=0;
        wait_ready("source_restored_auto_release");
        snapshot("final");
        $fclose(samples);
        $display("MIG_RESET_OBSERVATION_PASS checks=%0d; actual public RTL plus vendor MMCM simulation; no DDR PHY/analog validation",checks);
        $finish;
    end
    initial begin
        #500000000;
        $fatal(1,"Global observation timeout");
    end
endmodule
