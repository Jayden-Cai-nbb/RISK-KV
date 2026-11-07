// Observer only. Counts accepted requests of the direct, always-ready memory
// interface; these are simulated logical transfers, not physical DDR measurements.
module rkv_dram_traffic_monitor #(parameter int D=32,SID=0)(
  input logic clk,a_req,a_we,sw_req,b_req,b_we,dump,
  input logic [3:0] a_be,sw_be,
  input logic [D/4-1:0] b_wmask
);
  longint unsigned ar=0,br=0,aw=0,sw=0,bw=0;
  always @(posedge clk) begin
    if(a_req && !a_we) ar<=ar+1;
    if(b_req && !b_we) br<=br+1;
    if(a_req && a_we) aw<=aw+64'($countones(a_be));
    if(sw_req) sw<=sw+64'($countones(sw_be));
    if(b_req && b_we) bw<=bw+4*64'($countones(b_wmask));
    if(dump)$display("RKV_TRAFFIC sid=%0d a_read_bytes=%0d b_read_bytes=%0d write_bytes=%0d",SID,ar*32,br*D,aw+sw+bw);
  end
endmodule
bind otpu_dram rkv_dram_traffic_monitor #(.D(D),.SID(SID)) rkv_traffic(.*);
