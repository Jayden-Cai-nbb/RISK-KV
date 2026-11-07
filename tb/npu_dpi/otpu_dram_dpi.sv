// Simulation-only byte storage adapter, derived from openTPU otpu_dram.sv
// at 91df41092f612361c5bc22f83b31d23382ffabb0 (Apache-2.0; LICENSE.openTPU).
// The NPU compute RTL is unchanged. Reads sample pre-write data. Writes commit
// on the NBA-triggered toggle, after all posedge readers/dumps have sampled.
module otpu_dram #(
  parameter int WORDS=1<<18, D=32, LAT=8, SID=0
) (
  input logic clk,
  input logic a_req,a_we,
  input logic [31:0] a_addr,a_wdata,
  input logic [3:0] a_be,
  output logic a_rvalid,
  output logic [255:0] a_rdata,
  input logic sw_req,
  input logic [31:0] sw_addr,sw_wdata,
  input logic [3:0] sw_be,
  input logic b_req,b_tag,b_we,
  input logic [D/4-1:0] b_wmask,
  input logic [D*8-1:0] b_wdata,
  input logic [31:0] b_addr,
  output logic b_rvalid,b_rtag,
  output logic [D*8-1:0] b_rdata,
  output logic rd_idle,
  input logic dump
);
`ifdef SYNTHESIS
  RKV_DPI_DRAM_IS_NOT_A_SYNTHESIZABLE_MEMORY illegal_use();
`else
  import "DPI-C" function void rkv_mem_init(input int sid,input longint unsigned words,input string dir);
  import "DPI-C" function int unsigned rkv_mem_read(input int sid,input int unsigned word);
  import "DPI-C" function void rkv_mem_queue(input int sid,input int unsigned word,
                                            input int unsigned value,input int unsigned mask);
  import "DPI-C" function void rkv_mem_commit(input int sid);
  import "DPI-C" function void rkv_mem_dump(input int sid);
  localparam int AW=$clog2(WORDS), CW=D/4, NPOKE=64;
  logic [LAT-1:0] av,bv,bt;
  logic [255:0] ad[LAT];
  logic [D*8-1:0] bd[LAT];
  longint pk_c[NPOKE];
  logic [31:0] pk_a[NPOKE],pk_v[NPOKE];
  int pk_n=0,pk_i=0;
  longint pk_cyc=0;
  bit initialized=0;
  logic commit_toggle;
  string dir;
  integer fd;
  initial begin
    if (LAT<1 || D<32 || D%4 || WORDS<8 || (WORDS & (WORDS-1)))
      $fatal(1,"DPI DRAM requires positive latency, whole words and power-of-two capacity");
    if (!$value$plusargs("dir=%s",dir)) $fatal(1,"DPI DRAM requires +dir");
    rkv_mem_init(SID,64'(WORDS),dir);
    av='0;bv='0;bt='0;commit_toggle=0;initialized=1;
    fd=$fopen($sformatf("%s/poke_%0d.txt",dir,SID),"r");
    if (fd!=0) begin
      while (pk_n<NPOKE && $fscanf(fd,"%h %h %h",pk_c[pk_n],pk_a[pk_n],pk_v[pk_n])==3) pk_n++;
      $fclose(fd);
    end
  end
  always_ff @(posedge clk) begin
    pk_cyc<=pk_cyc+1;
    if (pk_i<pk_n && pk_cyc>=pk_c[pk_i]) begin
      rkv_mem_queue(SID,32'(pk_a[pk_i][AW-1:0]),pk_v[pk_i],15);
      pk_i<=pk_i+1;
    end
    if (a_req && a_we) rkv_mem_queue(SID,32'(a_addr[AW-1:0]),a_wdata,32'(a_be));
    if (sw_req) rkv_mem_queue(SID,32'(sw_addr[AW-1:0]),sw_wdata,32'(sw_be));
    av[0]<=a_req && !a_we;
    for (int w=0;w<8;w++) ad[0][32*w +:32]<=rkv_mem_read(SID,32'({a_addr[AW-1:3],3'(w)}));
    bv[0]<=b_req && !b_we;bt[0]<=b_tag;
    for (int w=0;w<CW;w++) bd[0][32*w +:32]<=rkv_mem_read(SID,32'(AW'(b_addr+w)));
    if (b_req && b_we)
      for (int w=0;w<CW;w++) if (b_wmask[w]) rkv_mem_queue(SID,32'(AW'(b_addr+w)),b_wdata[32*w +:32],15);
    for (int k=1;k<LAT;k++) begin
      av[k]<=av[k-1];ad[k]<=ad[k-1];bv[k]<=bv[k-1];bt[k]<=bt[k-1];bd[k]<=bd[k-1];
    end
    commit_toggle<=~commit_toggle;
  end
  always @(commit_toggle) if (initialized) rkv_mem_commit(SID);
  always @(posedge clk) if (dump) rkv_mem_dump(SID);
  assign a_rvalid=av[LAT-1];assign a_rdata=ad[LAT-1];
  assign b_rvalid=bv[LAT-1];assign b_rtag=bt[LAT-1];assign b_rdata=bd[LAT-1];
  assign rd_idle=!(|av) && !(|bv);
`endif
endmodule
