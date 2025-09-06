//You may use this software for **personal, research, academic, and other noncommercial purposes** free of charge.  
//Any **commercial use** requires a separate license from QSymbolic LLC.  
//This software is provided **“as is”**, without warranties or conditions of any kind.

module mdi_register (
    input  logic       clk,
    input  logic       reset,
    input  logic       init,
    input  logic       read,            // one-cycle read strobe (sync)
    input  logic [7:0] value_in,
    input  logic [1:0] basis_in,        // prepared basis
    input  logic       allow_read,      // granted by matching unit (combinational)
    // --- data outputs ---
    output logic [7:0] value_out,       // presents true value pre-edge; collapses same cycle
    output logic       collapsed,       // latched on first read attempt
    output logic [1:0] basis_out,       // exposed basis for matcher
    // --- physical disable / tamper hooks ---
    input  logic       fuse_blow,       // external request to hard-disable this register
    output logic       pad_enable,      // PHYSICAL OE to I/O pad; latches LOW permanently after kill/fuse
    output logic       fuse_fire        // 1-cycle pulse at collapse to drive OTP/antifuse/kill circuit
);

  // Internal storage
  logic [7:0] stored_value;
  logic [1:0] stored_basis;

  // Physical/tamper latches
  logic       kill_latch;   // permanent physical disable
  logic       fuse_blown;   // latched fuse state

  // Synthesizable 8-bit LFSR (x^8 + x^6 + x^5 + x^4 + 1) for obfuscation
  logic [7:0] lfsr;
  always_ff @(posedge clk or posedge reset) begin
    if (reset)       lfsr <= 8'hA5;      // nonzero seed
    else             lfsr <= {lfsr[6:0], lfsr[7]^lfsr[5]^lfsr[4]^lfsr[3]};
  end

  // State
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      stored_value <= '0;
      stored_basis <= 2'b00;
      collapsed    <= 1'b0;
      basis_out    <= 2'b00;
      kill_latch   <= 1'b0;
      fuse_blown   <= 1'b0;
      fuse_fire    <= 1'b0;
    end else begin
      fuse_fire <= 1'b0; // default deassert pulse

      // External fuse → immediate permanent physical disable
      if (fuse_blow) begin
        fuse_blown <= 1'b1;
        kill_latch <= 1'b1;
      end

      if (init && !fuse_blown) begin
        stored_value <= value_in;
        stored_basis <= basis_in;
        collapsed    <= 1'b0;
        basis_out    <= basis_in;
        // If you allow re-provisioning to re-arm pads, uncomment:
        // kill_latch <= 1'b0;
      end

      // SAME EDGE: any read attempt consumes the cell (if not already killed/fused)
      if (read && !collapsed && !kill_latch && !fuse_blown) begin
        collapsed    <= 1'b1;     // logical disable
        kill_latch   <= 1'b1;     // physical disable (permanent)
        fuse_fire    <= 1'b1;     // OTP/antifuse/kill trigger
        // Optional: wipe storage on collapse to defeat remanence
        // stored_value <= lfsr;
      end
    end
  end

  // Same-cycle output selection:
  // If (read && allow_read && live) is true just before the edge,
  // present stored_value; on that same edge, collapse/kill asserts.
  wire live = (!collapsed) && (!kill_latch) && (!fuse_blown);
  always_comb begin
    if (read && allow_read && live)
      value_out = stored_value;
    else
      value_out = lfsr; // obfuscated otherwise
  end

  // PHYSICAL OE to I/O pad: once kill_latch/fuse_blown asserts, stays LOW permanently
  assign pad_enable = (read && allow_read && live) & ~kill_latch & ~fuse_blown;

endmodule

// ----------------------------------------------------------------------------
// Matching Unit (Untrusted Relay): grants read only if bases match.
// ----------------------------------------------------------------------------
module mdi_matching_unit (
    input  logic [1:0] basis_a,
    input  logic [1:0] basis_b,
    output logic       grant_read
);
  always_comb begin
    grant_read = (basis_a == basis_b);
  end
endmodule

// ----------------------------------------------------------------------------
// Top: two MDI registers (Alice/Bob) + matching unit, with physical OE exposed.
// ----------------------------------------------------------------------------
module mdi_qkd_top (
    input  logic       clk,
    input  logic       reset,
    input  logic       init,
    input  logic       read,          // one-cycle strobe to both parties
    input  logic [7:0] value_a,
    input  logic [7:0] value_b,
    input  logic [1:0] basis_a,
    input  logic [1:0] basis_b,
    input  logic       fuse_blow_a,   // per-channel fuse controls
    input  logic       fuse_blow_b,
    output logic [7:0] out_a,
    output logic [7:0] out_b,
    output logic       pad_enable_a,  // physical OEs for pads
    output logic       pad_enable_b
);

  logic       grant_read;
  logic [1:0] basis_out_a, basis_out_b;
  logic       collapsed_a, collapsed_b;
  logic       fuse_fire_a, fuse_fire_b; // route to OTP/antifuse if used

  mdi_register alice (
    .clk(clk), .reset(reset), .init(init), .read(read),
    .value_in(value_a), .basis_in(basis_a),
    .allow_read(grant_read),
    .value_out(out_a), .collapsed(collapsed_a), .basis_out(basis_out_a),
    .fuse_blow(fuse_blow_a), .pad_enable(pad_enable_a), .fuse_fire(fuse_fire_a)
  );

  mdi_register bob (
    .clk(clk), .reset(reset), .init(init), .read(read),
    .value_in(value_b), .basis_in(basis_b),
    .allow_read(grant_read),
    .value_out(out_b), .collapsed(collapsed_b), .basis_out(basis_out_b),
    .fuse_blow(fuse_blow_b), .pad_enable(pad_enable_b), .fuse_fire(fuse_fire_b)
  );

  mdi_matching_unit matcher (
    .basis_a(basis_out_a),
    .basis_b(basis_out_b),
    .grant_read(grant_read)
  );

endmodule
