//You may use this software for **personal, research, academic, and other noncommercial purposes** free of charge.  
//Any **commercial use** requires a separate license from QSymbolic LLC.  
//This software is provided **“as is”**, without warranties or conditions of any kind.

module collapse_register_keyexchange (
    input  logic       clk,
    input  logic       reset,
    input  logic       init,            // load fresh entropy/seed
    input  logic       read,            // one-cycle read strobe (sync)
    input  logic [7:0] entropy_in,      // TRNG/QRNG/seed input
    // --- data outputs ---
    output logic [7:0] key_fragment,    // presents value pre-edge; collapses same cycle
    output logic       output_enable,   // pulses during valid sampling edge (logical OE)
    // --- physical disable / tamper hooks ---
    input  logic       fuse_blow,       // external request to blow fuse / hard kill
    output logic       pad_enable,      // PHYSICAL OE to I/O pad; latches LOW permanently after kill/fuse
    output logic       fuse_fire        // 1-cycle pulse at collapse to drive OTP/antifuse/kill circuit
);

  // Internal storage & lifecycle
  logic [7:0] stored_entropy;
  logic       collapsed;     // logical disable (read-once)
  logic       kill_latch;    // physical disable (permanent)
  logic       fuse_blown;    // latched result of fuse request

  // Synthesizable 8-bit LFSR (x^8 + x^6 + x^5 + x^4 + 1) for obfuscation
  logic [7:0] lfsr;
  always_ff @(posedge clk or posedge reset) begin
    if (reset)       lfsr <= 8'hA5; // nonzero seed
    else             lfsr <= {lfsr[6:0], lfsr[7]^lfsr[5]^lfsr[4]^lfsr[3]};
  end

  // Lifecycle latches
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      stored_entropy <= '0;
      collapsed      <= 1'b0;
      kill_latch     <= 1'b0;
      fuse_blown     <= 1'b0;
      fuse_fire      <= 1'b0;
    end else begin
      fuse_fire <= 1'b0; // default deassert single-cycle pulse

      // External fuse request → immediate permanent physical disable
      if (fuse_blow) begin
        fuse_blown <= 1'b1;
        kill_latch <= 1'b1;
      end

      // Load new entropy; clear logical collapse
      // NOTE: For true OTP provisioning, DO NOT clear kill_latch/fuse_blown here.
      if (init && !fuse_blown) begin
        stored_entropy <= entropy_in;
        collapsed      <= 1'b0;
        // kill_latch <= 1'b0; // ← uncomment ONLY if re-arming pad after init is allowed
      end

      // SAME EDGE: irrevocably collapse on first read (if not already killed/fused)
      if (read && !collapsed && !kill_latch && !fuse_blown) begin
        collapsed      <= 1'b1;   // logical disable
        kill_latch     <= 1'b1;   // physical disable (permanent)
        fuse_fire      <= 1'b1;   // pulse to OTP/antifuse / wordline-kill
        // Optional hardening: wipe storage on collapse to defeat remanence
        stored_entropy <= lfsr;
      end
    end
  end

  // Same-cycle output selection:
  // If (read && live) just before the edge, present true value; then collapse/kill on that edge.
  wire live = (!collapsed) && (!kill_latch) && (!fuse_blown);
  always_comb begin
    if (read && live)
      key_fragment = stored_entropy;
    else
      key_fragment = lfsr;   // obfuscated otherwise (idle, post-collapse, or killed)
  end

  // Logical OE: pulse only during valid sampling edge
  assign output_enable = (read && live);

  // PHYSICAL OE to I/O pad: once kill_latch/fuse_blown asserts, stays LOW permanently
  assign pad_enable = output_enable & ~kill_latch & ~fuse_blown;

endmodule
