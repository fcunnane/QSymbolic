//You may use this software for **personal, research, academic, and other noncommercial purposes** free of charge.  
//Any **commercial use** requires a separate license from QSymbolic LLC.  
//This software is provided **“as is”**, without warranties or conditions of any kind.

module qkd_collapse_register (
    input  logic       clk,
    input  logic       reset,
    input  logic       init,            // load fresh value + basis
    input  logic       read,            // one-cycle read strobe (sync)
    input  logic [1:0] basis_in,        // reader's basis guess
    // --- data outputs ---
    output logic [7:0] value_out,       // presents value pre-edge; collapses same cycle
    output logic       output_enable,   // pulses during valid sampling edge (logical OE)
    // --- physical disable / tamper hooks ---
    input  logic       fuse_blow,       // external request to blow fuse / hard kill
    output logic       pad_enable,      // PHYSICAL OE to I/O pad; latches LOW permanently after kill/fuse
    output logic       fuse_fire        // 1-cycle pulse at collapse to drive OTP/antifuse/kill circuit
);

  // Internal storage & metadata
  logic [7:0] stored_value;  // entropy-derived secret
  logic [1:0] basis;         // symbolic basis tag

  // Lifecycle & tamper
  logic       collapsed;     // logical disable (read-once)
  logic       kill_latch;    // physical disable (permanent)
  logic       fuse_blown;    // latched result of fuse request

  // Synthesizable 8-bit LFSR (x^8 + x^6 + x^5 + x^4 + 1) for obfuscation/entropy
    // In production you would use an entropy source of your choosing
  logic [7:0] lfsr;
  always_ff @(posedge clk or posedge reset) begin
    if (reset)       lfsr <= 8'hA5; // nonzero seed
    else             lfsr <= {lfsr[6:0], lfsr[7]^lfsr[5]^lfsr[4]^lfsr[3]};
  end

  // Lifecycle & initialization
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      stored_value <= '0;
      basis        <= 2'b00;
      collapsed    <= 1'b0;
      kill_latch   <= 1'b0;
      fuse_blown   <= 1'b0;
      fuse_fire    <= 1'b0;
    end else begin
      fuse_fire <= 1'b0; // default deassert single-cycle pulse

      // External fuse request → immediate permanent physical disable
      if (fuse_blow) begin
        fuse_blown <= 1'b1;
        kill_latch <= 1'b1;
      end

      // Load a fresh value and randomized basis; clear logical collapse
      // NOTE: For true OTP provisioning, DO NOT clear kill_latch/fuse_blown here.
      if (init && !fuse_blown) begin
        stored_value <= lfsr;        // or drive from TRNG/QRNG
        basis        <= lfsr[1:0];   // randomized basis tag
        collapsed    <= 1'b0;
        // kill_latch <= 1'b0; // ← uncomment ONLY if re-arming pad after init is allowed
      end

      // SAME EDGE: irrevocably collapse AND physically kill on any live read
      if (read && !collapsed && !kill_latch && !fuse_blown) begin
        collapsed    <= 1'b1;   // logical disable
        kill_latch   <= 1'b1;   // physical disable (permanent)
        fuse_fire    <= 1'b1;   // pulse to OTP/antifuse / wordline-kill
        // Optional hardening: wipe internal value at collapse to defeat remanence
        stored_value <= lfsr;
      end
    end
  end

  // Authorization: QKD-style basis check + first-use + not killed/fused
  wire basis_ok   = (basis_in == basis);
  wire authorized = (!collapsed) & basis_ok & (!kill_latch) & (!fuse_blown);

  // Same-cycle output selection:
  // If (read && authorized) is true just before the edge, present stored_value for capture;
  // on that SAME edge, collapse/kill latch and path immediately reverts to LFSR.
  always_comb begin
    if (read && authorized)
      value_out = stored_value;
    else
      value_out = lfsr;   // obfuscated otherwise
  end

  // Logical OE: pulse only during valid sampling edge
  assign output_enable = (read && authorized);

  // PHYSICAL OE to I/O pad: once kill_latch/fuse_blown asserts, stays LOW permanently
  assign pad_enable = output_enable & ~kill_latch & ~fuse_blown;

endmodule
