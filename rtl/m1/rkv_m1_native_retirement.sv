// 原生 DDR 退休监督：把预取读也计入排空，而非只看 NPU 已请求的数据返回。
// 不清除控制/CPU 复位前的在途计数；n_wdone 是平台真实可见写退休计数。
module rkv_m1_native_retirement (
    input logic clk,
    input logic cold_reset,
    input logic [1:0] cvalid,
    input logic [1:0] cready,
    input logic [1:0] cwe,
    input logic [1:0] wvalid,
    input logic [1:0] wready,
    input logic [1:0] rvalid,
    input logic [1:0][15:0] wdone,
    input logic platform_error,
    output logic idle,
    output logic error,
    output logic [63:0] read_accepted [2],
    output logic [63:0] read_retired [2],
    output logic [63:0] write_accepted [2],
    output logic [63:0] data_accepted [2],
    output logic [63:0] write_retired [2]
);
    logic [1:0][15:0] previous_wdone;
    logic [1:0][15:0] delta;
    logic sticky_error;
    logic violation;
    always_comb begin
        idle = !(|cvalid) && !(|wvalid) && !(|rvalid);
        violation = 1'b0;
        for (int c = 0; c < 2; c++) begin
            // 16-bit 模差保持原生计数合同；平台必须保证每拍新增退休不超过已接受量。
            delta[c] = wdone[c] - previous_wdone[c];
            if (rvalid[c] && read_accepted[c] == read_retired[c]) violation = 1'b1;
            if (64'(delta[c]) > write_accepted[c] - write_retired[c] + 64'(cvalid[c] && cready[c] && cwe[c])) violation = 1'b1;
            if (64'(delta[c]) > data_accepted[c] - write_retired[c] + 64'(wvalid[c] && wready[c])) violation = 1'b1;
            if (read_accepted[c] != read_retired[c] || write_accepted[c] != write_retired[c] ||
                data_accepted[c] != write_retired[c] || delta[c] != 0) idle = 1'b0;
        end
        error = sticky_error || violation || platform_error;
        if (error) idle = 1'b0;
    end
    always_ff @(posedge clk) begin
        if (cold_reset) begin
            previous_wdone <= wdone;
            sticky_error <= 1'b0;
            for (int c = 0; c < 2; c++) begin
                read_accepted[c] <= 64'd0;
                read_retired[c] <= 64'd0;
                write_accepted[c] <= 64'd0;
                data_accepted[c] <= 64'd0;
                write_retired[c] <= 64'd0;
            end
        end else begin
            previous_wdone <= wdone;
            if (violation || platform_error) sticky_error <= 1'b1;
            for (int c = 0; c < 2; c++) begin
                if (cvalid[c] && cready[c]) begin
                    if (cwe[c]) write_accepted[c] <= write_accepted[c] + 64'd1;
                    else read_accepted[c] <= read_accepted[c] + 64'd1;
                end
                if (wvalid[c] && wready[c]) data_accepted[c] <= data_accepted[c] + 64'd1;
                if (rvalid[c]) read_retired[c] <= read_retired[c] + 64'd1;
                write_retired[c] <= write_retired[c] + 64'(delta[c]);
            end
        end
    end
endmodule
