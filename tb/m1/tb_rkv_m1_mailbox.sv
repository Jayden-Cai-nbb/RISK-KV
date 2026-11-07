`timescale 1ns/1ps
module tb_rkv_m1_mailbox;
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
    logic boot_hold = 1;
    logic host_reset_request = '0;
    logic host_valid = '0;
    logic [15:0] host_addr = '0;
    logic [31:0] host_wdata = '0;
    logic [3:0] host_wstrb = '0;
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
    assign fabric_idle = !pending && (run_count < 7 || run_count > 11);
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
    task automatic hword(input integer word_index, input logic write_op, input logic [31:0] value);
        @(negedge clk);
        host_valid = 1; host_addr = 16'(MAILBOX_BASE + 32'(word_index)*4);
        host_wdata = value; host_wstrb = write_op ? 4'hf : 4'h0;
        do begin @(posedge clk); #1; end while (!host_ready);
        if (host_error) $fatal(1,"host mailbox access rejected");
        hvalue = host_rdata;
        @(negedge clk); host_valid = 0; host_wstrb = 0;
        repeat (4) @(negedge clk);
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
        cold_reset = 1;
        repeat (5) @(posedge clk);
        @(negedge clk); cold_reset = 0;
        repeat (20) @(posedge clk);
        if (accepted_count != 0) $fatal(1,"CPU ran while boot held");
        @(negedge clk); boot_hold = 0;
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
        @(negedge clk); host_reset_request = 1;
        @(negedge clk); host_reset_request = 0;
        ready_epoch(2);
        if (committed_tasks != 1 || built_tokens != 0 || session_valid || generation != 2)
            $fatal(1,"controlled reset crossed identity/commit domain");
        host_session++;
        submit(OP_BOOT); acknowledge(0,0);
        submit(OP_REGISTER); acknowledge(0,0);
        submit(OP_BUILD); acknowledge(0,0);
        if (built_tokens != 4 || generation != 3 || committed_tasks != 2) $fatal(1,"restart service failed");
        // 冷复位也不清 RAM：旧 READY_EPOCH 保留，主机必须在 boot_hold 内主动清零。
        @(negedge clk);boot_hold=1;cold_reset=1;
        repeat(5) @(negedge clk);
        cold_reset=0;
        hword(MB_READY_EPOCH,0,0);
        if(hvalue!=2 || epoch!=1) $fatal(1,"retained mailbox cold-boot premise changed");
        $display("M1_MAILBOX_STALE_READY_COUNTEREXAMPLE retained=%0d hardware_epoch=%0d",hvalue,epoch);
        hword(MB_READY_EPOCH,1,0);hword(MB_READY_EPOCH,0,0);
        if(hvalue!=0) $fatal(1,"cold host did not clear startup flag");
        @(negedge clk);boot_hold=0;
        ready_epoch(1);host_session++;
        submit(OP_BOOT);acknowledge(0,0);
        submit(OP_REGISTER);acknowledge(0,0);
        submit(OP_BUILD);acknowledge(0,0);
        if(built_tokens!=4 || generation!=1 || committed_tasks!=1) $fatal(1,"new cold mailbox service failed");
        $display("M1_MAILBOX_PASS checks=%0d launches=%0d commits=%0d epoch=%0d scope=real_RV32I_mock_NPU",checks,launches,committed_tasks,epoch);
        $finish;
    end
    initial begin
        #100000000;
        $fatal(1,"mailbox test timeout");
    end
endmodule
