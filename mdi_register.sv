// ============================================================================
// ATOMIC MEMORY™ / ROOM – MDI-QKD-Inspired Collapse Register
// ----------------------------------------------------------------------------
// QSymbolic Non-Commercial Research License (summary)
//
// - Free for personal, academic, and research use.
// - Any commercial use (products, services, silicon, cloud, etc.) requires
//   a separate written license from QSymbolic LLC.
// - Covered by U.S. Patent Pending: US 19/286,600.
// - See LICENSE in this repository for full terms.
// - Provided "AS IS", without warranty of any kind.
// ----------------------------------------------------------------------------
// Current collapse semantics (MDI-QKD adaptation):
//
//  * INIT:
//      - 'init' loads value_in + basis_in into the live register.
//      - Logical collapse is cleared.
//      - Physical kill (kill_latch/fuse_blown) is *not* cleared,
//        so fused/killed devices cannot be re-armed.
//
//  * FIRST READ ATTEMPT (any read = measurement → collapse):
//      - On the first rising edge where read && live:
//            collapsed  <= 1
//            kill_latch <= 1
//            fuse_fire  <= 1-cycle pulse
//      - This happens *regardless* of whether allow_read == 1.
//
//  * OUTPUT SEMANTICS (same cycle):
//      - If allow_read && read && live just before the edge:
//            value_out = stored_value (true value, once)
//        else:
//            value_out = lfsr (obfuscation)
//
//      - Wrong-basis or disallowed reads:
//            → never reveal the value
//            → *still collapse the cell*
//            → all future reads produce obfuscation
//
//  * AFTER COLLAPSE:
//      - No further true outputs.
//      - pad_enable permanently LOW.
//      - Optionally wipe the stored_value on collapse.
//
//  * EXTERNAL FUSE:
//      - fuse_blow → immediate permanent kill_latch=1 + fuse_blown=1.
// ============================================================================

module mdi_register (
    input  logic       clk,
    input  logic       reset,
    input  logic       init,
    input  logic       read,            // one-cycle read strobe (sync)
    input  logic [7:0] value_in,
    input  logic [1:0] basis_in,        // prepared basis
    input  logic       allow_read,      // granted by matching unit (combinational)
    // --- data outputs ---
    output logic [7:0] value_out,       // true value only on first allowed read
    output logic       collapsed,       // logical read-once flag
    output logic [1:0] basis_out,       // basis exposed to matcher
    // --- physical disable / tamper ---
    input  logic       fuse_blow,
    output logic       pad_enable,      // hardware OE: permanently killed after collapse/fuse
    output logic       fuse_fire        // 1-cycle pulse to OTP/antifuse/kill circuit
);

  // --------------------------------------------------------------------------
  // Internal state
  // --------------------------------------------------------------------------
  logic [7:0] stored_value;
  logic [1:0] stored_basis;

  logic       kill_latch;   // physical permanent disable
  logic       fuse_blown;   // latched fuse signal

  // --------------------------------------------------------------------------
  // LFSR for obfuscation (same polynomial as other ROOM registers)
  // --------------------------------------------------------------------------
  logic [7:0] lfsr;

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      lfsr <= 8'hA5;
    end else begin
      lfsr <= {lfsr[6:0], lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3]};
    end
  end

  // --------------------------------------------------------------------------
  // Lifecycle logic
  // --------------------------------------------------------------------------
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      stored_value <= '0;
      stored_basis <= 2'b00;
      basis_out    <= 2'b00;
      collapsed    <= 1'b0;
      kill_latch   <= 1'b0;
      fuse_blown   <= 1'b0;
      fuse_fire    <= 1'b0;
    end else begin
      fuse_fire <= 1'b0; // default

      // External fuse → immediate kill
      if (fuse_blow) begin
        fuse_blown <= 1'b1;
        kill_latch <= 1'b1;
      end

      // Initialization (but cannot undo a fuse)
      if (init && !fuse_blown) begin
        stored_value <= value_in;
        stored_basis <= basis_in;
        basis_out    <= basis_in;
        collapsed    <= 1'b0;
        // kill_latch stays unless re-arming is allowed:
        // kill_latch <= 1'b0;
      end

      // FIRST READ ATTEMPT collapses state (regardless of allow_read)
      if (read && !collapsed && !kill_latch && !fuse_blown) begin
        collapsed  <= 1'b1;
        kill_latch <= 1'b1;
        fuse_fire  <= 1'b1;

        // Optional: secretly wipe internal value on collapse
        // stored_value <= lfsr;
      end
    end
  end

  // --------------------------------------------------------------------------
  // Same-cycle output logic
  // First allowed read returns the true value; all other reads return noise.
  // --------------------------------------------------------------------------
  wire live = (!collapsed) && (!kill_latch) && (!fuse_blown);

  always_comb begin
    if (read && allow_read && live)
      value_out = stored_value;   // true BB84-style measurement
    else
      value_out = lfsr;           // noise, decoys, or post-collapse garbage
  end

  // --------------------------------------------------------------------------
  // pad_enable mirrors logical OE but becomes permanently LOW post-collapse
  // --------------------------------------------------------------------------
  assign pad_enable = (read && allow_read && live) & ~kill_latch & ~fuse_blown;

endmodule


// ============================================================================
// MDI-QKD Matching Unit
// ----------------------------------------------------------------------------
// Untrusted relay: grants read ONLY if bases match.
// Does not learn the secret.
// ============================================================================
module mdi_matching_unit (
    input  logic [1:0] basis_a,
    input  logic [1:0] basis_b,
    output logic       grant_read
);
  always_comb begin
    grant_read = (basis_a == basis_b);
  end
endmodule


// ============================================================================
// MDI-QKD Top: Alice + Bob registers + Matching unit
// ----------------------------------------------------------------------------
// Both sides attempt read on same strobe.
// grant_read determines whether either side sees the true value.
// Any read attempt → collapse for both.
// ============================================================================
module mdi_qkd_top (
    input  logic       clk,
    input  logic       reset,
    input  logic       init,
    input  logic       read,
    input  logic [7:0] value_a,
    input  logic [7:0] value_b,
    input  logic [1:0] basis_a,
    input  logic [1:0] basis_b,
    input  logic       fuse_blow_a,
    input  logic       fuse_blow_b,
    output logic [7:0] out_a,
    output logic [7:0] out_b,
    output logic       pad_enable_a,
    output logic       pad_enable_b
);

  logic       grant_read;
  logic [1:0] basis_out_a, basis_out_b;
  logic       collapsed_a, collapsed_b;
  logic       fuse_fire_a, fuse_fire_b;

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
