// 由configs/m1/host-control.json与layout.json生成；仅组合地址译码，不持有事务。
module rkv_m1_host_map (
    input wire [31:0] address,
    output reg [4:0] register_id,
    output wire mailbox_select,
    output wire [15:0] mailbox_address
);
    assign mailbox_select = address[31:9] == 23'h400080 && address[2:0] == 3'd0;
// 每个8-byte主机别名对应一个4-byte原邮箱字；低两位保持字对齐。
    assign mailbox_address = {8'he0, address[8:3], 2'd0};
    always @* begin
        register_id = 5'd0;
        case (address)
            32'h80000000: register_id = 5'd1; // identity
            32'h80000008: register_id = 5'd2; // status
            32'h80000010: register_id = 5'd3; // boot
            32'h80000018: register_id = 5'd4; // reset
            32'h80000020: register_id = 5'd5; // epoch
            32'h80000028: register_id = 5'd6; // generation
            32'h80000030: register_id = 5'd7; // error
            32'h80000038: register_id = 5'd8; // clock_plan
            32'h80000040: register_id = 5'd9; // support
            32'h80000048: register_id = 5'd10; // experiment_id
            32'h80000050: register_id = 5'd11; // host_verified
            32'h80000058: register_id = 5'd12; // native_verified
            32'h80000060: register_id = 5'd13; // accepted_reads
            32'h80000068: register_id = 5'd14; // accepted_writes
            32'h80000070: register_id = 5'd15; // rejected_requests
            32'h80000078: register_id = 5'd16; // control_requests
            default: register_id = 5'd0;
        endcase
    end
endmodule
