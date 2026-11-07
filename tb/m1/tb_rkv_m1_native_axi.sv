`timescale 1ns/1ps
module tb_rkv_m1_native_axi;
    logic clk = 0;
    always #5 clk = !clk;
    logic cold_reset;
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
    rkv_m1_native_axi #(.TIMEOUT_CYCLES(64)) dut (
        .clk(clk),
        .cold_reset(cold_reset),
        .admission_enable(1'b1),
        .external_fault(1'b0),
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
        .platform_error(fault),
        .idle(retire_idle),
        .error(retire_error),
        .read_accepted(ra),
        .read_retired(rr),
        .write_accepted(wa),
        .data_accepted(da),
        .write_retired(wr)
    );

    // 独立线性 byte-memory 模型：AXI 地址直接索引；Golden 不读取 DUT 内部状态。
    logic [511:0] memory [int unsigned];
    logic [511:0] golden [int unsigned];
    logic aw_seen;
    logic w_seen;
    logic [32:0] aw_saved;
    logic [32:0] ar_saved;
    logic [511:0] w_saved;
    logic [63:0] mask_saved;
    integer b_delay;
    integer r_delay;
    integer mode;
    integer checks = 0;
    integer reads_seen = 0;
    integer axi_writes = 0;
    logic block_aw;
    logic block_ar;
    logic orphan_b;
    logic [31:0] random_state;
    integer initial_seed;
    logic [1:0][511:0] last_read;
    integer native_reads[2];
    logic hold_aw;
    logic hold_w;
    logic hold_ar;
    logic [32:0] stalled_aw;
    logic [32:0] stalled_ar;
    logic [511:0] stalled_w;
    logic [63:0] stalled_mask;
    function automatic logic [511:0] load_memory(input logic [32:0] addr);
        if (memory.exists(int'(addr >> 6)) != 0) return memory[int'(addr >> 6)];
        return 512'd0;
    endfunction
    function automatic logic [511:0] load_golden(input logic [31:0] addr);
        int unsigned index;
        index = addr >> 6;
        if (golden.exists(index) != 0) return golden[index];
        return 512'd0;
    endfunction
    task automatic check(input bit ok, input string message);
        checks++;
        if (!ok) $fatal(1, "%s time=%0t fault=%0d/%0d", message, $time, fault, fault_code);
    endtask
    task automatic tick;
        @(posedge clk); #1;
    endtask
    always @(negedge clk) begin
        random_state = (random_state >> 1) ^ (random_state[0] ? 32'h80200003 : 32'd0);
        m_awready = !cold_reset && !block_aw && !aw_seen && random_state[0];
        m_wready = !cold_reset && !w_seen && random_state[3];
        m_arready = !cold_reset && !block_ar && r_delay < 0 && !m_rvalid && random_state[7];
    end
    always @(posedge clk) begin
        if (cold_reset) begin
            aw_seen <= 0; w_seen <= 0; b_delay <= -1; r_delay <= -1;
            m_bvalid <= 0; m_rvalid <= 0; m_bresp <= 0; m_rresp <= 0;
            m_bid <= 0; m_rid <= 0; m_rlast <= 1; m_rdata <= 0;
            hold_aw <= 0; hold_w <= 0; hold_ar <= 0;
            for (int c=0;c<2;c++) native_reads[c] <= 0;
        end else begin
            // AXI VALID 在隔离/超时后也须保持，直到真实握手。
            if (hold_aw) check(m_awvalid && m_awaddr == stalled_aw, "AW changed while stalled");
            if (hold_ar) check(m_arvalid && m_araddr == stalled_ar, "AR changed while stalled");
            if (hold_w) check(m_wvalid && m_wdata == stalled_w && m_wstrb == stalled_mask, "W changed while stalled");
            hold_aw <= m_awvalid && !m_awready; stalled_aw <= m_awaddr;
            hold_ar <= m_arvalid && !m_arready; stalled_ar <= m_araddr;
            hold_w <= m_wvalid && !m_wready; stalled_w <= m_wdata; stalled_mask <= m_wstrb;
            if (m_awvalid && m_awready) begin
                check(m_awaddr < 33'h080000000 && m_awaddr[5:0] == 0, "AW range/alignment");
                check(m_awid == 0 && m_awlen == 0 && m_awsize == 6 && m_awburst == 1, "AW geometry");
                aw_seen <= 1; aw_saved <= m_awaddr;
            end
            if (m_wvalid && m_wready) begin
                check(m_wlast, "single-beat WLAST");
                w_seen <= 1; w_saved <= m_wdata; mask_saved <= m_wstrb;
            end
            if (aw_seen && w_seen && b_delay < 0 && !m_bvalid) begin
                logic [511:0] updated;
                updated = load_memory(aw_saved);
                for (int b=0;b<64;b++) if (mask_saved[b]) updated[b*8+:8] = w_saved[b*8+:8];
                memory[int'(aw_saved >> 6)] = updated;
                aw_seen <= 0; w_seen <= 0; b_delay <= int'(random_state[6:4]); axi_writes++;
            end
            if (b_delay > 0) b_delay <= b_delay-1;
            if (b_delay == 0) begin
                m_bvalid <= 1; m_bresp <= mode == 1 ? 2'b10 : 2'b00;
                m_bid <= mode == 7 ? 4'd1 : 4'd0; b_delay <= -1;
            end
            if (orphan_b) begin m_bvalid <= 1; m_bresp <= 0; m_bid <= 0; end
            if (m_bvalid && m_bready) m_bvalid <= 0;
            if (m_arvalid && m_arready) begin
                check(m_araddr < 33'h080000000 && m_araddr[5:0] == 0, "AR range/alignment");
                check(m_arid == 0 && m_arlen == 0 && m_arsize == 6 && m_arburst == 1, "AR geometry");
                ar_saved <= m_araddr; r_delay <= mode == 6 ? -1 : int'(random_state[11:8]); reads_seen++;
            end
            if (r_delay > 0) r_delay <= r_delay-1;
            if (r_delay == 0) begin
                m_rvalid <= 1; m_rdata <= load_memory(ar_saved) ^ (mode == 5 ? 512'd1 : 512'd0);
                m_rresp <= mode == 2 ? 2'b10 : 2'b00;
                m_rid <= mode == 3 ? 4'd1 : 4'd0; m_rlast <= mode != 4; r_delay <= -1;
            end
            if (m_rvalid && m_rready) m_rvalid <= 0;
            for (int c=0;c<2;c++) if (n_rvalid[c]) begin
                native_reads[c] <= native_reads[c]+1;
                last_read[c] <= n_rdata[c];
            end
        end
    end
    task automatic reset_chain;
        @(negedge clk);
        cold_reset=1; n_cvalid=0; n_wvalid=0; mode=0; block_aw=0; block_ar=0; orphan_b=0;
        repeat(3) tick();
        @(negedge clk); cold_reset=0;
        repeat(3) tick();
        check(idle && !fault, "cold restart idle");
    endtask
    task automatic command(input bit c, input bit write, input logic [24:0] addr);
        @(negedge clk); n_cvalid[c]=1; n_cwe[c]=write; n_caddr[c]=addr;
        do @(posedge clk); while (!n_cready[c]);
        @(negedge clk); n_cvalid[c]=0;
    endtask
    task automatic data(input bit c, input logic [511:0] value, input logic [63:0] mask);
        @(negedge clk); n_wvalid[c]=1; n_wdata[c]=value; n_wmask[c]=mask;
        do @(posedge clk); while (!n_wready[c]);
        @(negedge clk); n_wvalid[c]=0;
    endtask
    task automatic pair_write(input bit c, input logic [24:0] addr, input logic [511:0] value, input logic [63:0] mask, input bit data_first);
        if (data_first) begin data(c,value,mask); repeat(3) tick(); command(c,1,addr); end
        else begin command(c,1,addr); repeat(3) tick(); data(c,value,mask); end
    endtask
    task automatic wait_idle;
        integer cycles;
        cycles=0;
        do begin tick(); cycles++; if(cycles>1000) $fatal(1,"idle timeout"); end while (!idle || !retire_idle);
        check(!fault && !retire_error, "retirement invariants");
    endtask
    task automatic read_check(input logic [31:0] addr);
        logic [24:0] beat;
        bit c;
        integer old_count;
        integer cycles;
        beat=25'(addr>>7); c=addr[6] ^ (^beat); old_count=native_reads[c]; cycles=0;
        command(c,0,beat);
        while(native_reads[c]==old_count) begin tick(); cycles++; if(cycles>200) $fatal(1,"read timeout"); end
        check(last_read[c] == load_golden(addr), "linear golden readback mismatch");
    endtask
    task automatic expect_fault(input integer code);
        integer cycles;
        cycles=0;
        while(!fault) begin tick(); cycles++; if(cycles>200) $fatal(1,"missing fault"); end
        check(fault_code == code && !idle && n_cready == 0 && n_wready == 0, "isolation contract");
    endtask
    initial begin
        cold_reset=1; n_cvalid=0; n_cwe=0; n_caddr=0; n_wvalid=0; n_wdata=0; n_wmask=0;
        mode=0; block_aw=0; block_ar=0; orphan_b=0;
        if (!$value$plusargs("seed=%d",initial_seed)) initial_seed=1;
        random_state=32'(initial_seed); if(random_state==0) random_state=1;
        reset_chain();
        // 两逻辑通道同时提交，覆盖 parity 变化、字节掩码、零掩码与 2 GiB 末块。
        for(int k=0;k<80;k++) begin
            logic [24:0] beat;
            logic [511:0] v0;
            logic [511:0] v1;
            logic [63:0] mask;
            logic [31:0] addr0;
            logic [31:0] addr1;
            logic [511:0] g0;
            logic [511:0] g1;
            beat=k==79 ? 25'h0ffffff : 25'(k*37);
            v0={16{32'h5a000000+32'(k)}}; v1=~v0;
            mask=k%4==0 ? 64'd0 : k%4==1 ? 64'h5555555555555555 : k%4==2 ? 64'h8000000000000001 : '1;
            addr0=32'((64'(beat)*128)+((^beat)?64:0)); addr1=addr0 ^ 32'd64;
            g0=load_golden(addr0); g1=load_golden(addr1);
            for(int b=0;b<64;b++) if(mask[b]) begin g0[b*8+:8]=v0[b*8+:8]; g1[b*8+:8]=v1[b*8+:8]; end
            golden[addr0>>6]=g0; golden[addr1>>6]=g1;
            fork
                pair_write(0,beat,v0,mask,bit'(k));
                pair_write(1,beat,v1,mask,!bit'(k));
            join
            wait_idle();
            check(n_wdone[0] == 16'(k+1) && n_wdone[1] == 16'(k+1), "write retirement exactly once");
            read_check(addr0); read_check(addr1); wait_idle();
        end
        check(verified_writes==160 && reads_seen==320, "explicit verify-read cost");
        // 尚未配对的写数据不能被前面的读命令吃掉；同址排队写不得覆盖 active 身份。
        reset_chain();
        golden[0]=load_memory(33'd0);
        data(0,512'habcdef,'1);
        read_check(0);
        command(0,1,25'd0);
        wait_idle();
        golden[0]=512'habcdef;
        read_check(0);
        pair_write(0,25'd0,512'h1111,'1,0);
        pair_write(0,25'd0,512'h2222,'1,1);
        pair_write(0,25'd0,512'h3333,'1,0);
        wait_idle();
        golden[0]=512'h3333;
        read_check(0);
        check(n_wdone[0]==4, "queued same-address writes retain order");
        // 错误发生后物理写可保留，但不能成功退休；每次新例先全链复位，保留 memory。
        for(int f=1;f<=7;f++) begin
            reset_chain(); mode=f;
            pair_write(0,25'd0,512'h12345,'1,0);
            expect_fault(f==1 || f==7 ? 1 : f==5 ? 3 : f==6 ? 5 : 2);
            repeat(8) tick(); check(n_wdone==0 && n_rvalid==0, "failed write not retired");
        end
        reset_chain(); command(0,0,25'h1000000); expect_fault(4);
        reset_chain(); data(1,512'd9,'1); expect_fault(5);
        reset_chain(); command(1,1,25'd0); expect_fault(5);
        reset_chain(); orphan_b=1; repeat(2) tick(); orphan_b=0; expect_fault(1);
        // AW 超时后保持 VALID，迟到 AW/B 可排空但不发校验读，也不恢复准入。
        reset_chain(); block_aw=1; pair_write(0,25'd0,512'h333,'1,1); expect_fault(5);
        repeat(5) tick(); block_aw=0; repeat(60) tick();
        check(fault && !idle && n_wdone==0, "late B must not recover or retire");
        // AR 超时后仍保持请求；迟到 R 只排空，不能被后续身份消费。
        reset_chain(); block_ar=1; command(1,0,25'd0); expect_fault(5);
        block_ar=0; repeat(60) tick();
        check(fault && native_reads[1]==0 && !idle, "late R must not leak");
        reset_chain(); golden.delete(); golden[0]=load_memory(33'd0); read_check(0); wait_idle();
        $display("M1_NATIVE_AXI_PASS seed=%0d checks=%0d axi_writes=%0d axi_reads=%0d",initial_seed,checks,axi_writes,reads_seen);
        $finish;
    end
    initial begin #2000000; $fatal(1,"global watchdog"); end
endmodule
