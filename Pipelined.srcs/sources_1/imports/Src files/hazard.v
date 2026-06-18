module hazard(
  input  [4:0] Rs1D, Rs2D,
  input  [4:0] Rs1E, Rs2E, RdE,
  input  [4:0] RdM, RdW,
  input        RegWriteM, RegWriteW,
  input        ResultSrcE0,
  input        PCSrcE,
  output reg [1:0] ForwardAE, ForwardBE,
  output StallF, StallD, FlushD, FlushE
);

  wire lwStall;

  // EX/MEM forwarding has priority over MEM/WB forwarding
  always @(*) begin
    if      (RegWriteM && RdM != 0 && RdM == Rs1E) ForwardAE = 2'b10;
    else if (RegWriteW && RdW != 0 && RdW == Rs1E) ForwardAE = 2'b01;
    else                                             ForwardAE = 2'b00;
  end

  always @(*) begin
    if      (RegWriteM && RdM != 0 && RdM == Rs2E) ForwardBE = 2'b10;
    else if (RegWriteW && RdW != 0 && RdW == Rs2E) ForwardBE = 2'b01;
    else                                             ForwardBE = 2'b00;
  end

  // Load-use hazard: stall one cycle and insert bubble in EX
  assign lwStall = ResultSrcE0 && (RdE == Rs1D || RdE == Rs2D);

  assign StallF = lwStall;
  assign StallD = lwStall;
  assign FlushD = PCSrcE;
  assign FlushE = lwStall | PCSrcE;

endmodule
