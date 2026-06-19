// Testbench: Load-Use Hazard (1-cycle stall)
// Program: SW to mem[0]=25, then LW from mem[0] into x4, then ADD x5=x4+x1.
// The ADD immediately follows the LW — hazard unit must stall IF+ID for 1 cycle
// and insert a bubble into EX (FlushE=1) so x4 is ready from WB forwarding.
// Expected: mem[100] = 25
module tb_stall;
  reg         clk, reset;
  wire [31:0] WriteData, DataAdr;
  wire        MemWrite;

  top #(.MEM_FILE("test_stall.mem")) dut(
    .clk(clk), .reset(reset),
    .WriteData(WriteData), .DataAdr(DataAdr), .MemWrite(MemWrite)
  );

  initial clk = 1;
  always #5 clk = ~clk;

  initial begin
    reset = 1; #22; reset = 0;
  end

  wire       StallF  = dut.rvsingle.hu.StallF;
  wire       StallD  = dut.rvsingle.hu.StallD;
  wire       FlushE  = dut.rvsingle.hu.FlushE;
  wire       IsLoadE = dut.rvsingle.hu.IsLoadE;
  wire       lwStall = dut.rvsingle.hu.lwStall;

  reg stall_seen;
  initial stall_seen = 0;

  always @(negedge clk) begin
    if (!reset) begin
      if (lwStall) begin
        $display("[STALL] t=%0t  load-use hazard detected: StallF=%b StallD=%b FlushE=%b",
                 $time, StallF, StallD, FlushE);
        stall_seen = 1;
      end
    end
  end

  always @(negedge clk) begin
    if (MemWrite) begin
      if (DataAdr === 32'd0 && WriteData === 32'd25) begin
        $display("[INFO]  tb_stall: intermediate SW to mem[0]=25 OK");
      end else if (DataAdr === 32'd100 && WriteData === 32'd25) begin
        if (stall_seen)
          $display("[PASS]  tb_stall: mem[100]=%0d  and load-use stall was observed", WriteData);
        else
          $display("[FAIL]  tb_stall: correct value but stall was NEVER observed");
        $finish;
      end else begin
        $display("[FAIL]  tb_stall: addr=%0d  data=%0d", DataAdr, WriteData);
        $finish;
      end
    end
  end

  initial begin #800; $display("[FAIL]  tb_stall: timeout"); $finish; end
endmodule
