//You may use this software for **personal, research, academic, and other noncommercial purposes** free of charge.  
//Any **commercial use** requires a separate license from QSymbolic LLC.  
//This software is provided **“as is”**, without warranties or conditions of any kind.

module collapse_register_symbolic (
    input  logic       clk,
    input  logic       reset,
    input  logic       init,            // Initialize ambiguous value
    input  logic       read,            // One-cycle read strobe (sync)
    input  logic [7:0] value_in,        // Initialization value
    input  logic [1:0] read_basis,      // Reader-supplied basis
    output logic [7:0] value_out,       // Collapses same cycle
    output logic       output_enable,   // Pulses on sampling edge
    input  logic       fuse_blow,       // Tamper: one-time fuse request (external)
    input  logic       battery_drop,    // Tamper: power loss
    // --- added for physical disable ---
    output logic       pad_enable,      // Wire to IO pad OE; latches low permanently after collapse/fuse
    output logic       fuse_fire        // 1-cycle internal pulse at collapse to drive OTP/antifuse (optional)
);

  // Internal state
  logic [7:0] stored_value;
  logic [1:0] basis_metadata;
  logic       collapsed;    // logical collapse
  logic       fuse_blown;   // latched result of fuse
  logic       kill_latch;   // physical disable latch (permanent)

  // Synthesizable 8-bit LFSR (x^8 + x^6 + x^5 + x^4 + 1)
  logic [7:0] lfsr;
  always_ff @(posedge clk or posedge reset) begin
    if (reset)       lfsr <= 8'hA5; // nonzero seed
    else             lfsr <= {lfsr[6:0], lfsr[7]^lfsr[5]^lfsr[4]^lfsr[3]};
  end

  // State and tamper latches
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      stored_value   <= '0;
      basis_metadata <= 2'b00;
      collapsed      <= 1'b0;
      fuse_blown     <= 1'b0;
      kill_latch     <= 1'b0;
      fuse_fire      <= 1'b0;
    end else begin
      // defaults
      fuse_fire <= 1'b0;

      // External tamper requests take priority
      if (fuse_blow) begin
        fuse_blown  <= 1'b1;
        kill_latch  <= 1'b1;   // physically disable immediately on fuse
      end
      if (battery_drop) begin
        stored_value <= lfsr;  // immediate obfuscation on power loss
      end

      // Initialization: load value and fresh basis; clear logical collapse
      // (Option: do NOT clear kill_latch/fuse_blown if provisioning must be one-time)
      if (init && !fuse_blown) begin
        stored_value   <= value_in;
        basis_metadata <= lfsr[1:0]; // simple randomized basis (or drive externally)
        collapsed      <= 1'b0;
        // kill_latch stays as-is unless you allow re-provisioning to re-arm pads:
        // kill_latch <= 1'b0; // uncomment ONLY if re-arming hardware OE after re-init is allowed
      end

      // FIRST valid read: irrevocably collapse AND physically kill on the SAME edge
      if (read && !collapsed && !fuse_blown) begin
        collapsed  <= 1'b1;    // logical disable
        kill_latch <= 1'b1;    // physical disable (permanent)
        fuse_fire  <= 1'b1;    // pulse to OTP/antifuse or wordline-kill (optional)
        // Optional: overwrite storage on collapse to defeat remanence
        stored_value <= lfsr;
      end
    end
  end

  // Basis match (combinational)
  wire basis_match = (read_basis == basis_metadata);

  // Same-cycle output selection:
  // If (read && !collapsed && basis_match && !fuse_blown) is true just before the sampling edge,
  // present stored_value for capture; otherwise present obfuscation.
  always_comb begin
    if (read && !collapsed && basis_match && !fuse_blown && !kill_latch)
      value_out = stored_value;
    else
      value_out = lfsr; // obfuscated output otherwise
  end

  // Logical OE: pulses only on the valid sampling edge
  assign output_enable = (read && !collapsed && basis_match && !fuse_blown && !kill_latch);

  // PHYSICAL OE to I/O pad: once kill_latch=1 or fuse_blown=1, it stays LOW forever
  assign pad_enable = output_enable & ~kill_latch & ~fuse_blown;

endmodule
