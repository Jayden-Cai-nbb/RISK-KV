// Simulation harness: memories load prog_<s>.hex / dram_<s>.bin from +dir=..., the machine runs
// until every slice halts, then TMEM and DRAM of every slice are dumped for comparison.
// +runs=N: N runs in one simulation, as the host runs a program again (the memory path, sys_rst,
// is not reset between them): after a run halts, the core's reset (AXI = 1: the memory model
// writes the next run's pokeb lines, the host's writes between the runs), +reload: the program
// loaded again, +r<k>_arg<j>=N: run k's arguments (else the run before's), then the next run.
module tb_top;
  parameter int S          = 1;
  parameter int D          = 32;
  parameter int MCOLS      = 8;
  parameter int ACT_BLOCKS = 64;
  parameter int ACT_ROWS   = MCOLS;
  parameter int TMEM_WORDS = 1 << 16;
  parameter int IMEM_WORDS = 1 << 16;
  parameter int DRAM_WORDS = 1 << 18;
  parameter int DRAM_LAT   = 8;
  parameter int LANES      = 8;
  parameter int WIN        = 32;
  parameter int RPB        = 4;
  parameter int WPB        = 2;
  parameter int MXU_IMPL   = 2;
  parameter int MXU_CL     = 16;
  parameter int MXU_E      = 0;       // MXU epilogue lanes (0: MCOLS / 2)
  parameter int QUANT_XD   = 1024;    // quantizer row buffer chunks (0: two passes over TMEM)
  parameter int VPU_CL     = (LANES >= 8) ? LANES / 4 : 1;
  parameter int ULANES     = LANES;
  parameter int AXI        = 0;       // otpu_top's memory path (1: the board's, native; 2: the
                                      // card's channels, LiteDRAM's controller)
  parameter int FIFO_DEPTH = 128;
  parameter int TMEM_IMPL  = 0;       // TMEM: 0 a copy per read port, 1 banked (otpu_slice)
  parameter bit SEQ_WC     = 1'b0;    // EXPERIMENTAL: otpu_seq's wait counts (docs/seq_vpu.md)
  parameter bit TMEM_RQ    = 1'b0;    // TMEM_IMPL 1: request-priority bank addresses
  parameter int TMEM_NCP   = 3;       // TMEM_IMPL 1: copies
  parameter int TMEM_NSB   = 8;       // TMEM_IMPL 3: sub-banks per bank
  parameter int TMEM_SBP   = 3;       // TMEM_IMPL 3: the sub-bank field's word-address bit
  parameter int TMEM_SBH   = 0;       // TMEM_IMPL 3: the sub-bank hashed
  parameter bit TMEM_RPL   = 1'b0;    // TMEM_IMPL 3: lost reads replayed
  parameter bit TMEM_TDP   = 1'b0;    // TMEM_IMPL 3: true dual-port RAMs
  parameter bit TMEM_GST   = 1'b0;    // TMEM_IMPL 3: QUANT 3 and COLL the DMA's guests
  parameter int TMEM_PMP   = 0;       // TMEM_TDP: 2 the pumped RAMs' model
  parameter int TMEM_PRK   = 0;       // TMEM_IMPL 3: the read ports' ranks (otpu_slice)
  parameter int TMEM_SDM   = -1;      // TMEM_TDP: the read ports' RAM sides (otpu_slice)
  parameter bit COLL_GATHER = 1'b1;   // 0: the BAR-only collective unit (otpu_coll_bar) at S = 1,
                                      // as the card builds it (rtlsim.BOARD_UARCH); S > 1 has GATHER

  logic clk=0,clk_f=0,sys_rst=1,rst,dump=0;
  logic ld_start,ld_busy;logic[31:0]ld_addr,ld_n,rinit[8],icount[S];
  logic all_halted,any_error,fabric_idle,program_ready,result_valid;
  logic result_store_valid,result_other_write;logic[31:0]result_store_addr,result_store_mask,result_token0,result_token1;
  logic[1023:0]result_store_data;
  logic cpu_trap,cpu_done,completion_valid,control_active,launch_pulse,token_trace_valid,token_trace_row;
  logic[31:0]cpu_code,completion_status,completion_context,completion_generation,accepted_count,rejected_count,token_trace_data;
  logic[63:0]completion_session,completion_sequence;
  logic completion_previous=0,ready_previous=0,bound_previous=0,ever_sealed=0,fabric_error=0;
  logic[2:0]state_previous=0;logic[8:0]built_previous=0;
  int launches=0,completions=0,decode_completions=0,token_traces=0,loads=0,load_checks=0,seals=0,binds=0,failure=0;
  longint cycles=0,max_cycles=500000000;
  logic[31:0]expected_build[32768],expected_decode[32768];
  string directory;
  import "DPI-C" function void rkv_observe_logits(input int sid,input string directory,input int step,input int address,input int words);
  import "DPI-C" function void rkv_observe_context(input string directory,input string name,input int address,input int bytes);
  initial begin
    if(!$value$plusargs("dir=%s",directory))$fatal(1,"No input directory");
    void'($value$plusargs("failure=%d",failure));
    for(int i=0;i<32768;i++)begin expected_build[i]=0;expected_decode[i]=0;end
    $readmemh($sformatf("%s/expected_build.hex",directory),expected_build);
    $readmemh($sformatf("%s/expected_decode.hex",directory),expected_decode);
  end
  rkv_npu_context_cpu #(.RESULT_ADDR(32'd1229289088)) u_cpu(
    .clk,.reset(sys_rst),.npu_halted(all_halted),.npu_error(any_error),.fabric_idle,.fabric_error,.loader_busy(ld_busy),
    .loader_start(ld_start),.loader_addr(ld_addr),.loader_count(ld_n),.result_store_valid,.result_other_write,
    .result_store_addr,.result_store_data,.result_store_mask,.program_ready,.result_valid,.result_token0,.result_token1,
    .token_trace_valid,.token_trace_row,.token_trace_data,.npu_reset(rst),.npu_args(rinit),.trap(cpu_trap),.test_done(cpu_done),.test_code(cpu_code),
    .completion_valid,.active(control_active),.launch_pulse,.completion_status,.completion_context,.completion_generation,
    .completion_session,.completion_sequence,.accepted_count,.rejected_count);
  always @(posedge clk)if(!sys_rst)begin
    fabric_error<=0;
    if(cpu_trap)$fatal(1,"RISC-V trapped");
    if(ld_start)begin
      if(!rst||control_active||completion_valid)$fatal(1,"Unsafe loader start");
      loads<=loads+1;$display("CTX_LOAD address=%h instructions=%0d cycle=%0d",ld_addr,ld_n,cycles);$fflush();
    end
    if(program_ready&&!ready_previous)begin
      if(!rst||ld_busy||!fabric_idle)$fatal(1,"Early ready");
      for(int i=0;i<int'(ld_n)*8;i++)begin
        if(ld_addr==32'h60000000)begin
          if(dut.g_slice[0].u_slice.u_seq.u_imem.g_auto.mem[i/32][32*(i%32)+:32]!==expected_build[i])$fatal(1,"Build IMEM mismatch");
        end else if(ld_addr==32'h60010000)begin
          if(dut.g_slice[0].u_slice.u_seq.u_imem.g_auto.mem[i/32][32*(i%32)+:32]!==expected_decode[i])$fatal(1,"Decode IMEM mismatch");
        end else $fatal(1,"Unexpected program");
      end
      load_checks<=load_checks+1;$display("CTX_LOAD_CHECK words=%0d cycle=%0d",ld_n*8,cycles);$fflush();
    end
    ready_previous<=program_ready;
    if(launch_pulse)begin
      launches<=launches+1;
      if(failure==2&&ld_addr==32'h60000000)fabric_error<=1;
      $display("CTX_LAUNCH seq=%h session=%h program=%h a0=%h a1=%h a2=%h a3=%h a4=%h a5=%h a6=%h a7=%h cycle=%0d",
        completion_sequence,completion_session,ld_addr,rinit[0],rinit[1],rinit[2],rinit[3],rinit[4],rinit[5],rinit[6],rinit[7],cycles);$fflush();
    end
    if(completion_valid&&!completion_previous)begin
      if(!fabric_idle||ld_busy)$fatal(1,"Completion before retirement");
      completions<=completions+1;
      if(ld_addr==32'h60010000&&completion_status==0)begin
        if(!result_valid)$fatal(1,"No decode result");
        decode_completions<=decode_completions+1;
        rkv_observe_logits(0,directory,decode_completions+1,13312,303872);
      end
      $display("CTX_COMPLETE seq=%h status=%0d program=%h word0=%h word1=%h cycle=%0d instructions=%0d",
        completion_sequence,completion_status,ld_addr,result_token0,result_token1,cycles,icount[0]);$fflush();
    end
    completion_previous<=completion_valid;
    if(u_cpu.control.guard.built_tokens!=built_previous)begin
      if(u_cpu.control.guard.built_tokens!=built_previous+4)$fatal(1,"Non-quantum build commit");
      $display("CTX_BUILD_COMMIT tokens=%0d cycle=%0d",u_cpu.control.guard.built_tokens,cycles);$fflush();
    end
    built_previous<=u_cpu.control.guard.built_tokens;
    if(u_cpu.control.guard.object_state!=state_previous)begin
      $display("CTX_STATE state=%0d built=%0d bound=%0d ref=%0d cycle=%0d",u_cpu.control.guard.object_state,
        u_cpu.control.guard.built_tokens,u_cpu.control.guard.bound_pair,u_cpu.control.guard.task_reference,cycles);$fflush();
      if(u_cpu.control.guard.object_state==2)begin
        if(u_cpu.control.guard.built_tokens!=256||control_active||completion_valid||!fabric_idle)$fatal(1,"Premature seal");
        rkv_observe_context(directory,"prefix-sealed.bin",1233223680,15138816);seals<=seals+1;ever_sealed<=1;
      end
    end
    state_previous<=u_cpu.control.guard.object_state;
    if(u_cpu.control.guard.bound_pair&&!bound_previous)begin
      if(!ever_sealed||control_active||completion_valid)$fatal(1,"Early bind");
      rkv_observe_context(directory,"private-at-bind.bin",1248362496,30277632);binds<=binds+1;
      $display("CTX_BOUND shared_prefix_bytes=15138816 cycle=%0d",cycles);$fflush();
    end
    bound_previous<=u_cpu.control.guard.bound_pair;
    if(token_trace_valid)begin
      if(!result_valid||!completion_valid||ld_addr!=32'h60010000)$fatal(1,"Unowned token");
      token_traces<=token_traces+1;$display("CTX_TOKEN seq=%h row=%0d value=%0d",completion_sequence,token_trace_row,token_trace_data);$fflush();
    end
  end
  otpu_top #(.S(S), .D(D), .MCOLS(MCOLS), .ACT_BLOCKS(ACT_BLOCKS), .ACT_ROWS(ACT_ROWS), .TMEM_WORDS(TMEM_WORDS),
             .IMEM_WORDS(IMEM_WORDS), .DRAM_WORDS(DRAM_WORDS), .DRAM_LAT(DRAM_LAT),
             .LANES(LANES), .WIN(WIN), .RPB(RPB), .WPB(WPB), .MXU_IMPL(MXU_IMPL), .MXU_CL(MXU_CL), .MXU_E(MXU_E), .QUANT_XD(QUANT_XD), .VPU_CL(VPU_CL), .ULANES(ULANES), .AXI(AXI), .FIFO_DEPTH(FIFO_DEPTH),
             .TMEM_IMPL(TMEM_IMPL), .TMEM_RQ(TMEM_RQ), .TMEM_NCP(TMEM_NCP),
             .TMEM_NSB(TMEM_NSB), .TMEM_SBP(TMEM_SBP), .TMEM_SBH(TMEM_SBH),
             .TMEM_RPL(TMEM_RPL), .TMEM_TDP(TMEM_TDP), .TMEM_GST(TMEM_GST),
             .TMEM_PMP(TMEM_PMP), .TMEM_PRK(TMEM_PRK), .TMEM_SDM(TMEM_SDM), .SEQ_WC(SEQ_WC),
             .COLL_GATHER(COLL_GATHER || S > 1)) dut (
    .clk, .clk_f, .sys_rst, .rst, .rinit, .ld_start, .ld_addr, .ld_n, .ld_busy, .all_halted, .any_error,
    .icount,.dump,.fabric_idle,.result_store_valid,.result_other_write,.result_store_addr,.result_store_data,.result_store_mask);
  // TMEM_PMP 1: clk_f (2 x clk) rises with each edge of clk, in clk's own process (no race between
  // the two domains); clk's edges stay where they are (the memory models' clocks are absolute)
  if (TMEM_PMP == 1) begin : g_clkf
    initial forever begin
      #2 clk_f = 1'b0;
      #3 begin clk = ~clk; clk_f = 1'b1; end
    end
  end else begin : g_clk
    always #5 clk = ~clk;
  end

  longint unsigned prefix_written=0,private_written=0,logits_written=0,mailbox_written=0;
  longint unsigned build_weight_reads=0,build_prefix_reads=0,decode_weight_reads=0,decode_prefix_reads=0,other_reads=0;
  task observe_write(input longint unsigned byte_addr,input int count);
    if(byte_addr>=1233223680&&byte_addr<1248362496)begin
      if(ever_sealed||ld_addr!=32'h60000000||!control_active)$fatal(1,"Write to sealed/unowned prefix");prefix_written+=64'(count);
    end else if(byte_addr>=1248362496&&byte_addr<1278640128)begin
      if(!ever_sealed||!u_cpu.control.guard.bound_pair||ld_addr!=32'h60010000||!control_active)$fatal(1,"Unowned private write");private_written+=64'(count);
    end else if(byte_addr>=13312&&byte_addr<1228800)begin
      if(ld_addr!=32'h60010000)$fatal(1,"Build unexpectedly writes logits");logits_written+=64'(count);
    end else if(byte_addr>=1229289088&&byte_addr<1229289096)mailbox_written+=64'(count);
    else $fatal(1,"Write outside allowed output/KV ranges: %h",byte_addr);
  endtask
  task observe_read(input longint unsigned byte_addr,input int count);
    if(byte_addr>=1233223680&&byte_addr<1248362496&&control_active)begin
      if(ld_addr==32'h60000000)build_prefix_reads+=64'(count);else decode_prefix_reads+=64'(count);
    end else if(control_active&&((byte_addr>=9216&&byte_addr<13312)||
                  (byte_addr>=1359872&&byte_addr<1229289088)))begin
      if(ld_addr==32'h60000000)build_weight_reads+=64'(count);else decode_weight_reads+=64'(count);
    end else other_reads+=64'(count);
  endtask
  always @(posedge clk)if(!sys_rst)begin
    if(dut.g_slice[0].a_req&&dut.g_slice[0].a_rdy)begin
      if(dut.g_slice[0].a_we)observe_write(64'(dut.g_slice[0].a_addr)*4,$countones(dut.g_slice[0].a_be));
      else observe_read(64'({dut.g_slice[0].a_addr[31:3],3'b0})*4,32);
    end
    if(dut.g_slice[0].sw_req&&dut.g_slice[0].sw_rdy)observe_write(64'(dut.g_slice[0].sw_addr)*4,$countones(dut.g_slice[0].sw_be));
    if(dut.g_slice[0].b_req&&dut.g_slice[0].b_rdy)begin
      if(dut.g_slice[0].b_we)begin
        for(int w=0;w<D/4;w++)if(dut.g_slice[0].b_wmask[w])observe_write((64'(dut.g_slice[0].b_addr)+64'(w))*4,4);
      end else observe_read(64'(dut.g_slice[0].b_addr)*4,D);
    end
  end
  initial begin
    void'($value$plusargs("max_cycles=%d",max_cycles));
    if(S!=1||AXI!=0)$fatal(1,"Validated context pilot requires S=1 AXI=0");
    repeat(3)@(negedge clk);sys_rst=0;
    while(!cpu_done&&cycles<max_cycles)begin @(negedge clk);cycles++;end
    if(!cpu_done)$fatal(1,"CPU did not finish");
    if(failure==0)begin
      if(cpu_code!=(32'h600d4000|32'(decode_completions))||launches!=64+decode_completions||completions!=launches||
         decode_completions<1||decode_completions>3||token_traces!=2*decode_completions||seals!=1||binds!=1||loads!=3||load_checks!=3)
        $fatal(1,"Lifecycle positive failed code=%h launches=%0d",cpu_code,launches);
    end else if(cpu_code!=(32'h600d3000|32'(failure))||launches!=1||completions!=1||seals!=0||binds!=0||decode_completions!=0)
      $fatal(1,"Negative lifecycle failed code=%h",cpu_code);
    if(control_active||completion_valid||!fabric_idle||ld_busy||!u_cpu.control.guard.reclaimable)$fatal(1,"Unsafe reclaim");
    rkv_observe_context(directory,"prefix-final.bin",1233223680,15138816);
    @(negedge clk);dump=1;@(negedge clk);dump=0;
    $display("CTX_BYTES prefix_written=%0d private_written=%0d logits_written=%0d mailbox_written=%0d build_weight_reads=%0d build_prefix_reads=%0d decode_weight_reads=%0d decode_prefix_reads=%0d other_reads=%0d",
      prefix_written,private_written,logits_written,mailbox_written,build_weight_reads,build_prefix_reads,decode_weight_reads,decode_prefix_reads,other_reads);
    $display("CTX_RESULT failure=%0d code=%h cycles=%0d accepted=%0d rejected=%0d built=%0d decode=%0d seals=%0d binds=%0d safe=1",
      failure,cpu_code,cycles,accepted_count,rejected_count,u_cpu.control.guard.built_tokens,decode_completions,seals,binds);$fflush();$finish;
  end
endmodule
