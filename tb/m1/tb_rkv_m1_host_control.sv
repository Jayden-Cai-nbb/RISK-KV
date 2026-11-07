`timescale 1ns/1ps
module tb_rkv_m1_host_control;
    import rkv_m1_layout_pkg::*;
    logic clk = '0;
    logic cold_reset = '0;
    logic cpu_reset_pulse;
    logic fabric_idle = '0;
    logic fabric_error = '0;
    logic cmd_ready;
    logic cq_valid;
    logic [31:0] cq_op;
    logic [31:0] cq_status;
    logic [63:0] cq_session;
    logic [31:0] cq_epoch;
    logic [63:0] cq_sequence;
    logic [31:0] cq_context;
    logic [31:0] cq_generation;
    logic [31:0] cq_token0;
    logic [31:0] cq_token1;
    logic isolated;
    logic reset_pending;
    logic session_valid;
    logic [63:0] session;
    logic [31:0] epoch;
    logic [63:0] next_sequence;
    logic [31:0] generation;
    logic [31:0] object_id;
    logic [2:0] object_state;
    logic bound_pair;
    logic [31:0] built_tokens;
    logic [31:0] decode_steps;
    logic [63:0] accepted_count;
    logic [63:0] rejected_count;
    logic [63:0] committed_tasks;
    logic [31:0] last_error;
    logic npu_halted = '0;
    logic npu_error = '0;
    logic loader_busy = '0;
    logic loader_start;
    logic [31:0] loader_addr;
    logic [31:0] loader_count;
    logic npu_reset;
    logic [31:0] npu_args [8];
    logic result_store_valid = '0;
    logic [31:0] result_store_addr = '0;
    logic [1023:0] result_store_data = '0;
    logic [31:0] result_store_mask = '0;
    logic result_other_write = '0;
    logic protocol_error;
    logic launch_pulse;
    logic [63:0] task_cycles;
    logic [63:0] loader_cycles;
    logic flush_req;
    logic flush_ack = '0;
    logic req_valid;
    logic req_ready = '0;
    logic req_write;
    logic [31:0] req_addr;
    logic [1023:0] req_data;
    logic [127:0] req_mask;
    logic rsp_valid = '0;
    logic rsp_ready;
    logic rsp_error = '0;
    logic [1023:0] rsp_data = '0;
    logic [31:0] clear_fault_code;
    logic [63:0] clear_reads_accepted;
    logic [63:0] clear_reads_retired;
    logic [63:0] clear_writes_accepted;
    logic [63:0] clear_writes_retired;
    logic [63:0] clear_cleaned_bytes;
    logic boot_hold;
    logic cpu_boot_waiting;
    logic host_reset_request;
    logic host_valid;
    logic [15:0] host_addr;
    logic [31:0] host_wdata;
    logic [3:0] host_wstrb;
    logic host_ready;
    logic [31:0] host_rdata;
    logic host_error;
    logic trap;
    logic test_done;
    logic [31:0] test_code;
    logic token_trace_valid;
    logic token_trace_row;
    logic [31:0] token_trace_data;
    always #5 clk = !clk;
    rkv_m1_cpu dut (
        .clk(clk),
        .cold_reset(cold_reset),
        .cpu_reset_pulse(cpu_reset_pulse),
        .fabric_idle(fabric_idle),
        .fabric_error(fabric_error),
        .cmd_ready(cmd_ready),
        .cq_valid(cq_valid),
        .cq_op(cq_op),
        .cq_status(cq_status),
        .cq_session(cq_session),
        .cq_epoch(cq_epoch),
        .cq_sequence(cq_sequence),
        .cq_context(cq_context),
        .cq_generation(cq_generation),
        .cq_token0(cq_token0),
        .cq_token1(cq_token1),
        .isolated(isolated),
        .reset_pending(reset_pending),
        .session_valid(session_valid),
        .session(session),
        .epoch(epoch),
        .next_sequence(next_sequence),
        .generation(generation),
        .object_id(object_id),
        .object_state(object_state),
        .bound_pair(bound_pair),
        .built_tokens(built_tokens),
        .decode_steps(decode_steps),
        .accepted_count(accepted_count),
        .rejected_count(rejected_count),
        .committed_tasks(committed_tasks),
        .last_error(last_error),
        .npu_halted(npu_halted),
        .npu_error(npu_error),
        .loader_busy(loader_busy),
        .loader_start(loader_start),
        .loader_addr(loader_addr),
        .loader_count(loader_count),
        .npu_reset(npu_reset),
        .npu_args(npu_args),
        .result_store_valid(result_store_valid),
        .result_store_addr(result_store_addr),
        .result_store_data(result_store_data),
        .result_store_mask(result_store_mask),
        .result_other_write(result_other_write),
        .protocol_error(protocol_error),
        .launch_pulse(launch_pulse),
        .task_cycles(task_cycles),
        .loader_cycles(loader_cycles),
        .flush_req(flush_req),
        .flush_ack(flush_ack),
        .req_valid(req_valid),
        .req_ready(req_ready),
        .req_write(req_write),
        .req_addr(req_addr),
        .req_data(req_data),
        .req_mask(req_mask),
        .rsp_valid(rsp_valid),
        .rsp_ready(rsp_ready),
        .rsp_error(rsp_error),
        .rsp_data(rsp_data),
        .clear_fault_code(clear_fault_code),
        .clear_reads_accepted(clear_reads_accepted),
        .clear_reads_retired(clear_reads_retired),
        .clear_writes_accepted(clear_writes_accepted),
        .clear_writes_retired(clear_writes_retired),
        .clear_cleaned_bytes(clear_cleaned_bytes),
        .boot_hold(boot_hold),
        .boot_waiting(cpu_boot_waiting),
        .host_reset_request(host_reset_request),
        .host_valid(host_valid),
        .host_addr(host_addr),
        .host_wdata(host_wdata),
        .host_wstrb(host_wstrb),
        .host_ready(host_ready),
        .host_rdata(host_rdata),
        .host_error(host_error),
        .trap(trap),
        .test_done(test_done),
        .test_code(test_code),
        .token_trace_valid(token_trace_valid),
        .token_trace_row(token_trace_row),
        .token_trace_data(token_trace_data)
    );
    logic platform_ready = 1;
    logic platform_error = 0;
    logic ddr_idle = 1;
    logic ddr_accept_now = 0;
    logic [31:0] status_flags = 0;
    logic control_idle;
    logic [63:0] control_requests;
    logic [3:0] s_awid = 0;
    logic [31:0] s_awaddr = 0;
    logic [7:0] s_awlen = 0;
    logic [2:0] s_awsize = 3;
    logic [1:0] s_awburst = 1;
    logic s_awlock = 0;
    logic s_awvalid = 0;
    logic s_awready;
    logic [63:0] s_wdata = 0;
    logic [7:0] s_wstrb = 0;
    logic s_wlast = 0;
    logic s_wvalid = 0;
    logic s_wready;
    logic [3:0] s_bid;
    logic [1:0] s_bresp;
    logic s_bvalid;
    logic s_bready = 0;
    logic [3:0] s_arid = 0;
    logic [31:0] s_araddr = 0;
    logic [7:0] s_arlen = 0;
    logic [2:0] s_arsize = 3;
    logic [1:0] s_arburst = 1;
    logic s_arlock = 0;
    logic s_arvalid = 0;
    logic s_arready;
    logic [3:0] s_rid;
    logic [63:0] s_rdata;
    logic [1:0] s_rresp;
    logic s_rlast;
    logic s_rvalid;
    logic s_rready = 0;
    rkv_m1_host_control control (
        .clk(clk),
        .cold_reset(cold_reset),
        .platform_ready(platform_ready),
        .platform_error(platform_error),
        .ddr_idle(ddr_idle),
        .ddr_accept_now(ddr_accept_now),
        .status_flags(status_flags),
        .epoch(epoch),
        .generation(generation),
        .error_code(last_error),
        .host_verified(64'd123),
        .native_verified(64'd456),
        .accepted_reads(64'd789),
        .accepted_writes(64'd987),
        .rejected_requests(64'd654),
        .boot_hold(boot_hold),
        .reset_request(host_reset_request),
        .control_idle(control_idle),
        .control_requests(control_requests),
        .host_valid(host_valid),
        .host_addr(host_addr),
        .host_wdata(host_wdata),
        .host_wstrb(host_wstrb),
        .host_ready(host_ready),
        .host_rdata(host_rdata),
        .host_error(host_error),
        .s_awid(s_awid),
        .s_awaddr(s_awaddr),
        .s_awlen(s_awlen),
        .s_awsize(s_awsize),
        .s_awburst(s_awburst),
        .s_awlock(s_awlock),
        .s_awvalid(s_awvalid),
        .s_awready(s_awready),
        .s_wdata(s_wdata),
        .s_wstrb(s_wstrb),
        .s_wlast(s_wlast),
        .s_wvalid(s_wvalid),
        .s_wready(s_wready),
        .s_bid(s_bid),
        .s_bresp(s_bresp),
        .s_bvalid(s_bvalid),
        .s_bready(s_bready),
        .s_arid(s_arid),
        .s_araddr(s_araddr),
        .s_arlen(s_arlen),
        .s_arsize(s_arsize),
        .s_arburst(s_arburst),
        .s_arlock(s_arlock),
        .s_arvalid(s_arvalid),
        .s_arready(s_arready),
        .s_rid(s_rid),
        .s_rdata(s_rdata),
        .s_rresp(s_rresp),
        .s_rlast(s_rlast),
        .s_rvalid(s_rvalid),
        .s_rready(s_rready)
    );
    integer task_limit = 20000;
    integer run_count = 0;
    integer load_countdown = 0;
    integer launches = 0;
    integer loads = 0;
    integer clean_requests = 0;
    logic pending = 0;
    logic [31:0] rng = 32'h57a12213;
    assign req_ready = !pending && rng[0];
    assign rsp_valid = pending;
    assign rsp_error = 1'b0;
    assign rsp_data = 1024'd0;
    assign fabric_idle = ddr_idle && !pending && (run_count < 7 || run_count > 11);
    assign flush_ack = flush_req && fabric_idle;
    assign npu_halted = !npu_reset && run_count >= task_limit;
    always @(posedge clk) begin
        if (cold_reset) begin
            pending <= 0; run_count <= 0; loader_busy <= 0;
            result_store_valid <= 0;
        end else begin
            rng <= {rng[30:0], rng[31] ^ rng[21] ^ rng[1] ^ rng[0]};
            if (req_valid && req_ready) begin
                pending <= 1;
                clean_requests <= clean_requests + 1;
            end
            if (rsp_valid && rsp_ready) pending <= 0;
            if (loader_start) begin
                loader_busy <= 1; load_countdown <= 4; loads <= loads + 1;
            end else if (load_countdown > 0) begin
                load_countdown <= load_countdown - 1;
                if (load_countdown == 1) loader_busy <= 0;
            end
            if (npu_reset) run_count <= 0;
            else run_count <= run_count + 1;
            if (launch_pulse) launches <= launches + 1;
            result_store_valid <= 0;
            if (!npu_reset && run_count == 9) begin
                result_store_valid <= 1;
                result_store_addr <= RESULT_ADDRESS >> 2;
                result_store_mask <= 32'd3;
                result_store_data <= 1024'd0;
                result_store_data[31:0] <= loader_addr == BUILD_ADDR ? 32'h3f800000 : 32'h43bb0000;
                result_store_data[63:32] <= loader_addr == BUILD_ADDR ? 32'h40800000 : 32'h41e00000;
            end
            if (trap || isolated || protocol_error) $fatal(1, "CPU/service failure trap=%b isolated=%b error=%0d", trap, isolated, last_error);
            if (test_done) $fatal(1,"mailbox firmware unexpected test exit");
        end
    end
    integer serial = 0;
    integer checks = 0;
    logic [31:0] hvalue;
    logic [31:0] saved [11];
    logic [63:0] host_session = 64'h1234567812345678;
    // 主机只从公开 RAM 端口访问邮箱，不能直接读写 DUT 内存或强制状态。
    integer seed;
    integer axi_reads=0;
    integer axi_writes=0;
    integer mailbox_events=0;
    integer reset_events=0;
    logic [63:0] axvalue;
    logic b_stalled=0;
    logic r_stalled=0;
    logic [5:0] last_b;
    logic [70:0] last_r;
    always @(posedge clk) begin
        if (cold_reset) begin b_stalled<=0; r_stalled<=0; end
        else begin
            if (host_valid && !host_ready) mailbox_events<=mailbox_events+1;
            if (host_reset_request) reset_events<=reset_events+1;
            if (b_stalled && (!s_bvalid || {s_bid,s_bresp}!==last_b)) $fatal(1,"B changed while blocked");
            if (r_stalled && (!s_rvalid || {s_rid,s_rresp,s_rlast,s_rdata}!==last_r)) $fatal(1,"R changed while blocked");
            b_stalled<=s_bvalid&&!s_bready; r_stalled<=s_rvalid&&!s_rready;
            last_b<={s_bid,s_bresp};last_r<={s_rid,s_rresp,s_rlast,s_rdata};
        end
    end
    task automatic axwrite(input logic [31:0] adr, input logic [63:0] data,
        input logic [7:0] mask, input logic [7:0] len, input logic [2:0] size,
        input logic [1:0] burst, input logic lock, input logic good_last,
        input logic [1:0] expected);
        logic [3:0] id;
        id=4'(axi_writes); axi_writes++;
        @(negedge clk);
        s_awid=id;s_awaddr=adr;s_awlen=len;s_awsize=size;s_awburst=burst;s_awlock=lock;
        s_wdata=data;s_wstrb=mask;s_wlast=(len==0)&&good_last;
        // 实际覆盖W先于AW，WVALID不能决定地址READY。
        s_wvalid=1;
        repeat(3) begin @(posedge clk); if(s_wready) $fatal(1,"W accepted without AW"); end
        @(negedge clk);s_awvalid=1;
        do @(posedge clk); while(!s_awready);
        @(negedge clk);s_awvalid=0;
        for(int i=0;i<=int'(len);i++) begin
            s_wvalid=1;s_wlast=(i==int'(len))?good_last:!good_last;
            do @(posedge clk); while(!s_wready);
            @(negedge clk);s_wvalid=0;
            repeat($urandom_range(0,3)) @(negedge clk);
        end
        while(!s_bvalid) @(negedge clk);
        if(s_bid!==id || s_bresp!==expected) $fatal(1,"B adr=%h got=%0d expected=%0d id=%h",adr,s_bresp,expected,s_bid);
        repeat($urandom_range(1,7)) @(negedge clk);
        s_bready=1;@(posedge clk);@(negedge clk);s_bready=0;
        checks++;
    endtask
    task automatic axread(input logic [31:0] adr,input logic [7:0] len,
        input logic [2:0] size,input logic [1:0] expected);
        logic [3:0] id;
        id=4'(axi_reads);axi_reads++;
        @(negedge clk);s_arid=id;s_araddr=adr;s_arlen=len;s_arsize=size;
        s_arvalid=1;
        do @(posedge clk);while(!s_arready);
        @(negedge clk);s_arvalid=0;
        for(int i=0;i<=int'(len);i++) begin
            while(!s_rvalid) @(negedge clk);
            if(s_rid!==id || s_rresp!==expected || s_rlast!==(i==int'(len)))
                $fatal(1,"R adr=%h id=%h resp=%0d last=%b beat=%0d",adr,s_rid,s_rresp,s_rlast,i);
            axvalue=s_rdata;
            repeat($urandom_range(1,7)) @(negedge clk);
            s_rready=1;@(posedge clk);@(negedge clk);s_rready=0;
            checks++;
        end
    endtask
    task automatic hword(input integer word_index, input logic write_op, input logic [31:0] value);
        if(write_op) axwrite(32'h80010000+32'(word_index)*8,{32'd0,value},8'hff,0,3,1,0,1,0);
        else begin
            axread(32'h80010000+32'(word_index)*8,0,3,0);
            if(axvalue[63:32]!=0) $fatal(1,"mailbox read reserved bits nonzero");
            hvalue=axvalue[31:0];
        end
    endtask
    task automatic control_prelude;
        integer before_events;
        // 同沿AR/AW竞争：接受AW后保留AR，直到写响应被消费，不能吞地址。
        @(negedge clk);
        s_awvalid=1;s_awaddr=32'h80010000;s_awid=4'hd;s_awlen=0;
        s_arvalid=1;s_araddr=32'h80010000;s_arid=4'he;s_arlen=0;
        @(posedge clk);if(!s_awready || s_arready) $fatal(1,"AW arbitration not exclusive");
        @(negedge clk);s_awvalid=0;s_wvalid=1;s_wdata=64'h11223344;s_wstrb=8'hff;s_wlast=1;
        do @(posedge clk);while(!s_wready);
        @(negedge clk);s_wvalid=0;
        while(!s_bvalid) @(negedge clk);
        repeat(5) begin @(posedge clk);if(s_arready || s_bid!=4'hd || s_bresp!=0) $fatal(1,"pending AR/B responsibility");end
        @(negedge clk);s_bready=1;@(posedge clk);@(negedge clk);s_bready=0;
        do @(posedge clk);while(!s_arready);
        @(negedge clk);s_arvalid=0;
        while(!s_rvalid) @(negedge clk);
        if(s_rid!=4'he || s_rresp!=0 || !s_rlast || s_rdata!=64'h11223344) $fatal(1,"concurrent read lost or wrong target");
        s_rready=1;@(posedge clk);@(negedge clk);s_rready=0;
        checks++;
        axread(32'h80000000,0,3,0);
        if(axvalue!==64'h0000000152564b50) $fatal(1,"platform identity mismatch");
        axread(32'h80000040,0,3,0);
        if(axvalue!==1) $fatal(1,"experiment support false claim");
        axread(32'h80000048,0,3,0);
        if(axvalue!==0) $fatal(1,"unbound build identity not zero");
        axread(32'h80000050,0,3,0);if(axvalue!=123) $fatal(1,"host counter wrong");
        axread(32'h80000058,0,3,0);if(axvalue!=456) $fatal(1,"native counter wrong");
        for(int i=0;i<64;i++) hword(i,1,32'h12340000+32'(i));
        for(int i=0;i<64;i++) begin hword(i,0,0);if(hvalue!=(32'h12340000+32'(i))) $fatal(1,"mailbox alias %0d",i);end
        axwrite(32'h800101f8,64'h00ab00cd,8'h05,0,3,1,0,1,0);
        hword(63,0,0);if(hvalue!=32'h12ab00cd) $fatal(1,"mailbox byte masks");
        before_events=mailbox_events;
        axwrite(32'h800101f8,64'hffffffffffffffff,8'h00,0,3,1,0,1,0);
        axwrite(32'h800101f8,64'h100000000,8'hff,0,3,1,0,1,2);
        axwrite(32'h800101f8,64'd0,8'hff,0,3,1,0,0,2);
        axwrite(32'h800101f8,64'd0,8'hff,2,3,1,0,1,3);
        axwrite(32'h800101f8,64'd0,8'hff,255,3,1,0,1,3);
        axread(32'h800101f8,255,3,3);
        axread(32'h80010004,0,3,3);axread(32'h80010200,0,3,3);
        axread(32'h7ffffff8,0,3,3);axread(32'h80000000,0,2,3);
        axwrite(32'h80000000,64'd1,8'hff,0,3,1,0,1,2);
        axwrite(32'h80000010,64'h52554e31,8'h0e,0,3,1,0,1,2);
        axwrite(32'h80000010,64'h52554e31,8'hff,0,3,0,0,1,3);
        axwrite(32'h80000010,64'h52554e31,8'hff,0,3,1,1,1,3);
        if(mailbox_events!=before_events) $fatal(1,"rejected or zero-mask operation touched mailbox");
        platform_ready=0;axwrite(32'h80000010,64'h52554e31,8'hff,0,3,1,0,1,2);platform_ready=1;
        platform_error=1;axwrite(32'h80000010,64'h52554e31,8'hff,0,3,1,0,1,2);
        axread(32'h80000008,0,3,0);if(!axvalue[34]) $fatal(1,"status inaccessible during error");platform_error=0;
        ddr_idle=0;axwrite(32'h80000010,64'h52554e31,8'hff,0,3,1,0,1,2);ddr_idle=1;
        ddr_accept_now=1;axwrite(32'h80000010,64'h52554e31,8'hff,0,3,1,0,1,2);ddr_accept_now=0;
        if(!boot_hold || !cpu_boot_waiting || accepted_count!=0) $fatal(1,"boot release bypassed qualification");
        // 清理测试的邮箱控制内容，CPU冷启动仍丢弃旧门铃。
        hword(MB_READY_EPOCH,1,0);hword(MB_DOORBELL,1,0);hword(MB_CANCEL_SERIAL,1,0);
        $display("M1_HOST_CONTROL_PRELUDE checks=%0d mailbox_events=%0d",checks,mailbox_events);
    endtask
    task automatic ready_epoch(input logic [31:0] expected);
        do hword(MB_READY_EPOCH,0,0); while (hvalue != expected);
    endtask
    task automatic stage(input logic [31:0] action, input logic [31:0] op);
        hword(MB_ACTION,1,action); hword(MB_OP,1,op);
        hword(MB_SESSION0,1,host_session[31:0]); hword(MB_SESSION1,1,host_session[63:32]);
        hword(MB_EPOCH,1,epoch); hword(MB_SEQUENCE0,1,next_sequence[31:0]);
        hword(MB_SEQUENCE1,1,next_sequence[63:32]); hword(MB_CONTEXT,1,7);
        hword(MB_GENERATION,1,generation); hword(MB_TOKEN0,1,3555); hword(MB_TOKEN1,1,8429);
    endtask
    task automatic ring;
        serial++; hword(MB_DOORBELL,1,32'(serial));
    endtask
    task automatic response(input logic [31:0] expected);
        do hword(MB_RESPONSE,0,0); while (hvalue != 32'(serial));
        hword(MB_RESULT,0,0);
        if (hvalue != expected) $fatal(1,"mailbox result got=%h expected=%h serial=%0d",hvalue,expected,serial);
        for (int i=0;i<11;i++) begin hword(MB_CQ0+i,0,0); saved[i]=hvalue; end
        checks++;
    endtask
    task automatic submit(input logic [31:0] op);
        stage(1,op); ring(); response(0);
    endtask
    task automatic acknowledge(input logic corrupt_identity, input logic [31:0] expected);
        hword(MB_ACTION,1,2);
        for (int i=0;i<7;i++) hword(MB_SESSION0+i,1,saved[2+i] ^ ((corrupt_identity && i==0)?32'd1:32'd0));
        ring(); response(expected);
    endtask
    initial begin
        if (!$value$plusargs("seed=%d", seed)) seed=1;
        $display("M1_HOST_CONTROL_SEED=%0d uses_runtime_verilator_seed",seed);
        cold_reset = 1;
        repeat (5) @(posedge clk);
        @(negedge clk); cold_reset = 0;
        repeat (20) @(posedge clk);
        if (accepted_count != 0) $fatal(1,"CPU ran while boot held");
        control_prelude();
        axwrite(32'h80000010,64'h52554e31,8'hff,0,3,1,0,1,0);
        ready_epoch(1);
        stage(1,OP_BOOT);
        repeat (2000) @(posedge clk);
        if (accepted_count != 0) $fatal(1,"partial descriptor submitted before doorbell");
        ring(); response(0); acknowledge(0,0);
        submit(OP_REGISTER); acknowledge(0,0);
        submit(OP_BUILD);
        repeat (2000) @(posedge clk);
        if (built_tokens != 0 || committed_tasks != 0 || !cq_valid) $fatal(1,"result committed before host consumption");
        acknowledge(1,8);
        if (built_tokens != 0 || !cq_valid) $fatal(1,"wrong host identity consumed result");
        acknowledge(0,0);
        if (built_tokens != 4 || committed_tasks != 1) $fatal(1,"correct host consumption failed");
        // 正确ACK可以完成逻辑消费，但主机尚未退休时新任务必须被拒绝。
        @(negedge clk); ddr_idle=0;
        stage(1,OP_BUILD); ring(); response(32'h80020006);
        if (launches!=1 || committed_tasks!=1) $fatal(1,"busy platform admitted new task");
        @(negedge clk); ddr_idle=1;
        repeat (4) @(negedge clk);
        // 重复门铃不重新提交。随后新任务在执行中收到异步取消。
        hword(MB_DOORBELL,1,32'(serial)); repeat (2000) @(posedge clk);
        if (committed_tasks != 1 || launches != 1) $fatal(1,"duplicate doorbell repeated work");
        stage(1,OP_BUILD); ring(); wait(!npu_reset);
        hword(MB_CANCEL_SERIAL,1,1); response(1);
        acknowledge(0,0);
        if (built_tokens != 4 || committed_tasks != 1 || object_state != 3) $fatal(1,"cancel committed progress");
        submit(OP_RECOVER); acknowledge(0,0);
        submit(OP_REGISTER); acknowledge(0,0);
        if (generation != 2) $fatal(1,"recovery did not change generation");
        // 独立复位请求不依赖 CPU 完成等待循环；旧 RAM 门铃保留并在新 epoch 丢弃。
        stage(1,OP_BUILD); ring(); wait(!npu_reset);
        axwrite(32'h80000018,64'h52535431,8'hff,0,3,1,0,1,0);
        ready_epoch(2);
        if (committed_tasks != 1 || built_tokens != 0 || session_valid || generation != 2)
            $fatal(1,"controlled reset crossed identity/commit domain");
        host_session++;
        submit(OP_BOOT); acknowledge(0,0);
        submit(OP_REGISTER); acknowledge(0,0);
        submit(OP_BUILD); acknowledge(0,0);
        if (built_tokens != 4 || generation != 3 || committed_tasks != 2) $fatal(1,"restart service failed");
        // 冷复位也不清 RAM：旧 READY_EPOCH 保留，主机必须在 boot_hold 内主动清零。
        @(negedge clk);cold_reset=1;
        repeat(5) @(negedge clk);
        cold_reset=0;
        hword(MB_READY_EPOCH,0,0);
        if(hvalue!=2 || epoch!=1) $fatal(1,"retained mailbox cold-boot premise changed");
        $display("M1_MAILBOX_STALE_READY_COUNTEREXAMPLE retained=%0d hardware_epoch=%0d",hvalue,epoch);
        hword(MB_READY_EPOCH,1,0);hword(MB_READY_EPOCH,0,0);
        if(hvalue!=0) $fatal(1,"cold host did not clear startup flag");
        axwrite(32'h80000010,64'h52554e31,8'hff,0,3,1,0,1,0);
        ready_epoch(1);host_session++;
        submit(OP_BOOT);acknowledge(0,0);
        submit(OP_REGISTER);acknowledge(0,0);
        submit(OP_BUILD);acknowledge(0,0);
        if(built_tokens!=4 || generation!=1 || committed_tasks!=1) $fatal(1,"new cold mailbox service failed");
        $display("M1_HOST_CONTROL_PASS seed=%0d checks=%0d launches=%0d commits=%0d epoch=%0d reads=%0d writes=%0d reset_events=%0d scope=AXI64_real_RV32I_mock_NPU",seed,checks,launches,committed_tasks,epoch,axi_reads,axi_writes,reset_events);
        $finish;
    end
    initial begin
        #100000000;
        $fatal(1,"mailbox test timeout");
    end
endmodule
