// RV32 原生 MMIO：接受沿为 bus_valid && !bus_ready，非 AXI ready/valid。
// 本模块暂存 CPU 参数；复位不影响独立监督器、清理器或存储退休状态。
module rkv_m1_mmio (
    input logic clk,
    input logic cpu_reset,
    input logic bus_valid,
    input logic [11:0] bus_addr,
    input logic [31:0] bus_wdata,
    input logic [3:0] bus_wstrb,
    output logic bus_ready,
    output logic [31:0] bus_rdata,
    output logic cmd_valid,
    input logic cmd_ready,
    output logic [31:0] cmd_op,
    output logic [63:0] cmd_session,
    output logic [31:0] cmd_epoch,
    output logic [63:0] cmd_sequence,
    output logic [31:0] cmd_context,
    output logic [31:0] cmd_generation,
    output logic [31:0] cmd_token0,
    output logic [31:0] cmd_token1,
    output logic ack_valid,
    output logic cancel_valid,
    output logic reset_request,
    output logic [63:0] receipt_session,
    output logic [31:0] receipt_epoch,
    output logic [63:0] receipt_sequence,
    output logic [31:0] receipt_context,
    output logic [31:0] receipt_generation,
    input logic cq_valid,
    input logic [31:0] cq_op,
    input logic [31:0] cq_status,
    input logic [63:0] cq_session,
    input logic [31:0] cq_epoch,
    input logic [63:0] cq_sequence,
    input logic [31:0] cq_context,
    input logic [31:0] cq_generation,
    input logic [31:0] cq_token0,
    input logic [31:0] cq_token1,
    input logic isolated,
    input logic reset_pending,
    input logic session_valid,
    input logic [63:0] session,
    input logic [31:0] epoch,
    input logic [63:0] next_sequence,
    input logic [31:0] generation,
    input logic [31:0] object_id,
    input logic [2:0] object_state,
    input logic bound_pair,
    input logic [31:0] built_tokens,
    input logic [31:0] decode_steps,
    input logic [63:0] accepted_count,
    input logic [63:0] rejected_count,
    input logic [63:0] committed_tasks,
    input logic [63:0] clear_cleaned_bytes,
    input logic [31:0] last_error
);
    import rkv_m1_layout_pkg::*;
    logic [31:0] access_error;
    wire transfer = bus_valid && !bus_ready && !cpu_reset;
    wire write_full = transfer && bus_wstrb == 4'hf && bus_addr[1:0] == 0;
    wire [31:0] address = {20'd0, bus_addr};
    assign cmd_valid = write_full && address == REG_COMMAND && cmd_ready;
    assign cmd_op = bus_wdata;
    assign ack_valid = write_full && address == REG_ACK && bus_wdata == 32'd1;
    assign cancel_valid = write_full && address == REG_CANCEL && bus_wdata == 32'd1;
    assign reset_request = write_full && address == REG_RESET && bus_wdata == 32'd1;
    assign receipt_session = cmd_session;
    assign receipt_epoch = cmd_epoch;
    assign receipt_sequence = cmd_sequence;
    assign receipt_context = cmd_context;
    assign receipt_generation = cmd_generation;

    always_ff @(posedge clk) begin
        if (cpu_reset) begin
            bus_ready <= 1'b0;
            bus_rdata <= 32'd0;
            access_error <= 32'd0;
            cmd_session <= 64'd0;
            cmd_epoch <= 32'd0;
            cmd_sequence <= 64'd0;
            cmd_context <= 32'd0;
            cmd_generation <= 32'd0;
            cmd_token0 <= 32'd0;
            cmd_token1 <= 32'd0;
        end else begin
            bus_ready <= 1'b0;
            if (transfer) begin
                bus_ready <= 1'b1;
                bus_rdata <= 32'd0;
                if (bus_addr[1:0] != 0 || ((|bus_wstrb) && bus_wstrb != 4'hf)) access_error <= 32'h80000001;
                else if (bus_wstrb != 0) begin
                    access_error <= 32'd0;
                    case (address)
                        REG_COMMAND: if (!cmd_ready) access_error <= 32'h80000002;
                        REG_ACK, REG_CANCEL, REG_RESET: if (bus_wdata != 32'd1) access_error <= 32'h80000003;
                        REG_SESSION_LO: cmd_session[31:0] <= bus_wdata;
                        REG_SESSION_HI: cmd_session[63:32] <= bus_wdata;
                        REG_EPOCH: cmd_epoch <= bus_wdata;
                        REG_SEQUENCE_LO: cmd_sequence[31:0] <= bus_wdata;
                        REG_SEQUENCE_HI: cmd_sequence[63:32] <= bus_wdata;
                        REG_CONTEXT: cmd_context <= bus_wdata;
                        REG_GENERATION: cmd_generation <= bus_wdata;
                        REG_TOKEN0: cmd_token0 <= bus_wdata;
                        REG_TOKEN1: cmd_token1 <= bus_wdata;
                        default: access_error <= 32'h80000004;
                    endcase
                end else begin
                    case (address)
                        REG_ID: bus_rdata <= ABI_MAGIC;
                        REG_LAYOUT: bus_rdata <= LAYOUT_VERSION;
                        REG_STATUS: bus_rdata <= {21'd0, object_state, 2'd0, bound_pair, session_valid,
                                                 reset_pending, isolated, cq_valid, cmd_ready};
                        REG_ERROR: bus_rdata <= access_error != 0 ? access_error : last_error;
                        REG_SESSION_LO: bus_rdata <= session[31:0];
                        REG_SESSION_HI: bus_rdata <= session[63:32];
                        REG_CQ_OP: bus_rdata <= cq_op;
                        REG_CQ_STATUS: bus_rdata <= cq_status;
                        REG_CQ_SESSION_LO: bus_rdata <= cq_session[31:0];
                        REG_CQ_SESSION_HI: bus_rdata <= cq_session[63:32];
                        REG_CQ_EPOCH: bus_rdata <= cq_epoch;
                        REG_CQ_SEQUENCE_LO: bus_rdata <= cq_sequence[31:0];
                        REG_CQ_SEQUENCE_HI: bus_rdata <= cq_sequence[63:32];
                        REG_CQ_CONTEXT: bus_rdata <= cq_context;
                        REG_CQ_GENERATION: bus_rdata <= cq_generation;
                        REG_CQ_TOKEN0: bus_rdata <= cq_token0;
                        REG_CQ_TOKEN1: bus_rdata <= cq_token1;
                        REG_BUILT: bus_rdata <= built_tokens;
                        REG_DECODED: bus_rdata <= decode_steps;
                        REG_NEXT_SEQUENCE_LO: bus_rdata <= next_sequence[31:0];
                        REG_NEXT_SEQUENCE_HI: bus_rdata <= next_sequence[63:32];
                        REG_CURRENT_EPOCH: bus_rdata <= epoch;
                        REG_CURRENT_GENERATION: bus_rdata <= generation;
                        REG_CURRENT_CONTEXT: bus_rdata <= object_id;
                        REG_ACCEPTED_LO: bus_rdata <= accepted_count[31:0];
                        REG_ACCEPTED_HI: bus_rdata <= accepted_count[63:32];
                        REG_REJECTED_LO: bus_rdata <= rejected_count[31:0];
                        REG_REJECTED_HI: bus_rdata <= rejected_count[63:32];
                        REG_COMMITTED_LO: bus_rdata <= committed_tasks[31:0];
                        REG_COMMITTED_HI: bus_rdata <= committed_tasks[63:32];
                        REG_CLEAN_BYTES_LO: bus_rdata <= clear_cleaned_bytes[31:0];
                        REG_CLEAN_BYTES_HI: bus_rdata <= clear_cleaned_bytes[63:32];
                        default: access_error <= 32'h80000004;
                    endcase
                end
            end
        end
    end
endmodule
