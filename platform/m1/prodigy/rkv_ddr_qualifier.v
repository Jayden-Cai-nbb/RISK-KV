// 独立DDR验收批次：整范围分阶段写读，单在途；不接NPU或主机数据写入。
module rkv_ddr_qualifier #(
    parameter [31:0] TIMEOUT_CYCLES = 32'd192000000,
    parameter [31:0] CYCLES_PER_SECOND = 32'd192000000
) (
    input wire clk,
    input wire cold_reset,
    input wire calibrated,
    input wire start,
    input wire [31:0] base_address,
    input wire [25:0] block_count,
    input wire [31:0] seed,
    input wire [15:0] min_seconds,
    input wire peek_toggle,
    input wire [31:0] peek_address,
    output reg peek_ack,
    output wire busy,
    output reg done,
    output wire fault,
    output reg [3:0] fault_code,
    output reg [3:0] phase,
    output reg [2:0] pass,
    output reg [31:0] rounds,
    output reg [25:0] block_index,
    output reg [31:0] elapsed,
    output reg [47:0] cycles,
    output reg [31:0] seconds,
    output reg [511:0] expected_data,
    output reg [511:0] observed_data,
    output reg [47:0] aw_count,
    output reg [47:0] w_count,
    output reg [47:0] b_count,
    output reg [47:0] ar_count,
    output reg [47:0] r_count,
    output reg [32:0] axi_awaddr,
    output reg axi_awvalid,
    input wire axi_awready,
    output reg [511:0] axi_wdata,
    output reg [63:0] axi_wstrb,
    output reg axi_wvalid,
    input wire axi_wready,
    input wire [3:0] axi_bid,
    input wire [1:0] axi_bresp,
    input wire axi_bvalid,
    output wire axi_bready,
    output wire [32:0] axi_araddr,
    output reg axi_arvalid,
    input wire axi_arready,
    input wire [3:0] axi_rid,
    input wire [1:0] axi_rresp,
    input wire [511:0] axi_rdata,
    input wire axi_rlast,
    input wire axi_rvalid,
    output wire axi_rready
);
    localparam [3:0] IDLE=4'd0, PREPARE=4'd1, WRITE=4'd2, READ=4'd3;
    localparam [3:0] COMPARE=4'd4, ADVANCE=4'd5, FINISHED=4'd6;
    reg [31:0] saved_base;
    reg [25:0] saved_blocks;
    reg [31:0] saved_seed;
    reg [15:0] saved_seconds;
    reg [31:0] second_cycles;
    reg peeking;
    reg peek_pending;
    reg read_seen;
    reg [3:0] failure_now;
    wire [32:0] range_end = {1'b0,base_address} + {1'b0,block_count,6'd0};
    wire active = (phase != IDLE) && (phase != FINISHED);
    wire [31:0] current_address = saved_base + {block_index,6'd0};
    integer lane;

    // xorshift只用32位无符号移位；可复现扰动而非密码随机数。
    function [31:0] mix32;
        input [31:0] value;
        reg [31:0] x;
        begin
            x = value ^ (value << 13);
            x = x ^ (x >> 17);
            mix32 = x ^ (x << 5);
        end
    endfunction
    function [511:0] pattern;
        input [31:0] address_value;
        input [31:0] seed_value;
        input [31:0] round_value;
        input random_mode;
        integer word_no;
        reg [31:0] value;
        begin
            for (word_no=0;word_no<16;word_no=word_no+1) begin
                // 低32位模运算，字0保留地址身份；轮号从0开始。
                value = address_value ^ seed_value ^ round_value ^ (32'h9e3779b9 * word_no[31:0]);
                pattern[word_no*32 +: 32] = random_mode ? mix32(value) : value;
            end
        end
    endfunction
    wire [511:0] linear_pattern = pattern(current_address,saved_seed,rounds,1'b0);
    wire [511:0] random_pattern = pattern(current_address,saved_seed,rounds,1'b1);
    // 两类交错mask随轮号翻转，覆盖全部64个字节通道；0为保留旧字节。
    wire [63:0] byte_mask = rounds[0] ? 64'h5555555555555555 : 64'haaaaaaaaaaaaaaaa;
    assign busy = active;
    assign fault = (fault_code != 4'd0);
    assign axi_araddr = axi_awaddr;
    assign axi_bready = (phase == WRITE) && !axi_awvalid && !axi_wvalid;
    assign axi_rready = (phase == READ) && !axi_arvalid;

    // 控制错误先于数值比较；一旦锁存首错，迟到响应仅退休，不能制造成功。
    always @* begin
        failure_now = 4'd0;
        if ((active || done) && !calibrated) failure_now=4'd2;
        else if ((phase==WRITE || phase==READ) && elapsed>=TIMEOUT_CYCLES-32'd1) failure_now=4'd3;
        else if (axi_bvalid && axi_bready && (axi_bid!=4'd0 || axi_bresp!=2'b00)) failure_now=4'd4;
        else if (axi_rvalid && axi_rready && (axi_rid!=4'd0 || axi_rresp!=2'b00 || !axi_rlast || read_seen)) failure_now=4'd5;
        else if (phase==COMPARE && !peeking && observed_data!=expected_data) failure_now=4'd6;
        // 无请求的返回不能留到下一笔被错误消费；有效返回早到可等待READY。
        else if (axi_bvalid && phase!=WRITE) failure_now=4'd8;
        else if (axi_rvalid && phase!=READ) failure_now=4'd8;
    end

    always @(posedge clk) begin
        if (cold_reset) begin
            phase<=IDLE; pass<=3'd0; rounds<=32'd0; block_index<=26'd0;
            done<=1'b0; fault_code<=4'd0; elapsed<=32'd0;
            cycles<=48'd0; seconds<=32'd0; second_cycles<=32'd0;
            saved_base<=32'd0; saved_blocks<=26'd0; saved_seed<=32'd0; saved_seconds<=16'd0;
            expected_data<=512'd0; observed_data<=512'd0;
            axi_awaddr<=33'd0; axi_awvalid<=1'b0; axi_wdata<=512'd0; axi_wstrb<=64'd0;
            axi_wvalid<=1'b0; axi_arvalid<=1'b0;
            aw_count<=48'd0; w_count<=48'd0; b_count<=48'd0; ar_count<=48'd0; r_count<=48'd0;
            peek_ack<=1'b0; peek_pending<=1'b0; peeking<=1'b0; read_seen<=1'b0;
        end else begin
            if (active && !peeking && !fault) begin
                if (cycles!=48'hffffffffffff) cycles<=cycles+48'd1;
                if (second_cycles==CYCLES_PER_SECOND-32'd1) begin
                    second_cycles<=32'd0;
                    if (seconds!=32'hffffffff) seconds<=seconds+32'd1;
                end else second_cycles<=second_cycles+32'd1;
            end
            if ((phase==WRITE || phase==READ) && elapsed!=32'hffffffff) elapsed<=elapsed+32'd1;
            if (!fault && failure_now!=4'd0) begin fault_code<=failure_now; done<=1'b0; end
            // 故障不撤销已展示的VALID。只有整链复位会重置接口；配置guard阻止再次启动。
            if (axi_awvalid && axi_awready) begin axi_awvalid<=1'b0; if (aw_count!=48'hffffffffffff) aw_count<=aw_count+48'd1; end
            if (axi_wvalid && axi_wready) begin axi_wvalid<=1'b0; if (w_count!=48'hffffffffffff) w_count<=w_count+48'd1; end
            if (axi_arvalid && axi_arready) begin axi_arvalid<=1'b0; if (ar_count!=48'hffffffffffff) ar_count<=ar_count+48'd1; end
            case (phase)
                IDLE: if (start && !fault && failure_now==4'd0) begin
                    if (!calibrated || base_address[5:0]!=6'd0 || block_count==26'd0 || range_end>33'h080000000 || min_seconds>16'd3600) begin
                        fault_code<=4'd1; phase<=FINISHED;
                    end else begin
                        saved_base<=base_address; saved_blocks<=block_count;
                        saved_seed<=seed; saved_seconds<=min_seconds;
                        peek_ack<=peek_toggle; phase<=PREPARE;
                    end
                end
                PREPARE: begin
                    if (fault || failure_now!=4'd0) phase<=FINISHED;
                    else begin
                        axi_awaddr<={1'b0,current_address}; elapsed<=32'd0; read_seen<=1'b0;
                        if (pass==3'd4 || pass==3'd5) expected_data<=random_pattern;
                        else if (pass==3'd3) begin
                            for (lane=0;lane<64;lane=lane+1)
                                expected_data[lane*8 +: 8]<=byte_mask[lane] ? ~linear_pattern[lane*8 +: 8] : linear_pattern[lane*8 +: 8];
                        end else expected_data<=linear_pattern;
                        if (!pass[0]) begin
                            axi_wdata<=pass==3'd4 ? random_pattern : (pass==3'd2 ? ~linear_pattern : linear_pattern);
                            axi_wstrb<=pass==3'd2 ? byte_mask : 64'hffffffffffffffff;
                            axi_awvalid<=1'b1; axi_wvalid<=1'b1; phase<=WRITE;
                        end else begin axi_arvalid<=1'b1; phase<=READ; end
                    end
                end
                WRITE: if (axi_bvalid && axi_bready) begin
                    if (b_count!=48'hffffffffffff) b_count<=b_count+48'd1;
                    phase<=(fault || failure_now!=4'd0) ? FINISHED : ADVANCE;
                end
                READ: if (axi_rvalid && axi_rready) begin
                    if (r_count!=48'hffffffffffff) r_count<=r_count+48'd1;
                    if (!read_seen) observed_data<=axi_rdata;
                    read_seen<=1'b1;
                    if (axi_rlast) phase<=(fault || failure_now!=4'd0) ? FINISHED : COMPARE;
                end
                COMPARE: begin
                    if (fault || failure_now!=4'd0) phase<=FINISHED;
                    else if (peeking) begin peek_ack<=peek_pending; peeking<=1'b0; phase<=FINISHED; end
                    else phase<=ADVANCE;
                end
                ADVANCE: begin
                    if (fault || failure_now!=4'd0) phase<=FINISHED;
                    else if (block_index==saved_blocks-26'd1) begin
                        block_index<=26'd0;
                        if (pass==3'd5) begin
                            rounds<=rounds+32'd1;
                            if (seconds>={16'd0,saved_seconds}) begin done<=1'b1; phase<=FINISHED; end
                            else begin pass<=3'd0; phase<=PREPARE; end
                        end else begin pass<=pass+3'd1; phase<=PREPARE; end
                    end else begin block_index<=block_index+26'd1; phase<=PREPARE; end
                end
                FINISHED: begin
                    // 成功后的抽查只有读请求；接收toggle沿固定地址，ACK在完整R被捕获后一拍更新。
                    if (done && !fault && failure_now==4'd0 && peek_toggle!=peek_ack) begin
                        if (!calibrated || peek_address[31] || peek_address[5:0]!=6'd0) begin fault_code<=4'd9; done<=1'b0; end
                        else begin
                            axi_awaddr<={1'b0,peek_address}; axi_arvalid<=1'b1;
                            peeking<=1'b1; peek_pending<=peek_toggle; elapsed<=32'd0; read_seen<=1'b0; phase<=READ;
                        end
                    end
                end
                default: begin fault_code<=4'd10; done<=1'b0; phase<=FINISHED; end
            endcase
        end
    end
endmodule
