// 独立主机控制从端：AXI64单拍访问，邮箱每8字节别名只作用于一个32-bit字。
// 所有状态在core上升沿推进；仅整链cold_reset清状态，普通CPU复位不接本模块。
module rkv_m1_host_control #(
    parameter [63:0] EXPERIMENT_ID = 64'd0
) (
    input wire clk,
    input wire cold_reset,
    input wire platform_ready,
    input wire platform_error,
    input wire ddr_idle,
    input wire ddr_accept_now,
    input wire [31:0] status_flags,
    input wire [31:0] epoch,
    input wire [31:0] generation,
    input wire [31:0] error_code,
    input wire [63:0] host_verified,
    input wire [63:0] native_verified,
    input wire [63:0] accepted_reads,
    input wire [63:0] accepted_writes,
    input wire [63:0] rejected_requests,
    output reg boot_hold,
    output reg reset_request,
    output wire control_idle,
    output reg [63:0] control_requests,
    output wire host_valid,
    output wire [15:0] host_addr,
    output wire [31:0] host_wdata,
    output wire [3:0] host_wstrb,
    input wire host_ready,
    input wire [31:0] host_rdata,
    input wire host_error,
    input wire [3:0] s_awid,
    input wire [31:0] s_awaddr,
    input wire [7:0] s_awlen,
    input wire [2:0] s_awsize,
    input wire [1:0] s_awburst,
    input wire s_awlock,
    input wire s_awvalid,
    output wire s_awready,
    input wire [63:0] s_wdata,
    input wire [7:0] s_wstrb,
    input wire s_wlast,
    input wire s_wvalid,
    output wire s_wready,
    output wire [3:0] s_bid,
    output wire [1:0] s_bresp,
    output wire s_bvalid,
    input wire s_bready,
    input wire [3:0] s_arid,
    input wire [31:0] s_araddr,
    input wire [7:0] s_arlen,
    input wire [2:0] s_arsize,
    input wire [1:0] s_arburst,
    input wire s_arlock,
    input wire s_arvalid,
    output wire s_arready,
    output wire [3:0] s_rid,
    output wire [63:0] s_rdata,
    output wire [1:0] s_rresp,
    output wire s_rlast,
    output wire s_rvalid,
    input wire s_rready
);
    localparam [2:0] IDLE = 3'd0;
    localparam [2:0] WRITE_DATA = 3'd1;
    localparam [2:0] EXECUTE_WRITE = 3'd2;
    localparam [2:0] EXECUTE_READ = 3'd3;
    localparam [2:0] MAILBOX = 3'd4;
    localparam [2:0] RESP_B = 3'd5;
    localparam [2:0] RESP_R = 3'd6;
    reg [2:0] state;
    reg [31:0] address;
    reg [3:0] identity;
    reg [7:0] length;
    reg [7:0] beat;
    reg write_op;
    reg [31:0] write_data;
    reg [3:0] write_mask;
    reg [1:0] response;
    reg [63:0] read_data;
    reg [63:0] reset_requests;
    wire [4:0] register_id;
    wire mailbox_select;
    wire [15:0] mailbox_address;
    wire reserved_write_nonzero;

    rkv_m1_host_map address_map (
        .address(address),
        .register_id(register_id),
        .mailbox_select(mailbox_select),
        .mailbox_address(mailbox_address)
    );
    // 单在途，AW优先；W可先呈现但在AW接受后才有ready，不依赖WVALID发AWREADY。
    assign s_awready = !cold_reset && state == IDLE;
    assign s_arready = !cold_reset && state == IDLE && !s_awvalid;
    assign s_wready = !cold_reset && state == WRITE_DATA;
    assign s_bid = identity;
    assign s_bresp = response;
    assign s_bvalid = !cold_reset && state == RESP_B;
    assign s_rid = identity;
    assign s_rdata = read_data;
    assign s_rresp = response;
    assign s_rlast = beat == length;
    assign s_rvalid = !cold_reset && state == RESP_R;
    assign control_idle = state == IDLE && !cold_reset;
    // CPU的host_ready是寄存应答，保持valid到采样应答后撤回，避免重复写RAM。
    assign host_valid = !cold_reset && state == MAILBOX;
    assign host_addr = mailbox_address;
    assign host_wdata = write_data;
    assign host_wstrb = write_op ? write_mask : 4'd0;
    // 高32-bit为保留零；没有strobed的字节不参与保留位检查。
    assign reserved_write_nonzero = |(s_wdata[63:32] &
        {{8{s_wstrb[7]}}, {8{s_wstrb[6]}}, {8{s_wstrb[5]}}, {8{s_wstrb[4]}}});

    always @(posedge clk) begin
        if (cold_reset) begin
            state <= IDLE;
            address <= 32'd0;
            identity <= 4'd0;
            length <= 8'd0;
            beat <= 8'd0;
            write_op <= 1'b0;
            write_data <= 32'd0;
            write_mask <= 4'd0;
            response <= 2'd0;
            read_data <= 64'd0;
            boot_hold <= 1'b1;
            reset_request <= 1'b0;
            control_requests <= 64'd0;
            reset_requests <= 64'd0;
        end else begin
            reset_request <= 1'b0;
            case (state)
                IDLE: begin
                    beat <= 8'd0;
                    read_data <= 64'd0;
                    if (s_awvalid && s_awready) begin
                        address <= s_awaddr;
                        identity <= s_awid;
                        length <= s_awlen;
                        write_op <= 1'b1;
                        response <= (s_awlen == 8'd0 && s_awsize == 3'd3 &&
                            s_awburst == 2'd1 && !s_awlock && s_awaddr[2:0] == 3'd0) ? 2'd0 : 2'd3;
                        control_requests <= control_requests + 64'd1;
                        state <= WRITE_DATA;
                    end else if (s_arvalid && s_arready) begin
                        address <= s_araddr;
                        identity <= s_arid;
                        length <= s_arlen;
                        write_op <= 1'b0;
                        response <= (s_arlen == 8'd0 && s_arsize == 3'd3 &&
                            s_arburst == 2'd1 && !s_arlock && s_araddr[2:0] == 3'd0) ? 2'd0 : 2'd3;
                        control_requests <= control_requests + 64'd1;
                        state <= EXECUTE_READ;
                    end
                end
                WRITE_DATA: if (s_wvalid && s_wready) begin
                    write_data <= s_wdata[31:0];
                    write_mask <= s_wstrb[3:0];
                    if (response == 2'd0 && (reserved_write_nonzero || s_wlast != (beat == length)))
                        response <= 2'd2;
                    // 非法burst也按AWLEN耗尽，不执行其任一数据beat的控制副作用。
                    if (beat == length) state <= EXECUTE_WRITE;
                    else beat <= beat + 8'd1;
                end
                EXECUTE_WRITE: begin
                    state <= RESP_B;
                    if (response == 2'd0) begin
                        if (!mailbox_select && register_id == 5'd0) response <= 2'd3;
                        else if (write_mask == 4'd0) response <= 2'd0;
                        else if (mailbox_select) state <= MAILBOX;
                        else if (register_id == 5'd3 && write_mask == 4'hf && write_data == 32'h52554e31) begin
                            // 此处检查执行沿；首启不能与DDR地址接收或未退休访问交叉。
                            if (!boot_hold || (platform_ready && !platform_error && ddr_idle && !ddr_accept_now))
                                boot_hold <= 1'b0;
                            else response <= 2'd2;
                        end else if (register_id == 5'd4 && write_mask == 4'hf && write_data == 32'h52535431) begin
                            // 独立受控复位只发请求，不能清存储队列或解除平台隔离。
                            reset_request <= 1'b1;
                            reset_requests <= reset_requests + 64'd1;
                        end else response <= 2'd2;
                    end
                end
                EXECUTE_READ: begin
                    state <= RESP_R;
                    if (response == 2'd0) begin
                        if (mailbox_select) state <= MAILBOX;
                        else begin
                            // 单次结果在此沿冻结；后续状态变化不能改变受阻R负载。
                            case (register_id)
                                5'd1: read_data <= {32'd1, 32'h52564b50};
                                5'd2: read_data <= {27'd0, ddr_accept_now, ddr_idle, platform_error, platform_ready, boot_hold, status_flags};
                                5'd3: read_data <= {63'd0, boot_hold};
                                5'd4: read_data <= reset_requests;
                                5'd5: read_data <= {32'd0, epoch};
                                5'd6: read_data <= {32'd0, generation};
                                5'd7: read_data <= {32'd0, error_code};
                                5'd8: read_data <= {32'd192000000, 32'd50000000}; // 名义时钟方案，非板上测量。
                                5'd9: read_data <= 64'd1; // bit0实验，bit1厂商支持=0，不能冒充正式M1。
                                5'd10: read_data <= EXPERIMENT_ID; // 默认0为未绑定，实物顶层须提供构建身份。
                                5'd11: read_data <= host_verified;
                                5'd12: read_data <= native_verified;
                                5'd13: read_data <= accepted_reads;
                                5'd14: read_data <= accepted_writes;
                                5'd15: read_data <= rejected_requests;
                                5'd16: read_data <= control_requests;
                                default: response <= 2'd3;
                            endcase
                        end
                    end
                end
                MAILBOX: if (host_ready) begin
                    response <= host_error ? 2'd2 : 2'd0;
                    read_data <= {32'd0, host_rdata};
                    state <= write_op ? RESP_B : RESP_R;
                end
                RESP_B: if (s_bready) state <= IDLE;
                RESP_R: if (s_rready) begin
                    if (beat == length) state <= IDLE;
                    else beat <= beat + 8'd1;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
