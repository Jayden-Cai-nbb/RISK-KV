// 平台候选：core 域双 native 通道 -> 单在途 AXI4/512。
// 写 B 后读回校验才推进 wdone；冷复位必须同时复位整个 AXI/DDR 链路。
// 未接真实 DDR/主机仲裁或 CDC，不加入冻结 M1 核心源清单。
module rkv_m1_native_axi #(
    parameter int unsigned TIMEOUT_CYCLES = 1000000
) (
    input logic clk,
    input logic cold_reset,
    input logic admission_enable,
    input logic external_fault,
    input logic [1:0] n_cvalid,
    output logic [1:0] n_cready,
    input logic [1:0] n_cwe,
    input logic [1:0][24:0] n_caddr,
    input logic [1:0] n_wvalid,
    output logic [1:0] n_wready,
    input logic [1:0][511:0] n_wdata,
    input logic [1:0][63:0] n_wmask,
    output logic [1:0] n_rvalid,
    output logic [1:0][511:0] n_rdata,
    output logic [1:0][15:0] n_wdone,
    output logic idle,
    output logic fault,
    output logic [31:0] fault_code,
    output logic [63:0] verified_writes,
    output logic [3:0] m_awid,
    output logic [32:0] m_awaddr,
    output logic [7:0] m_awlen,
    output logic [2:0] m_awsize,
    output logic [1:0] m_awburst,
    output logic m_awlock,
    output logic [3:0] m_awcache,
    output logic [2:0] m_awprot,
    output logic [3:0] m_awqos,
    output logic m_awvalid,
    input logic m_awready,
    output logic [511:0] m_wdata,
    output logic [63:0] m_wstrb,
    output logic m_wlast,
    output logic m_wvalid,
    input logic m_wready,
    input logic [3:0] m_bid,
    input logic [1:0] m_bresp,
    input logic m_bvalid,
    output logic m_bready,
    output logic [3:0] m_arid,
    output logic [32:0] m_araddr,
    output logic [7:0] m_arlen,
    output logic [2:0] m_arsize,
    output logic [1:0] m_arburst,
    output logic m_arlock,
    output logic [3:0] m_arcache,
    output logic [2:0] m_arprot,
    output logic [3:0] m_arqos,
    output logic m_arvalid,
    input logic m_arready,
    input logic [3:0] m_rid,
    input logic [511:0] m_rdata,
    input logic [1:0] m_rresp,
    input logic m_rlast,
    input logic m_rvalid,
    output logic m_rready
);
    typedef enum logic [2:0] {S_IDLE, S_WRITE, S_B, S_AR, S_R} state_t;
    state_t state;
    logic [1:0] cmd_full;
    logic [1:0] data_full;
    logic [1:0] cmd_write;
    logic [1:0][24:0] cmd_addr;
    logic [1:0][511:0] data_value;
    logic [1:0][63:0] data_mask;
    logic turn;
    logic chosen;
    logic choose_valid;
    logic active_channel;
    logic active_write;
    logic [32:0] active_addr;
    logic [511:0] active_data;
    logic [63:0] active_mask;
    logic aw_done;
    logic w_done;
    logic busy;
    logic progress;
    logic mismatch;
    logic [31:0] stall_count;
    logic [31:0] error_now;

    // 两槽公平选择；同通道读/写命令 FIFO 顺序保持，写数据可以先于命令。
    always_comb begin
        choose_valid = 1'b0;
        chosen = turn;
        if (cmd_full[turn] && (!cmd_write[turn] || data_full[turn])) begin
            choose_valid = 1'b1;
        end else if (cmd_full[!turn] && (!cmd_write[!turn] || data_full[!turn])) begin
            chosen = !turn;
            choose_valid = 1'b1;
        end
    end

    // 所有 AXI 事务为对齐 64-byte 单 beat，ID=0；地址是线性字节地址。
    assign m_awid = 4'd0;
    assign m_awaddr = active_addr;
    assign m_awlen = 8'd0;
    assign m_awsize = 3'd6;
    assign m_awburst = 2'b01;
    assign m_awlock = 1'b0;
    assign m_awcache = 4'd0;
    assign m_awprot = 3'd0;
    assign m_awqos = 4'd0;
    assign m_awvalid = !cold_reset && state == S_WRITE && !aw_done;
    assign m_wdata = active_data;
    assign m_wstrb = active_mask;
    assign m_wlast = 1'b1;
    assign m_wvalid = !cold_reset && state == S_WRITE && !w_done;
    assign m_bready = !cold_reset;
    assign m_arid = 4'd0;
    assign m_araddr = active_addr;
    assign m_arlen = 8'd0;
    assign m_arsize = 3'd6;
    assign m_arburst = 2'b01;
    assign m_arlock = 1'b0;
    assign m_arcache = 4'd0;
    assign m_arprot = 3'd0;
    assign m_arqos = 4'd0;
    assign m_arvalid = !cold_reset && state == S_AR;
    assign m_rready = !cold_reset;

    // 错误不会撤回已有 AXI VALID；它只关闭新准入/派发并禁止成功退休。
    always_comb begin
        mismatch = 1'b0;
        for (int byte_index = 0; byte_index < 64; byte_index++) begin
            if (active_mask[byte_index] &&
                m_rdata[byte_index*8 +: 8] != active_data[byte_index*8 +: 8]) mismatch = 1'b1;
        end
        error_now = 32'd0;
        // 平台失锁/校准撤回必须在本沿阻断结果发布，不能只等下一拍fault寄存器。
        if (external_fault) error_now = 32'd7;
        else if (m_bvalid && (state != S_B || m_bid != 0 || m_bresp != 0)) error_now = 32'd1;
        else if (m_rvalid && (state != S_R || m_rid != 0 || m_rresp != 0 || !m_rlast)) error_now = 32'd2;
        else if (state == S_R && m_rvalid && active_write && mismatch) error_now = 32'd3;
        else if (state == S_IDLE && choose_valid && cmd_addr[chosen][24]) error_now = 32'd4;

        // 2 GiB 固定布局：channel address bit24 必须为零，不默默截断高地址。
        n_cready = ~cmd_full & {2{admission_enable && !cold_reset && !fault && error_now == 0}};
        n_wready = ~data_full & {2{admission_enable && !cold_reset && !fault && error_now == 0}};
        busy = state != S_IDLE || (|cmd_full) || (|data_full);
        progress = (|(n_cvalid & n_cready)) || (|(n_wvalid & n_wready)) ||
                   (m_awvalid && m_awready) || (m_wvalid && m_wready) ||
                   (m_arvalid && m_arready) || m_bvalid || m_rvalid;
        idle = !fault && error_now == 0 && !busy && !(|n_rvalid);
    end

    // 缓存、派发身份、计数由本过程拥有；超时后的在途状态保留至排空或全链冷复位。
    always_ff @(posedge clk) begin
        if (cold_reset) begin
            state <= S_IDLE;
            cmd_full <= 2'b00;
            data_full <= 2'b00;
            cmd_write <= '0;
            cmd_addr <= '0;
            data_value <= '0;
            data_mask <= '0;
            active_channel <= 1'b0;
            active_write <= 1'b0;
            active_addr <= '0;
            active_data <= '0;
            active_mask <= '0;
            aw_done <= 1'b0;
            w_done <= 1'b0;
            turn <= 1'b0;
            n_rvalid <= '0;
            n_rdata <= '0;
            n_wdone <= '0;
            fault <= 1'b0;
            fault_code <= 32'd0;
            stall_count <= 32'd0;
            verified_writes <= 64'd0;
        end else begin
            n_rvalid <= 2'b00;
            if (!busy || progress) stall_count <= 32'd0;
            else if (!fault) stall_count <= stall_count + 32'd1;
            if (!fault) begin
                if (error_now != 0) begin
                    fault <= 1'b1;
                    fault_code <= error_now;
                end else if (busy && !progress && stall_count >= TIMEOUT_CYCLES - 1) begin
                    fault <= 1'b1;
                    fault_code <= 32'd5;
                end
            end
            for (int channel = 0; channel < 2; channel++) begin
                if (n_cvalid[channel] && n_cready[channel]) begin
                    cmd_full[channel] <= 1'b1;
                    cmd_write[channel] <= n_cwe[channel];
                    cmd_addr[channel] <= n_caddr[channel];
                end
                if (n_wvalid[channel] && n_wready[channel]) begin
                    data_full[channel] <= 1'b1;
                    data_value[channel] <= n_wdata[channel];
                    data_mask[channel] <= n_wmask[channel];
                end
            end
            case (state)
                S_IDLE: if (choose_valid && admission_enable && !fault && error_now == 0) begin
                    active_channel <= chosen;
                    active_write <= cmd_write[chosen];
                    // CHASH=1：完整 channel beat XOR 决定 128-byte 块内的高/低半部。
                    active_addr <= {1'b0, cmd_addr[chosen], (chosen ^ (^cmd_addr[chosen])), 6'd0};
                    active_data <= data_value[chosen];
                    active_mask <= data_mask[chosen];
                    cmd_full[chosen] <= 1'b0;
                    turn <= !chosen;
                    aw_done <= 1'b0;
                    w_done <= 1'b0;
                    if (cmd_write[chosen]) begin
                        data_full[chosen] <= 1'b0;
                        state <= S_WRITE;
                    end else state <= S_AR;
                end
                S_WRITE: begin
                    if (m_awvalid && m_awready) aw_done <= 1'b1;
                    if (m_wvalid && m_wready) w_done <= 1'b1;
                    if ((aw_done || m_awready) && (w_done || m_wready)) state <= S_B;
                end
                S_B: if (m_bvalid) begin
                    if (!fault && error_now == 0) state <= S_AR;
                    else state <= S_IDLE;
                end
                S_AR: if (m_arready) state <= S_R;
                S_R: if (m_rvalid && m_rlast) begin
                    state <= S_IDLE;
                    if (!fault && error_now == 0) begin
                        if (active_write) begin
                            n_wdone[active_channel] <= n_wdone[active_channel] + 16'd1;
                            verified_writes <= verified_writes + 64'd1;
                        end else begin
                            n_rvalid[active_channel] <= 1'b1;
                            n_rdata[active_channel] <= m_rdata;
                        end
                    end
                end
                default: begin
                    fault <= 1'b1;
                    fault_code <= 32'd6;
                end
            endcase
        end
    end
endmodule
