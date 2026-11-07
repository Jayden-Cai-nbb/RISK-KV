// M1 清理器：真实零写 / 冷模板复制；退休和失效后才发布完成。
// cold_reset 仅接整机冷复位，禁止接 CPU reset 或取消脉冲。
module rkv_m1_cleaner #(
    parameter logic [31:0] TIMEOUT_CYCLES = 32'd1000000
) (
    input logic clk,
    input logic cold_reset,
    input logic start_valid,
    output logic start_ready,
    input logic full_object,
    input logic fabric_idle,
    input logic fabric_error,
    output logic flush_req,
    input logic flush_ack,
    output logic req_valid,
    input logic req_ready,
    output logic req_write,
    output logic [31:0] req_addr,
    output logic [1023:0] req_data,
    output logic [127:0] req_mask,
    input logic rsp_valid,
    output logic rsp_ready,
    input logic rsp_error,
    input logic [1023:0] rsp_data,
    output logic done_valid,
    input logic done_ready,
    output logic isolated,
    output logic [31:0] fault_code,
    output logic [63:0] reads_accepted,
    output logic [63:0] reads_retired,
    output logic [63:0] writes_accepted,
    output logic [63:0] writes_retired,
    output logic [63:0] cleaned_bytes
);
    import rkv_m1_layout_pkg::*;
    typedef enum logic [3:0] {
        IDLE, DRAIN, RANGE, READ_REQ, READ_WAIT, WRITE_REQ,
        WRITE_WAIT, ADVANCE, FLUSH, DONE, QUARANTINE
    } state_t;
    state_t state;
    logic full_saved;
    logic [2:0] range_index;
    logic [31:0] dest_base;
    logic [31:0] source_base;
    logic [31:0] remaining;
    logic [1023:0] copy_data;
    logic [31:0] wait_cycles;
    logic idle_previous;
    wire copy_range = range_index != 3'd0;
    wire request_fire = req_valid && req_ready;
    wire response_fire = rsp_valid && rsp_ready;
    wire waiting = state == DRAIN || state == READ_REQ || state == READ_WAIT ||
                   state == WRITE_REQ || state == WRITE_WAIT || state == FLUSH;
    wire timeout_now = waiting && wait_cycles >= TIMEOUT_CYCLES - 32'd1;

    // 地址、模式和数据只在接受 / 退休后更新，背压期间保持整个负载。
    assign start_ready = state == IDLE && !isolated && !fabric_error;
    assign req_valid = state == READ_REQ || state == WRITE_REQ;
    assign req_write = state == WRITE_REQ;
    assign req_addr = req_write ? dest_base : source_base;
    assign req_data = copy_range ? copy_data : 1024'b0;
    assign req_mask = {128{1'b1}};
    assign rsp_ready = state == READ_WAIT || state == WRITE_WAIT;
    assign flush_req = state == FLUSH && !isolated;
    assign done_valid = state == DONE && !isolated && !fabric_error && !rsp_valid;

    always_ff @(posedge clk) begin
        if (cold_reset) begin
            state <= IDLE;
            full_saved <= 1'b0;
            range_index <= 3'd0;
            dest_base <= 32'd0;
            source_base <= 32'd0;
            remaining <= 32'd0;
            copy_data <= 1024'd0;
            wait_cycles <= 32'd0;
            idle_previous <= 1'b0;
            isolated <= 1'b0;
            fault_code <= 32'd0;
            reads_accepted <= 64'd0;
            reads_retired <= 64'd0;
            writes_accepted <= 64'd0;
            writes_retired <= 64'd0;
            cleaned_bytes <= 64'd0;
        end else begin
            idle_previous <= fabric_idle;
            if (!waiting || request_fire || response_fire) begin
                wait_cycles <= 32'd0;
            end else if (!timeout_now) begin
                wait_cycles <= wait_cycles + 32'd1;
            end

            // 超时不撤回已呈现请求、不清计数；迟到返回仍可退休，但永不解隔离。
            if ((timeout_now && !request_fire && !response_fire) || fabric_error) begin
                isolated <= 1'b1;
                if (!isolated) fault_code <= fabric_error ? 32'd2 : 32'd1;
            end
            if (rsp_valid && !rsp_ready) begin
                isolated <= 1'b1;
                if (!isolated) fault_code <= 32'd3;
            end

            case (state)
                IDLE: begin
                    if (start_valid && start_ready) begin
                        full_saved <= full_object;
                        range_index <= 3'd0;
                        idle_previous <= 1'b0;
                        state <= DRAIN;
                    end
                end
                DRAIN: begin
                    if (isolated || timeout_now || fabric_error) state <= QUARANTINE;
                    else if (fabric_idle && idle_previous) state <= RANGE;
                end
                RANGE: begin
                    if (isolated || fabric_error) state <= QUARANTINE;
                    else if (range_index == 3'd0) begin
                        // 首段完整覆盖对象或两个私有尾部；全为 128-byte 整数块。
                        dest_base <= full_saved ? KV_BASE : KV_BASE + PREFIX_BYTES;
                        remaining <= full_saved ? OBJECT_BYTES : OBJECT_BYTES - PREFIX_BYTES;
                        source_base <= 32'd0;
                        copy_data <= 1024'd0;
                        state <= WRITE_REQ;
                    end else begin
                        dest_base <= scratch_base(range_index - 3'd1);
                        source_base <= scratch_source(range_index - 3'd1);
                        remaining <= scratch_bytes(range_index - 3'd1);
                        state <= READ_REQ;
                    end
                end
                READ_REQ: begin
                    if (request_fire) begin
                        reads_accepted <= reads_accepted + 64'd1;
                        state <= READ_WAIT;
                    end
                end
                READ_WAIT: begin
                    if (response_fire) begin
                        reads_retired <= reads_retired + 64'd1;
                        if (rsp_error || isolated || fabric_error) begin
                            isolated <= 1'b1;
                            if (!isolated) fault_code <= 32'd4;
                            state <= QUARANTINE;
                        end else begin
                            copy_data <= rsp_data;
                            state <= WRITE_REQ;
                        end
                    end
                end
                WRITE_REQ: begin
                    if (request_fire) begin
                        writes_accepted <= writes_accepted + 64'd1;
                        state <= WRITE_WAIT;
                    end
                end
                WRITE_WAIT: begin
                    if (response_fire) begin
                        writes_retired <= writes_retired + 64'd1;
                        if (rsp_error || isolated || fabric_error) begin
                            isolated <= 1'b1;
                            if (!isolated) fault_code <= 32'd4;
                            state <= QUARANTINE;
                        end else begin
                            cleaned_bytes <= cleaned_bytes + 64'd128;
                            state <= ADVANCE;
                        end
                    end
                end
                ADVANCE: begin
                    if (isolated || fabric_error) state <= QUARANTINE;
                    else if (remaining == 32'd128) begin
                        if ({29'd0, range_index} == SCRATCH_RANGES) begin
                            idle_previous <= 1'b0;
                            state <= FLUSH;
                        end else begin
                            range_index <= range_index + 3'd1;
                            state <= RANGE;
                        end
                    end else begin
                        // 地址加 128、长度减 128；布局生成器检查正长度、对齐与 2 GiB 上界。
                        dest_base <= dest_base + 32'd128;
                        source_base <= source_base + 32'd128;
                        remaining <= remaining - 32'd128;
                        state <= copy_range ? READ_REQ : WRITE_REQ;
                    end
                end
                FLUSH: begin
                    if (isolated || timeout_now || fabric_error) state <= QUARANTINE;
                    else if (flush_ack && fabric_idle && idle_previous &&
                             reads_accepted == reads_retired && writes_accepted == writes_retired) state <= DONE;
                end
                DONE: begin
                    if (isolated || fabric_error) state <= QUARANTINE;
                    else if (done_valid && done_ready) state <= IDLE;
                end
                QUARANTINE: state <= QUARANTINE;
                default: begin
                    isolated <= 1'b1;
                    fault_code <= 32'd5;
                    state <= QUARANTINE;
                end
            endcase
        end
    end
endmodule
