`timescale 1ns/1ps
module tb_rkv_m1_native_adapter;
    logic clk = '0;
    logic cold_reset = '0;
    logic npu_reset = '0;
    logic loader_busy = '0;
    logic a_req = '0;
    logic a_we = '0;
    logic [31:0] a_addr = '0;
    logic [31:0] a_wdata = '0;
    logic [3:0] a_be = '0;
    logic a_rdy;
    logic a_rvalid;
    logic [255:0] a_rdata;
    logic sw_req = '0;
    logic [31:0] sw_addr = '0;
    logic [31:0] sw_wdata = '0;
    logic [3:0] sw_be = '0;
    logic sw_rdy;
    logic b_req = '0;
    logic b_we = '0;
    logic b_tag = '0;
    logic b_par = '0;
    logic [31:0] b_addr = '0;
    logic [1023:0] b_wdata = '0;
    logic [31:0] b_wmask = '0;
    logic b_rdy;
    logic b_rvalid;
    logic b_rtag;
    logic [1023:0] b_rdata;
    logic clean_req_valid = '0;
    logic clean_req_ready;
    logic clean_req_write = '0;
    logic [31:0] clean_req_addr = '0;
    logic [1023:0] clean_req_data = '0;
    logic [127:0] clean_req_mask = '0;
    logic clean_rsp_valid;
    logic clean_rsp_ready = '0;
    logic clean_rsp_error;
    logic [1023:0] clean_rsp_data;
    logic flush_req = '0;
    logic flush_ack;
    logic cache_flush;
    logic cache_flush_ack = '0;
    logic transport_idle = '0;
    logic transport_error = '0;
    logic mem_wr_idle = '0;
    logic mem_rd_idle = '0;
    logic fabric_idle;
    logic fabric_error;
    logic mem_a_req;
    logic mem_a_we;
    logic [31:0] mem_a_addr;
    logic [31:0] mem_a_wdata;
    logic [3:0] mem_a_be;
    logic mem_a_rdy = '0;
    logic mem_a_rvalid = '0;
    logic [255:0] mem_a_rdata = '0;
    logic mem_sw_req;
    logic [31:0] mem_sw_addr;
    logic [31:0] mem_sw_wdata;
    logic [3:0] mem_sw_be;
    logic mem_sw_rdy = '0;
    logic mem_b_req;
    logic mem_b_we;
    logic mem_b_tag;
    logic mem_b_par;
    logic [31:0] mem_b_addr;
    logic [1023:0] mem_b_wdata;
    logic [31:0] mem_b_wmask;
    logic mem_b_rdy = '0;
    logic mem_b_rvalid = '0;
    logic mem_b_rtag = '0;
    logic [1023:0] mem_b_rdata = '0;
    always #5 clk = !clk;
    rkv_m1_memory_arbiter dut (
        .clk(clk),
        .cold_reset(cold_reset),
        .npu_reset(npu_reset),
        .loader_busy(loader_busy),
        .a_req(a_req),
        .a_we(a_we),
        .a_addr(a_addr),
        .a_wdata(a_wdata),
        .a_be(a_be),
        .a_rdy(a_rdy),
        .a_rvalid(a_rvalid),
        .a_rdata(a_rdata),
        .sw_req(sw_req),
        .sw_addr(sw_addr),
        .sw_wdata(sw_wdata),
        .sw_be(sw_be),
        .sw_rdy(sw_rdy),
        .b_req(b_req),
        .b_we(b_we),
        .b_tag(b_tag),
        .b_par(b_par),
        .b_addr(b_addr),
        .b_wdata(b_wdata),
        .b_wmask(b_wmask),
        .b_rdy(b_rdy),
        .b_rvalid(b_rvalid),
        .b_rtag(b_rtag),
        .b_rdata(b_rdata),
        .clean_req_valid(clean_req_valid),
        .clean_req_ready(clean_req_ready),
        .clean_req_write(clean_req_write),
        .clean_req_addr(clean_req_addr),
        .clean_req_data(clean_req_data),
        .clean_req_mask(clean_req_mask),
        .clean_rsp_valid(clean_rsp_valid),
        .clean_rsp_ready(clean_rsp_ready),
        .clean_rsp_error(clean_rsp_error),
        .clean_rsp_data(clean_rsp_data),
        .flush_req(flush_req),
        .flush_ack(flush_ack),
        .cache_flush(cache_flush),
        .cache_flush_ack(cache_flush_ack),
        .transport_idle(transport_idle),
        .transport_error(transport_error),
        .mem_wr_idle(mem_wr_idle),
        .mem_rd_idle(mem_rd_idle),
        .fabric_idle(fabric_idle),
        .fabric_error(fabric_error),
        .mem_a_req(mem_a_req),
        .mem_a_we(mem_a_we),
        .mem_a_addr(mem_a_addr),
        .mem_a_wdata(mem_a_wdata),
        .mem_a_be(mem_a_be),
        .mem_a_rdy(mem_a_rdy),
        .mem_a_rvalid(mem_a_rvalid),
        .mem_a_rdata(mem_a_rdata),
        .mem_sw_req(mem_sw_req),
        .mem_sw_addr(mem_sw_addr),
        .mem_sw_wdata(mem_sw_wdata),
        .mem_sw_be(mem_sw_be),
        .mem_sw_rdy(mem_sw_rdy),
        .mem_b_req(mem_b_req),
        .mem_b_we(mem_b_we),
        .mem_b_tag(mem_b_tag),
        .mem_b_par(mem_b_par),
        .mem_b_addr(mem_b_addr),
        .mem_b_wdata(mem_b_wdata),
        .mem_b_wmask(mem_b_wmask),
        .mem_b_rdy(mem_b_rdy),
        .mem_b_rvalid(mem_b_rvalid),
        .mem_b_rtag(mem_b_rtag),
        .mem_b_rdata(mem_b_rdata)
    );
    logic run_flush = '0;
    logic platform_error = '0;
    logic [1:0] n_cvalid = '0;
    logic [1:0] n_cready = '0;
    logic [1:0] n_cwe = '0;
    logic [1:0][24:0] n_caddr = '0;
    logic [1:0] n_wvalid = '0;
    logic [1:0] n_wready = '0;
    logic [1:0][511:0] n_wdata = '0;
    logic [1:0][63:0] n_wmask = '0;
    logic [1:0] n_rvalid = '0;
    logic [1:0][511:0] n_rdata = '0;
    logic [1:0][15:0] n_wdone = '0;
    rkv_m1_native_memory backend (
        .clk(clk),
        .cold_reset(cold_reset),
        .run_flush(run_flush),
        .cache_flush(cache_flush),
        .cache_flush_ack(cache_flush_ack),
        .transport_idle(transport_idle),
        .transport_error(transport_error),
        .platform_error(platform_error),
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
        .mem_wr_idle(mem_wr_idle),
        .mem_rd_idle(mem_rd_idle),
        .mem_a_req(mem_a_req),
        .mem_a_we(mem_a_we),
        .mem_a_addr(mem_a_addr),
        .mem_a_wdata(mem_a_wdata),
        .mem_a_be(mem_a_be),
        .mem_a_rdy(mem_a_rdy),
        .mem_a_rvalid(mem_a_rvalid),
        .mem_a_rdata(mem_a_rdata),
        .mem_sw_req(mem_sw_req),
        .mem_sw_addr(mem_sw_addr),
        .mem_sw_wdata(mem_sw_wdata),
        .mem_sw_be(mem_sw_be),
        .mem_sw_rdy(mem_sw_rdy),
        .mem_b_req(mem_b_req),
        .mem_b_we(mem_b_we),
        .mem_b_tag(mem_b_tag),
        .mem_b_par(mem_b_par),
        .mem_b_addr(mem_b_addr),
        .mem_b_wdata(mem_b_wdata),
        .mem_b_wmask(mem_b_wmask),
        .mem_b_rdy(mem_b_rdy),
        .mem_b_rvalid(mem_b_rvalid),
        .mem_b_rtag(mem_b_rtag),
        .mem_b_rdata(mem_b_rdata)
    );
    typedef struct packed {logic write_op; logic [24:0] address;} command_t;
    typedef struct packed {logic [511:0] data; logic [63:0] mask;} write_t;
    command_t commands [2][$];
    write_t writes [2][$];
    command_t current [2];
    logic busy [2];
    integer delay_left [2];
    logic [511:0] memory [logic [31:0]];
    logic [31:0] rng = 32'h83c0a917;
    logic [1023:0] pattern;
    logic [1023:0] actual;
    integer checks = 0;
    integer transactions = 0;
    logic stop_returns = 0;
    assign run_flush = npu_reset;
    function automatic logic [511:0] read_beat(input integer channel, input logic [24:0] address);
        logic [31:0] key;
        logic [31:0] word_address;
        logic [511:0] value;
        key = {6'd0,1'(channel),address};
        word_address = {2'd0,address,5'd0} + ((1'(channel) ^ (^address)) ? 32'd16 : 32'd0);
        if (memory.exists(key)) return memory[key];
        for (int w = 0; w < 16; w++) value[w*32 +: 32] = 32'hf00d0000 ^ (word_address + 32'(w));
        return value;
    endfunction
    always @(negedge clk) begin
        rng = rng ^ (rng << 13); rng = rng ^ (rng >> 17); rng = rng ^ (rng << 5);
        for (int c = 0; c < 2; c++) begin
            n_cready[c] = commands[c].size() < 8 && rng[c];
            n_wready[c] = writes[c].size() < 8 && rng[c+2];
        end
    end
    always @(posedge clk) begin
        for (int c = 0; c < 2; c++) begin
            n_rvalid[c] <= 0;
            if (cold_reset) begin
                commands[c].delete(); writes[c].delete(); busy[c] = 0; delay_left[c] = 0;
                n_wdone[c] <= 16'hfff8;
            end else begin
                if (n_cvalid[c] && n_cready[c]) begin
                    commands[c].push_back('{n_cwe[c],n_caddr[c]});
                    transactions++;
                end
                if (n_wvalid[c] && n_wready[c]) writes[c].push_back('{n_wdata[c],n_wmask[c]});
                if (!busy[c] && commands[c].size() != 0) begin
                    current[c] = commands[c].pop_front(); busy[c] = 1;
                    delay_left[c] = int'(rng[6:3]) + 2;
                end
                if (busy[c] && delay_left[c] > 0) delay_left[c]--;
                if (busy[c] && delay_left[c] == 0 && !stop_returns) begin
                    if (current[c].write_op) begin
                        if (writes[c].size() != 0) begin
                            automatic write_t payload;
                            automatic logic [511:0] value;
                            payload = writes[c].pop_front();
                            value = read_beat(c,current[c].address);
                            for (int b = 0; b < 64; b++) if (payload.mask[b]) value[b*8 +: 8] = payload.data[b*8 +: 8];
                            memory[{6'd0,1'(c),current[c].address}] = value;
                            n_wdone[c] <= n_wdone[c] + 16'd1; busy[c] = 0;
                        end
                    end else begin
                        n_rdata[c] <= read_beat(c,current[c].address);
                        n_rvalid[c] <= 1; busy[c] = 0;
                    end
                end
            end
        end
    end
    task automatic tick(input integer n);
        repeat (n) begin @(posedge clk); #1; end
    endtask
    task automatic drain;
        do begin tick(1); end while (!fabric_idle);
        tick(3);
    endtask
    task automatic clear_access(input logic write_op, input logic [31:0] address,
                                input logic [127:0] mask, input logic expect_error);
        drain();
        @(negedge clk);
        clean_req_valid = 1; clean_req_write = write_op; clean_req_addr = address;
        clean_req_data = pattern; clean_req_mask = mask;
        do begin @(posedge clk); end while (!clean_req_ready);
        @(negedge clk); clean_req_valid = 0;
        while (!clean_rsp_valid) tick(1);
        if (clean_rsp_error != expect_error) $fatal(1, "clean response before retirement / wrong status");
        actual = clean_rsp_data;
        tick(5);
        if (!clean_rsp_valid || clean_req_ready || clean_rsp_data != actual) $fatal(1, "response under backpressure");
        @(negedge clk); clean_rsp_ready = 1;
        tick(1);
        @(negedge clk); clean_rsp_ready = 0;
        tick(3);
        checks += 2;
    endtask
    initial begin
        cold_reset = 1; npu_reset = 0;
        tick(4);
        @(negedge clk); cold_reset = 0;
        tick(4);
        @(negedge clk); sw_req = 1; sw_addr = 32'h1233; sw_wdata = 32'h12345678; sw_be = 4'b0101;
        do begin @(posedge clk); end while (!sw_rdy);
        @(negedge clk); sw_req = 0;
        drain();
        @(negedge clk); a_req = 1; a_we = 0; a_addr = 32'h1233;
        do begin @(posedge clk); end while (!a_rdy);
        @(negedge clk); a_req = 0;
        while (!a_rvalid) tick(1);
        if (a_rdata[3*32 +: 32] != 32'hf0341278) $fatal(1,"native SW RMW / A mapping");
        tick(1);
        if (transport_idle) $fatal(1,"unconsumed native prefetch incorrectly idle");
        drain();
        if (fabric_error) $fatal(1,"native initial retirement error");
        checks += 2;
        @(negedge clk); npu_reset = 1;
        for (int w = 0; w < 32; w++) pattern[w*32 +: 32] = 32'hcafe0000 + 32'(w);
        clear_access(1,32'h7fffff80,{128{1'b1}},0);
        clear_access(0,32'h7fffff80,128'd0,0);
        if (actual != pattern) $fatal(1,"native last 2 GiB chunk");
        clear_access(1,32'h00004000,{128{1'b1}},0);
        pattern = ~pattern;
        clear_access(1,32'h00004000,{16{8'h0f}},0);
        clear_access(0,32'h00004000,128'd0,0);
        for (int w = 0; w < 32; w++)
            if (actual[w*32 +: 32] != (w[0] ? ~pattern[w*32 +: 32] : pattern[w*32 +: 32])) $fatal(1,"native masked write");
        checks += 2;
        @(negedge clk); flush_req = 1;
        while (!flush_ack) tick(1);
        if (fabric_error || !transport_idle) $fatal(1,"native flush/retirement fence");
        @(negedge clk); flush_req = 0; npu_reset = 0;
        // NPU B 返回的 tag 和两通道重组保持原合同。
        @(negedge clk); b_req = 1; b_we = 0; b_addr = 32'h1000; b_tag = 1; b_par = ^b_addr[31:5];
        do begin @(posedge clk); end while (!b_rdy);
        @(negedge clk); b_req = 0;
        while (!b_rvalid) tick(1);
        if (!b_rtag || b_rdata != actual) $fatal(1,"native B response tag/order");
        drain();
        if (fabric_error) $fatal(1,"native integrated fabric fault");
        checks += 2;
        @(negedge clk); npu_reset = 1;
        for (int block_index=0;block_index<64;block_index++) begin
            for (int w=0;w<32;w++) pattern[w*32 +: 32] = 32'h7fc01234 ^ 32'(block_index*32+w);
            clear_access(1,32'h00400000+32'(block_index)*128,{128{1'b1}},0);
            clear_access(0,32'h00400000+32'(block_index)*128,128'd0,0);
            if (actual!=pattern) $fatal(1,"native randomized stream data mismatch");
        end
        // 延迟未返回请求绝不形成退休或失效应答；恢复响应后只退休一次。
        drain();
        @(negedge clk); stop_returns=1;
        clean_req_valid=1;clean_req_write=0;clean_req_addr=32'h00400100;clean_req_mask=0;
        do begin @(posedge clk); end while(!clean_req_ready);
        @(negedge clk);clean_req_valid=0;
        tick(100);
        if(clean_rsp_valid || transport_idle || fabric_idle) $fatal(1,"lost response falsely retired");
        @(negedge clk);flush_req=1;
        tick(20);
        if(flush_ack) $fatal(1,"cache fence acknowledged with lost response");
        @(negedge clk);stop_returns=0;
        while(!clean_rsp_valid) tick(1);
        @(negedge clk);clean_rsp_ready=1;
        tick(1);
        @(negedge clk);clean_rsp_ready=0;
        while(!flush_ack) tick(1);
        if(fabric_error || !transport_idle) $fatal(1,"late response accounting failed");
        checks+=3;
        $display("M1_NATIVE_ADAPTER_PASS checks=%0d physical_transactions=%0d seed=83c0a917",checks,transactions);
        $finish;
    end
    initial begin
        #1000000;
        $fatal(1,"test timeout");
    end
endmodule
