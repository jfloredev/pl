// Testbench: No Data Dependency
// Program: 3 ADDIs with nop-gap, then ADD of settled values, then SW.
// Hazard expected: NONE — no forwarding, stall, or flush needed.
// Expected: mem[100] = 25
module tb_nodep;
  reg         clk, reset;
  wire [31:0] WriteData, DataAdr;
  wire        MemWrite;

  top #(.MEM_FILE("test_nodep.mem")) dut(
    .clk(clk), .reset(reset),
    .WriteData(WriteData), .DataAdr(DataAdr), .MemWrite(MemWrite)
  );

  initial clk = 1;
  always #5 clk = ~clk;

  initial begin
    reset = 1; #22; reset = 0;
  end

  // Monitor hazard signals (should all stay 0)
  wire [1:0] ForwardAE = dut.rvsingle.hu.ForwardAE;
  wire [1:0] ForwardBE = dut.rvsingle.hu.ForwardBE;
  wire       StallF    = dut.rvsingle.hu.StallF;
  wire       FlushE    = dut.rvsingle.hu.FlushE;

  always @(negedge clk) begin
    if (ForwardAE !== 2'b00 || ForwardBE !== 2'b00)
      $display("[INFO]  t=%0t  ForwardAE=%b  ForwardBE=%b", $time, ForwardAE, ForwardBE);
    if (StallF)
      $display("[WARN]  t=%0t  Unexpected stall in no-dep test", $time);
    if (FlushE)
      $display("[INFO]  t=%0t  FlushE=1 (pipeline bubble during reset drain)", $time);
  end

  always @(negedge clk) begin
    if (MemWrite) begin
      if (DataAdr === 32'd100 && WriteData === 32'd25) begin
        $display("[PASS]  tb_nodep: mem[100]=%0d  (no hazard path)", WriteData);
        $finish;
      end else begin
        $display("[FAIL]  tb_nodep: addr=%0d  data=%0d", DataAdr, WriteData);
        $finish;
      end
    end
  end

  initial begin #500; $display("[FAIL]  tb_nodep: timeout"); $finish; end
endmodule
