// Testbench: Control Hazard — Branch Flush
// Program: BEQ x1,x1,+12 (always taken) skips two ADDI x2,x0,0x7FF instructions.
// Hazard unit sets FlushD=FlushE=1 the cycle PCSrcE=1, discarding the two
// wrongly-fetched instructions (turns them into NOPs/bubbles).
// Expected: mem[100] = 25  (x2 not overwritten by the flushed ADDIs)
module tb_flush;
  reg         clk, reset;
  wire [31:0] WriteData, DataAdr;
  wire        MemWrite;

  top #(.MEM_FILE("test_flush.mem")) dut(
    .clk(clk), .reset(reset),
    .WriteData(WriteData), .DataAdr(DataAdr), .MemWrite(MemWrite)
  );

  initial clk = 1;
  always #5 clk = ~clk;

  initial begin
    reset = 1; #22; reset = 0;
  end

  wire PCSrcE = dut.rvsingle.hu.PCSrcE;
  wire FlushD = dut.rvsingle.hu.FlushD;
  wire FlushE = dut.rvsingle.hu.FlushE;

  reg flush_seen;
  initial flush_seen = 0;

  always @(negedge clk) begin
    if (!reset && PCSrcE) begin
      $display("[FLUSH] t=%0t  branch taken: PCSrcE=1  FlushD=%b  FlushE=%b",
               $time, FlushD, FlushE);
      flush_seen = 1;
    end
  end

  always @(negedge clk) begin
    if (MemWrite) begin
      if (DataAdr === 32'd100 && WriteData === 32'd25) begin
        if (flush_seen)
          $display("[PASS]  tb_flush: mem[100]=%0d  and branch flush was observed", WriteData);
        else
          $display("[FAIL]  tb_flush: correct value but flush was NEVER observed");
        $finish;
      end else begin
        $display("[FAIL]  tb_flush: addr=%0d  data=%0d  (flushed instrs may have executed!)",
                 DataAdr, WriteData);
        $finish;
      end
    end
  end

  initial begin #800; $display("[FAIL]  tb_flush: timeout"); $finish; end
endmodule
