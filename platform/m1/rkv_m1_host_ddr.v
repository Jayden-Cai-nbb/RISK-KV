// 主机DDR访问阶段入口；只支持64-bit对齐、INCR、非独占burst，地址限定2GiB。
// 请求资格在地址接受沿锁存；普通CPU/NPU复位不清在途，写B成功后仍须逐字节读回。
module rkv_m1_host_ddr #(
    parameter [31:0] TIMEOUT_CYCLES = 32'd1000000
) (
    input wire clk,
    input wire cold_reset,
    input wire external_fault,
    input wire read_grant,
    input wire write_grant,
    output wire host_idle,
    output reg fault,
    output reg [31:0] fault_code,
    output reg [63:0] accepted_reads,
    output reg [63:0] accepted_writes,
    output reg [63:0] rejected_requests,
    output reg [63:0] verified_write_beats,
    input wire [3:0] s_awid,
    input wire [31:0] s_awaddr,
    input wire [7:0] s_awlen,
    input wire [2:0] s_awsize,
    input wire [1:0] s_awburst,
    input wire s_awlock,
    input wire [3:0] s_awcache,
    input wire [2:0] s_awprot,
    input wire [3:0] s_awqos,
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
    input wire [3:0] s_arcache,
    input wire [2:0] s_arprot,
    input wire [3:0] s_arqos,
    input wire s_arvalid,
    output wire s_arready,
    output wire [3:0] s_rid,
    output wire [63:0] s_rdata,
    output wire [1:0] s_rresp,
    output wire s_rlast,
    output wire s_rvalid,
    input wire s_rready,
    output wire [3:0] m_awid,
    output wire [31:0] m_awaddr,
    output wire [7:0] m_awlen,
    output wire [2:0] m_awsize,
    output wire [1:0] m_awburst,
    output wire m_awlock,
    output wire [3:0] m_awcache,
    output wire [2:0] m_awprot,
    output wire [3:0] m_awqos,
    output wire m_awvalid,
    input wire m_awready,
    output wire [63:0] m_wdata,
    output wire [7:0] m_wstrb,
    output wire m_wlast,
    output wire m_wvalid,
    input wire m_wready,
    input wire [3:0] m_bid,
    input wire [1:0] m_bresp,
    input wire m_bvalid,
    output wire m_bready,
    output wire [3:0] m_arid,
    output wire [31:0] m_araddr,
    output wire [7:0] m_arlen,
    output wire [2:0] m_arsize,
    output wire [1:0] m_arburst,
    output wire m_arlock,
    output wire [3:0] m_arcache,
    output wire [2:0] m_arprot,
    output wire [3:0] m_arqos,
    output wire m_arvalid,
    input wire m_arready,
    input wire [3:0] m_rid,
    input wire [63:0] m_rdata,
    input wire [1:0] m_rresp,
    input wire m_rlast,
    input wire m_rvalid,
    output wire m_rready
);
    localparam [3:0] IDLE = 4'd0;
    localparam [3:0] WRITE = 4'd1;
    localparam [3:0] WAIT_B = 4'd2;
    localparam [3:0] VERIFY_AR = 4'd3;
    localparam [3:0] VERIFY_R = 4'd4;
    localparam [3:0] RESP_B = 4'd5;
    localparam [3:0] READ_AR = 4'd6;
    localparam [3:0] READ_R = 4'd7;
    localparam [3:0] REJECT_W = 4'd8;
    localparam [3:0] REJECT_R = 4'd9;
    reg [3:0] state;
    reg [3:0] request_id;
    reg [31:0] request_addr;
    reg [7:0] request_len;
    reg [3:0] request_cache;
    reg [2:0] request_prot;
    reg [3:0] request_qos;
    reg [7:0] write_index;
    reg [7:0] read_index;
    reg address_done;
    reg data_done;
    reg [1:0] write_response;
    reg read_valid;
    reg [63:0] read_data;
    reg [1:0] read_response;
    reg read_last;
    reg [31:0] wait_cycles;
    reg [31:0] fault_event;
    reg mismatch;
    integer byte_index;
    // 最多256个beat，只在接收写数据时写入；核验前整笔已覆盖，不清RAM初值。
    reg [63:0] expected_data [0:255];
    reg [7:0] expected_mask [0:255];

    function bad_request;
        input [31:0] address;
        input [7:0] length;
        input [2:0] size;
        input [1:0] burst;
        input locked;
        reg [32:0] bytes;
        reg [32:0] last_address;
        begin
            // 扩到33位后加一再乘8，256-beat不能在8位计数中回绕。
            bytes = ({25'd0, length} + 33'd1) << 3;
            last_address = {1'b0, address} + bytes - 33'd1;
            bad_request = size != 3'd3 || burst != 2'b01 || locked ||
                address[2:0] != 3'd0 || last_address > 33'h07fffffff ||
                ({21'd0, address[11:0]} + bytes > 33'd4096);
        end
    endfunction

    wire write_accept = s_awvalid && s_awready;
    wire read_accept = s_arvalid && s_arready;
    wire write_beat = s_wvalid && s_wready;
    wire memory_read_beat = m_rvalid && m_rready;
    wire memory_write_response = m_bvalid && m_bready;
    wire memory_wait = ((state == WRITE) &&
        ((m_awvalid && !m_awready) || (m_wvalid && !m_wready))) ||
        (state == WAIT_B && !m_bvalid) ||
        ((state == VERIFY_AR || state == READ_AR) && !m_arready) ||
        (state == VERIFY_R && !m_rvalid) ||
        (state == READ_R && !read_valid && !m_rvalid);
    wire timeout_event = memory_wait && wait_cycles >= TIMEOUT_CYCLES - 32'd1;
    wire failed_now = fault || fault_event != 32'd0;

    // host_idle只看已接受责任；未获grant的VALID不构成组合环。
    // 拒绝请求也要完成合法AXI错误响应，隔离后idle永久为0直到可信cold。
    assign host_idle = state == IDLE && !fault && !external_fault;
    assign s_awready = host_idle && !cold_reset && !m_bvalid && !m_rvalid;
    assign s_arready = s_awready && !s_awvalid;
    assign m_awvalid = state == WRITE && !address_done;
    assign m_awid = request_id;
    assign m_awaddr = request_addr;
    assign m_awlen = request_len;
    assign m_awsize = 3'd3;
    assign m_awburst = 2'b01;
    assign m_awlock = 1'b0;
    assign m_awcache = request_cache;
    assign m_awprot = request_prot;
    assign m_awqos = request_qos;
    // 已接地址的W义务持续到约定beat数；错误源WLAST记录隔离，下游仍收到合法长度。
    assign m_wvalid = state == WRITE && !data_done && s_wvalid;
    assign m_wdata = s_wdata;
    assign m_wstrb = s_wstrb;
    assign m_wlast = write_index == request_len;
    assign s_wready = (state == WRITE && !data_done && m_wready) || state == REJECT_W;
    assign m_bready = state == WAIT_B || (fault && state == IDLE);
    assign s_bvalid = state == RESP_B;
    assign s_bid = request_id;
    assign s_bresp = write_response;
    // 写后核验复用AR通道，资格覆盖整笔事务，不重新查看瞬时read_grant。
    assign m_arvalid = state == VERIFY_AR || state == READ_AR;
    assign m_arid = request_id;
    assign m_araddr = request_addr;
    assign m_arlen = request_len;
    assign m_arsize = 3'd3;
    assign m_arburst = 2'b01;
    assign m_arlock = 1'b0;
    assign m_arcache = request_cache;
    assign m_arprot = request_prot;
    assign m_arqos = request_qos;
    assign m_rready = state == VERIFY_R || (state == READ_R && !read_valid) ||
        (fault && state == IDLE);
    assign s_rvalid = read_valid;
    assign s_rid = request_id;
    assign s_rdata = read_data;
    assign s_rresp = read_response;
    assign s_rlast = read_last;

    // 原样检查每个有效字节，不用读改写冒充byte-enable。
    always @* begin
        mismatch = 1'b0;
        for (byte_index = 0; byte_index < 8; byte_index = byte_index + 1) begin
            if (expected_mask[read_index][byte_index] &&
                m_rdata[byte_index*8 +: 8] != expected_data[read_index][byte_index*8 +: 8])
                mismatch = 1'b1;
        end
        fault_event = 32'd0;
        if (external_fault) fault_event = 32'd7;
        // 无对应下游读/写响应责任时立即隔离，不能把旧返回留给之后的核验。
        else if ((m_rvalid && state != READ_R && state != VERIFY_R) ||
                 (m_bvalid && state != WAIT_B)) fault_event = 32'd9;
        else if ((state == WRITE || state == REJECT_W) && write_beat &&
                 s_wlast != (write_index == request_len)) fault_event = 32'd4;
        else if (state == WAIT_B && memory_write_response && m_bid != request_id) fault_event = 32'd3;
        else if (state == WAIT_B && memory_write_response && m_bresp != 2'b00) fault_event = 32'd1;
        else if ((state == VERIFY_R || state == READ_R) && memory_read_beat && m_rid != request_id) fault_event = 32'd3;
        else if ((state == VERIFY_R || state == READ_R) && memory_read_beat &&
                 m_rlast != (read_index == request_len)) fault_event = 32'd4;
        else if ((state == VERIFY_R || state == READ_R) && memory_read_beat && m_rresp != 2'b00) fault_event = 32'd2;
        else if (state == VERIFY_R && memory_read_beat && mismatch) fault_event = 32'd8;
        else if (timeout_event) fault_event = 32'd5;
    end

    // 故障首因与等待计数独立持有；下游失联不合成成功B/R或伪造空闲。
    // 主机自身的W/R/B停顿不算DDR超时，但仍保持事务占有，不能提前释放。
    always @(posedge clk) begin
        if (cold_reset) begin
            fault <= 1'b0;
            fault_code <= 32'd0;
            wait_cycles <= 32'd0;
        end else begin
            if (!fault && fault_event != 32'd0) begin
                fault <= 1'b1;
                fault_code <= fault_event;
            end
            if (!memory_wait) wait_cycles <= 32'd0;
            else if (wait_cycles != 32'hffffffff) wait_cycles <= wait_cycles + 32'd1;
        end
    end

    always @(posedge clk) begin
        if (cold_reset) begin
            state <= IDLE;
            request_id <= 4'd0;
            request_addr <= 32'd0;
            request_len <= 8'd0;
            request_cache <= 4'd0;
            request_prot <= 3'd0;
            request_qos <= 4'd0;
            write_index <= 8'd0;
            read_index <= 8'd0;
            address_done <= 1'b0;
            data_done <= 1'b0;
            write_response <= 2'b00;
            read_valid <= 1'b0;
            read_data <= 64'd0;
            read_response <= 2'b00;
            read_last <= 1'b0;
            accepted_reads <= 64'd0;
            accepted_writes <= 64'd0;
            rejected_requests <= 64'd0;
            verified_write_beats <= 64'd0;
        end else begin
            case (state)
                IDLE: begin
                    if (write_accept) begin
                        request_id <= s_awid;
                        request_addr <= s_awaddr;
                        request_len <= s_awlen;
                        request_cache <= s_awcache;
                        request_prot <= s_awprot;
                        request_qos <= s_awqos;
                        write_index <= 8'd0;
                        read_index <= 8'd0;
                        address_done <= 1'b0;
                        data_done <= 1'b0;
                        accepted_writes <= accepted_writes + 64'd1;
                        if (!write_grant || bad_request(s_awaddr,s_awlen,s_awsize,s_awburst,s_awlock)) begin
                            rejected_requests <= rejected_requests + 64'd1;
                            state <= REJECT_W;
                        end else state <= WRITE;
                    end else if (read_accept) begin
                        request_id <= s_arid;
                        request_addr <= s_araddr;
                        request_len <= s_arlen;
                        request_cache <= s_arcache;
                        request_prot <= s_arprot;
                        request_qos <= s_arqos;
                        read_index <= 8'd0;
                        accepted_reads <= accepted_reads + 64'd1;
                        if (!read_grant || bad_request(s_araddr,s_arlen,s_arsize,s_arburst,s_arlock)) begin
                            rejected_requests <= rejected_requests + 64'd1;
                            state <= REJECT_R;
                        end else state <= READ_AR;
                    end
                end
                WRITE: begin
                    if (m_awvalid && m_awready) address_done <= 1'b1;
                    if (write_beat) begin
                        expected_data[write_index] <= s_wdata;
                        expected_mask[write_index] <= s_wstrb;
                        if (write_index == request_len) data_done <= 1'b1;
                        else write_index <= write_index + 8'd1;
                    end
                    if ((address_done || (m_awvalid && m_awready)) &&
                        (data_done || (write_beat && write_index == request_len))) state <= WAIT_B;
                end
                WAIT_B: begin
                    if (memory_write_response) begin
                        if (failed_now) begin write_response <= 2'b10; state <= RESP_B; end
                        else state <= VERIFY_AR;
                    end
                end
                VERIFY_AR: if (m_arready) state <= VERIFY_R;
                VERIFY_R: begin
                    if (memory_read_beat) begin
                        if (read_index == request_len) begin
                            write_response <= failed_now ? 2'b10 : 2'b00;
                            if (!failed_now) verified_write_beats <= verified_write_beats + {56'd0, request_len} + 64'd1;
                            state <= RESP_B;
                        end else read_index <= read_index + 8'd1;
                    end
                end
                RESP_B: if (s_bready) state <= IDLE;
                READ_AR: if (m_arready) state <= READ_R;
                READ_R: begin
                    if (memory_read_beat) begin
                        read_valid <= 1'b1;
                        read_data <= m_rdata;
                        read_response <= failed_now ? 2'b10 : 2'b00;
                        read_last <= read_index == request_len;
                        if (read_index != request_len) read_index <= read_index + 8'd1;
                    end
                    if (read_valid && s_rready) begin
                        read_valid <= 1'b0;
                        if (read_last) state <= IDLE;
                    end
                end
                REJECT_W: begin
                    if (write_beat) begin
                        if (write_index == request_len) begin
                            write_response <= 2'b11;
                            state <= RESP_B;
                        end else write_index <= write_index + 8'd1;
                    end
                end
                REJECT_R: begin
                    if (!read_valid) begin
                        read_valid <= 1'b1;
                        read_data <= 64'd0;
                        read_response <= 2'b11;
                        read_last <= read_index == request_len;
                    end
                    if (read_valid && s_rready) begin
                        read_valid <= 1'b0;
                        if (read_last) state <= IDLE;
                        else read_index <= read_index + 8'd1;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
