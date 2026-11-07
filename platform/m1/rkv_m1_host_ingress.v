// 根互连前的主机责任记录：每方向一笔，资格在最早地址接收沿锁存。
// root可缓存地址/响应；只有最终主机消费B/最后R才释放。普通CPU复位不接。
module rkv_m1_host_ingress #(
    parameter [31:0] TIMEOUT_CYCLES = 32'd1000000
) (
    input wire clk,
    input wire cold_reset,
    input wire read_grant,
    input wire write_grant,
    output wire memory_idle,
    output wire memory_accept_now,
    output wire saved_read_grant,
    output wire saved_write_grant,
    output reg fault,
    output reg [31:0] fault_code,
    output wire [1:0] memory_outstanding,
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
    reg rd_active;
    reg wr_active;
    reg rd_ddr;
    reg wr_ddr;
    reg rd_permission;
    reg wr_permission;
    reg [3:0] rd_id;
    reg [3:0] wr_id;
    reg [7:0] rd_left;
    reg [7:0] wr_left;
    reg wr_data_done;
    reg [31:0] rd_wait;
    reg [31:0] wr_wait;
    wire ar_fire = s_arvalid && s_arready;
    wire aw_fire = s_awvalid && s_awready;
    wire w_fire = s_wvalid && s_wready;
    wire r_fire = s_rvalid && s_rready;
    wire b_fire = s_bvalid && s_bready;
    wire rd_timeout = rd_active && rd_ddr && !m_rvalid && rd_wait >= TIMEOUT_CYCLES - 32'd1;
    wire wr_timeout = wr_active && wr_ddr && wr_data_done && !m_bvalid && wr_wait >= TIMEOUT_CYCLES - 32'd1;
    wire response_error = (m_rvalid && (!rd_active || m_rid != rd_id || m_rlast != (rd_left == 8'd0))) ||
        (m_bvalid && (!wr_active || m_bid != wr_id || !wr_data_done));
    wire data_error = w_fire && s_wlast != (wr_left == 8'd0);
    // idle只反映先前已接收责任；accept_now另给CPU准入，权限采样不可依赖accept_now。
    assign memory_idle = !fault && !(rd_active && rd_ddr) && !(wr_active && wr_ddr);
    assign memory_accept_now = (ar_fire && !s_araddr[31]) || (aw_fire && !s_awaddr[31]);
    assign memory_outstanding = {1'b0, rd_active && rd_ddr} + {1'b0, wr_active && wr_ddr};
    assign saved_read_grant = rd_active && rd_ddr && rd_permission && !fault;
    assign saved_write_grant = wr_active && wr_ddr && wr_permission && !fault;
    // 不用实时阶段资格门控VALID；地址一旦呈现，保持到root接收。
    assign m_arvalid = !cold_reset && !rd_active && s_arvalid;
    assign s_arready = !cold_reset && !rd_active && m_arready;
    assign m_awvalid = !cold_reset && !wr_active && s_awvalid;
    assign s_awready = !cold_reset && !wr_active && m_awready;
    // AW后才接W，按AWLEN计数；W先呈现可以等待，不要求主机先等WREADY才发AW。
    assign m_wvalid = !cold_reset && wr_active && !wr_data_done && s_wvalid;
    assign s_wready = !cold_reset && wr_active && !wr_data_done && m_wready;
    assign s_rvalid = !cold_reset && m_rvalid;
    assign m_rready = !cold_reset && s_rready;
    assign s_bvalid = !cold_reset && m_bvalid;
    assign m_bready = !cold_reset && s_bready;
    assign m_awid = s_awid;
    assign m_awaddr = s_awaddr;
    assign m_awlen = s_awlen;
    assign m_awsize = s_awsize;
    assign m_awburst = s_awburst;
    assign m_awlock = s_awlock;
    assign m_awcache = s_awcache;
    assign m_awprot = s_awprot;
    assign m_awqos = s_awqos;
    assign m_wdata = s_wdata;
    assign m_wstrb = s_wstrb;
    assign m_wlast = s_wlast;
    assign s_bid = m_bid;
    assign s_bresp = m_bresp;
    assign m_arid = s_arid;
    assign m_araddr = s_araddr;
    assign m_arlen = s_arlen;
    assign m_arsize = s_arsize;
    assign m_arburst = s_arburst;
    assign m_arlock = s_arlock;
    assign m_arcache = s_arcache;
    assign m_arprot = s_arprot;
    assign m_arqos = s_arqos;
    assign s_rid = m_rid;
    assign s_rdata = m_rdata;
    assign s_rresp = m_rresp;
    assign s_rlast = m_rlast;

    always @(posedge clk) begin
        if (cold_reset) begin
            rd_active <= 1'b0;
            wr_active <= 1'b0;
            rd_ddr <= 1'b0;
            wr_ddr <= 1'b0;
            rd_permission <= 1'b0;
            wr_permission <= 1'b0;
            rd_id <= 4'd0;
            wr_id <= 4'd0;
            rd_left <= 8'd0;
            wr_left <= 8'd0;
            wr_data_done <= 1'b0;
            rd_wait <= 32'd0;
            wr_wait <= 32'd0;
            fault <= 1'b0;
            fault_code <= 32'd0;
        end else begin
            // 首因只记一次；没有响应时不清active，不合成完成，不自动重开。
            if (!fault) begin
                if (response_error || data_error) begin fault <= 1'b1; fault_code <= 32'd1; end
                else if (rd_timeout) begin fault <= 1'b1; fault_code <= 32'd2; end
                else if (wr_timeout) begin fault <= 1'b1; fault_code <= 32'd3; end
            end
            if (ar_fire) begin
                rd_active <= 1'b1;
                rd_ddr <= !s_araddr[31];
                rd_permission <= read_grant;
                rd_id <= s_arid;
                rd_left <= s_arlen;
                rd_wait <= 32'd0;
            end else if (r_fire) begin
                if (m_rlast) rd_active <= 1'b0;
                if (rd_left != 8'd0) rd_left <= rd_left - 8'd1;
                rd_wait <= 32'd0;
            end else if (rd_active && rd_ddr && !m_rvalid && !fault && !rd_timeout)
                rd_wait <= rd_wait + 32'd1;
            if (aw_fire) begin
                wr_active <= 1'b1;
                wr_ddr <= !s_awaddr[31];
                wr_permission <= write_grant;
                wr_id <= s_awid;
                wr_left <= s_awlen;
                wr_data_done <= 1'b0;
                wr_wait <= 32'd0;
            end else begin
                if (w_fire) begin
                    if (wr_left == 8'd0) wr_data_done <= 1'b1;
                    else wr_left <= wr_left - 8'd1;
                end
                if (b_fire) begin wr_active <= 1'b0; wr_wait <= 32'd0; end
                else if (wr_active && wr_ddr && wr_data_done && !m_bvalid && !fault && !wr_timeout)
                    wr_wait <= wr_wait + 32'd1;
            end
        end
    end
endmodule
