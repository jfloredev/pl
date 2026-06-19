// Testbench: Data Forwarding (EX/MEM and MEM/WB paths)
// Program: back-to-back ALU instructions producing and consuming values
//   immediately — requires ForwardAE=10 (EX/MEM) and ForwardBE=01 (MEM/WB).
// Expected: mem[100] = 25
module tb_forwarding;
  reg         clk, reset;
  wire [31:0] WriteData, DataAdr;
  wire        MemWrite;

  top #(.MEM_FILE("test_forwarding.mem")) dut(
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

  // Log every forwarding event
  always @(negedge clk) begin
    if (!reset) begin
      if (ForwardAE == 2'b10)
        $display("[FWD]   t=%0t  EX/MEM forward -> SrcA", $time);
      if (ForwardAE == 2'b01)
        $display("[FWD]   t=%0t  MEM/WB forward -> SrcA", $time);
      if (ForwardBE == 2'b10)
        $display("[FWD]   t=%0t  EX/MEM forward -> SrcB", $time);
      if (ForwardBE == 2'b01)
        $display("[FWD]   t=%0t  MEM/WB forward -> SrcB", $time);
      if (StallF)
        $display("[WARN]  t=%0t  Unexpected stall", $time);
    end
  end

  always @(negedge clk) begin
    if (MemWrite) begin
      if (DataAdr === 32'd100 && WriteData === 32'd25) begin
        $display("[PASS]  tb_forwarding: mem[100]=%0d  (forwarding correct)", WriteData);
        $finish;
      end else begin
        $display("[FAIL]  tb_forwarding: addr=%0d  data=%0d  (expected addr=100 data=25)",
                 DataAdr, WriteData);
        $finish;
      end
    end
  end

  initial begin #800; $display("[FAIL]  tb_forwarding: timeout"); $finish; end
endmodule
