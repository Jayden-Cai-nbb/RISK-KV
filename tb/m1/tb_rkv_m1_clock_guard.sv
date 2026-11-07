`timescale 1ns/1ps
module tb_rkv_m1_clock_guard;
    logic clk = 0;
    logic clock_running = 1;
    always #10 clk = clock_running ? !clk : 1'b0;
    logic cold_reset;
    logic [3:0] healthy = 4'b0000;
    wire admission_enable;
    wire clock_fault;
    wire [3:0] fault_causes;
    wire armed;
    rkv_m1_clock_guard guard (
        .core_clk(clk),
        .chain_cold_reset(cold_reset),
        .core_locked(healthy[0]),
        .ddr_locked(healthy[1]),
        .ddr_calibrated(healthy[2]),
        .transport_ready(healthy[3]),
        .admission_enable(admission_enable),
        .fault(clock_fault),
        .fault_causes(fault_causes),
        .armed(armed)
    );
    logic [1:0] n_cvalid;
    logic [1:0] n_cready;
    logic [1:0] n_cwe;
    logic [1:0] n_wvalid;
    logic [1:0] n_wready;
    logic [1:0] n_rvalid;
    logic [1:0][24:0] n_caddr;
    logic [1:0][511:0] n_wdata;
    logic [1:0][511:0] n_rdata;
    logic [1:0][63:0] n_wmask;
    logic [1:0][15:0] n_wdone;
    logic idle;
    logic fault;
    logic [31:0] fault_code;
    logic [63:0] verified_writes;
    logic [3:0] m_awid;
    logic [3:0] m_arid;
    logic [3:0] m_bid;
    logic [3:0] m_rid;
    logic [32:0] m_awaddr;
    logic [32:0] m_araddr;
    logic [7:0] m_awlen;
    logic [7:0] m_arlen;
    logic [2:0] m_awsize;
    logic [2:0] m_arsize;
    logic [2:0] m_awprot;
    logic [2:0] m_arprot;
    logic [1:0] m_awburst;
    logic [1:0] m_arburst;
    logic [1:0] m_bresp;
    logic [1:0] m_rresp;
    logic m_awlock;
    logic m_arlock;
    logic [3:0] m_awcache;
    logic [3:0] m_arcache;
    logic [3:0] m_awqos;
    logic [3:0] m_arqos;
    logic m_awvalid;
    logic m_awready;
    logic m_wvalid;
    logic m_wready;
    logic m_wlast;
    logic m_bvalid;
    logic m_bready;
    logic m_arvalid;
    logic m_arready;
    logic m_rvalid;
    logic m_rready;
    logic m_rlast;
    logic [511:0] m_wdata;
    logic [511:0] m_rdata;
    logic [63:0] m_wstrb;
    rkv_m1_native_axi #(.TIMEOUT_CYCLES(2048)) dut (
        .clk(clk),
        .cold_reset(cold_reset),
        .admission_enable(admission_enable),
        .external_fault(clock_fault),
        .n_cvalid(n_cvalid),
        .n_cready(n_cready),
        .n_cwe(n_cwe),
        .n_caddr(n_caddr),
        .n_wvalid(n_wvalid),
        .n_wready(n_wready),
        .n_wdata(n_wdata),
        .n_wmask(n_wmask),
        .n_rvalid(n_rvalid),
        .n_rdata(n_rdata),
        .n_wdone(n_wdone),
        .idle(idle),
        .fault(fault),
        .fault_code(fault_code),
        .verified_writes(verified_writes),
        .m_awid(m_awid),
        .m_awaddr(m_awaddr),
        .m_awlen(m_awlen),
        .m_awsize(m_awsize),
        .m_awburst(m_awburst),
        .m_awlock(m_awlock),
        .m_awcache(m_awcache),
        .m_awprot(m_awprot),
        .m_awqos(m_awqos),
        .m_awvalid(m_awvalid),
        .m_awready(m_awready),
        .m_wdata(m_wdata),
        .m_wstrb(m_wstrb),
        .m_wlast(m_wlast),
        .m_wvalid(m_wvalid),
        .m_wready(m_wready),
        .m_bid(m_bid),
        .m_bresp(m_bresp),
        .m_bvalid(m_bvalid),
        .m_bready(m_bready),
        .m_arid(m_arid),
        .m_araddr(m_araddr),
        .m_arlen(m_arlen),
        .m_arsize(m_arsize),
        .m_arburst(m_arburst),
        .m_arlock(m_arlock),
        .m_arcache(m_arcache),
        .m_arprot(m_arprot),
        .m_arqos(m_arqos),
        .m_arvalid(m_arvalid),
        .m_arready(m_arready),
        .m_rid(m_rid),
        .m_rdata(m_rdata),
        .m_rresp(m_rresp),
        .m_rlast(m_rlast),
        .m_rvalid(m_rvalid),
        .m_rready(m_rready)
    );
    logic retire_idle;
    logic retire_error;
    logic [63:0] ra[2];
    logic [63:0] rr[2];
    logic [63:0] wa[2];
    logic [63:0] da[2];
    logic [63:0] wr[2];
    rkv_m1_native_retirement retirement (
        .clk(clk),
        .cold_reset(cold_reset),
        .cvalid(n_cvalid),
        .cready(n_cready),
        .cwe(n_cwe),
        .wvalid(n_wvalid),
        .wready(n_wready),
        .rvalid(n_rvalid),
        .wdone(n_wdone),
        .platform_error(fault || clock_fault),
        .idle(retire_idle),
        .error(retire_error),
        .read_accepted(ra),
        .read_retired(rr),
        .write_accepted(wa),
        .data_accepted(da),
        .write_retired(wr)
    );

    integer checks = 0;
    integer read_publications = 0;
    integer cycles;
    logic [32:0] held_address;
    logic [511:0] held_data;
    logic [63:0] held_mask;
    localparam logic [511:0] PAYLOAD = {16{32'h1234abcd}};

    // 所有同步刺激在下降沿更新；接受沿观察旧ready，沿后检查寄存结果。
    task automatic check(input bit ok, input string message);
        checks++;
        if (!ok) $fatal(1, "%s time=%0t guard=%h bridge=%0d/%0d", message,
                        $time, fault_causes, fault, fault_code);
    endtask
    task automatic tick;
        @(posedge clk); #1;
    endtask
    task automatic clear_inputs;
        n_cvalid = 0;
        n_cwe = 0;
        n_caddr = 0;
        n_wvalid = 0;
        n_wdata = 0;
        n_wmask = 0;
        m_awready = 0;
        m_wready = 0;
        m_arready = 0;
        m_bid = 0;
        m_bresp = 0;
        m_bvalid = 0;
        m_rid = 0;
        m_rdata = PAYLOAD;
        m_rresp = 0;
        m_rlast = 1;
        m_rvalid = 0;
    endtask
    task automatic cold_start;
        // 这是整链冷复位模型：外部所有返回也丢弃，不冒充仅复位控制器。
        @(negedge clk);
        cold_reset = 1;
        clear_inputs();
        healthy = 4'b0000;
        repeat (3) tick();
        check(!admission_enable && !clock_fault && !armed, "Cold startup closed/clear");
        @(negedge clk); cold_reset = 0;
        repeat (4) tick();
        check(!clock_fault && !admission_enable && n_cready == 0 && n_wready == 0,
              "Unqualified startup must not latch a runtime fault or accept requests");
    endtask
    task automatic qualify;
        @(negedge clk); healthy = 4'b1111;
        cycles = 0;
        while (!admission_enable && cycles < 25) begin
            tick(); cycles++;
        end
        check(cycles == 19 && armed && !clock_fault, "Three sync plus sixteen qualifying edges");
    endtask
    task automatic issue_native(input bit write_request);
        @(negedge clk);
        check(n_cready[0] && (!write_request || n_wready[0]), "Native must be ready");
        n_cvalid = 1;
        n_cwe = write_request ? 2'b01 : 2'b00;
        n_caddr[0] = 25'd7;
        n_wvalid = write_request ? 2'b01 : 2'b00;
        n_wdata[0] = PAYLOAD;
        n_wmask[0] = 64'hffffffffffffffff;
        @(posedge clk);
        check(n_cready[0] && (!write_request || n_wready[0]), "Native accepted exactly once");
        @(negedge clk); n_cvalid = 0; n_wvalid = 0;
    endtask
    task automatic wait_ar;
        integer waits;
        waits = 0;
        while (!m_arvalid && waits < 10) begin tick(); waits++; end
        check(m_arvalid && m_araddr == 33'd960 && m_arsize == 6 && m_arlen == 0,
              "Expected linear address/beat for AR");
    endtask
    task automatic accept_ar;
        wait_ar();
        @(negedge clk); m_arready = 1;
        tick();
        @(negedge clk); m_arready = 0;
    endtask
    task automatic send_r;
        @(negedge clk); m_rvalid = 1;
        tick();
        @(negedge clk); m_rvalid = 0;
    endtask
    task automatic accept_write;
        integer waits;
        waits = 0;
        while (!(m_awvalid && m_wvalid) && waits < 10) begin tick(); waits++; end
        check(m_awvalid && m_wvalid && m_awaddr == 33'd960 && m_wdata == PAYLOAD,
              "Expected write request");
        @(negedge clk); m_awready = 1; m_wready = 1;
        tick();
        @(negedge clk); m_awready = 0; m_wready = 0;
    endtask
    task automatic send_b;
        @(negedge clk); m_bvalid = 1;
        tick();
        @(negedge clk); m_bvalid = 0;
    endtask
    task automatic check_quarantine;
        check(clock_fault && fault && fault_code == 7 && !admission_enable,
              "Platform fault must be sticky and bridge reason must be seven");
        check(n_cready == 0 && n_wready == 0 && !idle && !retire_idle && retire_error,
              "No new acceptance or reusable-idle qualification in quarantine");
        check(n_wdone == 0 && verified_writes == 0 && read_publications == 0,
              "No successful read/write publication after failed transaction");
    endtask
    always @(posedge clk) begin
        if (cold_reset) read_publications <= 0;
        else if (n_rvalid[0]) read_publications <= read_publications + 1;
    end

    initial begin
        cold_reset = 1;
        clear_inputs();
        cold_start();
        // 首次校准可能耗时很长；未armed时健康低不能被误报为运行故障。
        @(negedge clk); healthy = 4'b0111;
        repeat (32) tick();
        check(!armed && !clock_fault && !admission_enable, "Transport reset not released");
        qualify();
        issue_native(0); accept_ar(); send_r();
        check(n_rdata[0] == PAYLOAD, "Normal read data");
        tick();
        check(read_publications == 1 && ra[0] == 1 && rr[0] == 1, "Normal read retirement");
        issue_native(1); accept_write(); send_b();
        check(n_wdone == 0, "B is not verified retirement");
        accept_ar(); send_r(); tick();
        check(n_wdone[0] == 1 && wr[0] == 1 && verified_writes == 1 && !fault,
              "Normal write verified exactly once");

        // 每种健康原因都在core完全停止时撤回5ns并恢复；不依赖core采到低电平。
        for (integer cause = 0; cause < 4; cause++) begin
            cold_start(); qualify(); issue_native(0); wait_ar();
            held_address = m_araddr;
            @(negedge clk); clock_running = 0;
            #3; healthy[cause] = 0;
            #5;
            check(clock_fault && fault_causes == (4'b0001 << cause) && !admission_enable,
                  "Stopped-core transient fault captured with reason");
            check(m_arvalid && m_araddr == held_address, "Fault cannot withdraw stalled AR");
            healthy[cause] = 1;
            #45;
            check(clock_fault && !admission_enable, "Relock while stopped cannot clear fault");
            clock_running = 1;
            repeat (25) tick();
            check_quarantine();
            accept_ar(); send_r(); repeat (3) tick();
            check_quarantine();
            check(ra[0] == 1 && rr[0] == 0, "Failed read remains unretired logically");
            check(!m_arvalid, "Late AR/R has drained without redispatch");
        end

        // AW已接受但W仍背压；故障不能撤回W或修改负载，迟到B不得发校验读。
        cold_start(); qualify(); issue_native(1);
        repeat (2) tick();
        check(m_awvalid && m_wvalid, "Both write channels offered");
        held_data = m_wdata; held_mask = m_wstrb;
        @(negedge clk); m_awready = 1;
        tick();
        @(negedge clk); m_awready = 0; healthy[1] = 0;
        repeat (3) tick();
        check(!m_awvalid && m_wvalid && m_wdata == held_data && m_wstrb == held_mask,
              "Accepted AW and stalled W preserved through fault");
        @(negedge clk); healthy[1] = 1; m_wready = 1;
        tick();
        @(negedge clk); m_wready = 0;
        send_b(); repeat (3) tick();
        check_quarantine();
        check(!m_arvalid && wa[0] == 1 && da[0] == 1 && wr[0] == 0,
              "Failed write must not issue a new verification read or retire");

        // 错误与普通读返回位于同一个接收周期；不能等下一拍fault才屏蔽成功。
        cold_start(); qualify(); issue_native(0); accept_ar();
        @(negedge clk); m_rvalid = 1; healthy[2] = 0;
        tick();
        check(n_rvalid == 0, "Fault beats same-edge ordinary read publication");
        @(negedge clk); m_rvalid = 0; healthy[2] = 1;
        repeat (3) tick(); check_quarantine();

        // 同样的竞争发生在写校验返回：既不递增wdone，也不递增统计。
        cold_start(); qualify(); issue_native(1); accept_write(); send_b(); accept_ar();
        @(negedge clk); m_rvalid = 1; healthy[0] = 0;
        tick();
        check(n_wdone == 0 && verified_writes == 0, "Fault beats same-edge verified write");
        @(negedge clk); m_rvalid = 0; healthy[0] = 1;
        repeat (3) tick(); check_quarantine();

        // 停core期间的短cold脉冲不算完整冷启动：没有同步清除原因位，不能误恢复。
        @(negedge clk); clock_running = 0;
        #3; cold_reset = 1;
        #5; cold_reset = 0;
        #45; clock_running = 1;
        repeat (30) tick();
        check(clock_fault && !admission_enable, "Unclocked reset pulse must not clear quarantine");
        cold_start(); qualify();
        issue_native(0); accept_ar(); send_r(); tick();
        check(read_publications == 1 && !clock_fault && !fault && retire_idle,
              "Only genuine cold restart restores service");

        // 没有新命令的旧响应不能越过新代际；模型不预填任何计算结果。
        cold_start(); qualify(); send_r(); repeat (3) tick();
        check(fault && fault_code == 2 && n_rvalid == 0 && read_publications == 0,
              "Orphan response after cold restart is rejected");
        $display("M1_CLOCK_GUARD_PASS checks=%0d; digital guard+bridge+retirement, no DDR/CDC/board", checks);
        $finish;
    end
    initial begin
        #1000000;
        $fatal(1, "Global clock-guard test timeout");
    end
endmodule

