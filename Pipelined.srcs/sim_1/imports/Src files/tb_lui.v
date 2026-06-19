// Testbench: U-type LUI instruction
// Program:
//   lui  x1, 1       --> x1 = 0x00001000 = 4096
//   lui  x2, 1       --> x2 = 0x00001000 = 4096
//   addi x3, x0, 100 --> x3 = 100
//   add  x4, x1, x2  --> x4 = 8192  (x1 via regfile fwd, x2 via MEM/WB fwd)
//   sw   x4, 0(x3)   --> mem[100] = 8192
//
// Hazard coverage: LUI result forwarded via MEM/WB path (ForwardBE=01)
// Expected: mem[100] = 8192 (0x2000)
module tb_lui;
  reg         clk, reset;
  wire [31:0] WriteData, DataAdr;
  wire        MemWrite;

  top #(.MEM_FILE("test_lui.mem")) dut(
    .clk(clk), .reset(reset),
    .WriteData(WriteData), .DataAdr(DataAdr), .MemWrite(MemWrite)
  );

  initial clk = 1;
  always #5 clk = ~clk;

  initial begin
    reset = 1; #22; reset = 0;
  end

  wire [1:0] ForwardAE = dut.rvsingle.hu.ForwardAE;
  wire [1:0] ForwardBE = dut.rvsingle.hu.ForwardBE;
  wire       StallF    = dut.rvsingle.hu.StallF;

  always @(negedge clk) begin
    if (!reset) begin
      if (ForwardAE !== 2'b00 || ForwardBE !== 2'b00)
        $display("[FWD]   t=%0t  ForwardAE=%b  ForwardBE=%b  (LUI result forwarded)",
                 $time, ForwardAE, ForwardBE);
      if (StallF)
        $display("[WARN]  t=%0t  Unexpected stall — LUI must NOT trigger load-use stall",
                 $time);
    end
  end

  always @(negedge clk) begin
    if (MemWrite) begin
      if (DataAdr === 32'd100 && WriteData === 32'd8192) begin
        $display("[PASS]  tb_lui: mem[100]=%0d (0x%h)  LUI + forwarding correct",
                 WriteData, WriteData);
        $finish;
      end else begin
        $display("[FAIL]  tb_lui: addr=%0d  data=%0d (0x%h)  expected addr=100 data=8192",
                 DataAdr, WriteData, WriteData);
        $finish;
      end
    end
  end

  initial begin #800; $display("[FAIL]  tb_lui: timeout"); $finish; end
endmodule
