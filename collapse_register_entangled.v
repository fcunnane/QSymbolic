//You may use this software for **personal, research, academic, and other noncommercial purposes** free of charge.  
//Any **commercial use** requires a separate license from QSymbolic LLC.  
//This software is provided **“as is”**, without warranties or conditions of any kind.

module collapse_register_entangled (
    input  logic       clk,
    input  logic       reset,
    input  logic       init,             // load value when permitted
    input  logic       read,             // one-cycle read strobe (sync)
    input  logic [7:0] value_in,
    input  logic       peer_collapsed,   // from entangled partner or OR-tree
    // --- physical disable / tamper ---
    input  logic       fuse_blow,        // external request to blow fuse / hard kill
    // --- data & controls ---
    output logic [7:0] value_out,        // collapses same cycle as read
    output logic       output_enable,    // pulses only on valid sampling edge (logical OE)
    output logic       self_collapsed,   // to peer / shared collapse line
    output logic       pad_enable,       // PHYSICAL OE to I/O pad; latches LOW permanently after kill/fuse
    output logic       fuse_fire         // 1-cycle pulse at collapse to drive OTP/antifuse/kill circuit
);

  // Internal storage & lifecycle
  logic [7:0] stored_value;
  logic       collapsed;     // logical disable
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
      stored_value   <= '0;
      collapsed      <= 1'b0;
      self_collapsed <= 1'b0;
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

      // Propagate peer collapse immediately (no read required)
      if (peer_collapsed && !collapsed) begin
        collapsed      <= 1'b1;
        self_collapsed <= 1'b1;   // assert to keep OR-tree latched
        kill_latch     <= 1'b1;   // physical kill on peer collapse
        // Optional hardening: wipe on external collapse as well
        // stored_value <= lfsr;
      end

      // Initialization permitted only if both ends are uncollapsed and not killed/fused
      if (init && !collapsed && !peer_collapsed && !kill_latch && !fuse_blown) begin
        stored_value   <= value_in;
        collapsed      <= 1'b0;
        self_collapsed <= 1'b0;
      end

      // SAME EDGE: any read attempt consumes the cell (valid or invalid) if not already collapsed/killed/fused
      if (read && !collapsed && !kill_latch && !fuse_blown) begin
        collapsed      <= 1'b1;   // logical disable
        self_collapsed <= 1'b1;   // propagate collapse to peers
        kill_latch     <= 1'b1;   // physical disable (permanent)
        fuse_fire      <= 1'b1;   // pulse to OTP/antifuse / wordline-kill
        // Optional hardening: wipe storage at collapse
        stored_value   <= lfsr;
      end
    end
  end

  // Authorization: both sides must be live at the sampling edge
  wire valid_read = (!collapsed) && (!peer_collapsed) && (!kill_latch) && (!fuse_blown);

  // Same-cycle output select:
  //  - Immediately before the sampling edge, if (read && valid_read) is true,
  //    present stored_value for capture. On that SAME edge, collapse/kill latch.
  always_comb begin
    if (read && valid_read)
      value_out = stored_value;
    else
      value_out = lfsr; // obfuscated otherwise
  end

  // Logical OE: pulses only for a valid sampling edge
  assign output_enable = (read && valid_read);

  // PHYSICAL OE to I/O pad: once kill_latch/fuse_blown asserts, stays LOW permanently
  assign pad_enable = output_enable & ~kill_latch & ~fuse_blown;

endmodule
