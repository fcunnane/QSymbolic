// ============================================================================
// ATOMIC MEMORY™ / ROOM collapse_register_symbolic
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
// Current collapse semantics (symbolic / basis-gated byte-wide cell):
//
//  * INIT:
//      - When 'init' is asserted and the fuse is not blown, the cell:
//          • loads 'value_in' into 'stored_value'
//          • samples a fresh 2-bit basis from LFSR into 'basis_metadata'
//          • clears 'collapsed' (logical live state)
//        kill_latch/fuse_blown are *not* cleared, so a fused device
//        cannot be re-armed by init.
//
//  * FIRST READ (measurement-like collapse):
//      - On the first clock edge where 'read' is high and the cell is
//        not yet collapsed and not fuse_blown, the module:
//          • sets 'collapsed'  = 1 (logical no-more-secrets)
//          • sets 'kill_latch' = 1 (physical pad kill, permanent)
//          • pulses 'fuse_fire' for one cycle
//          • overwrites 'stored_value' with LFSR output (destroy secret)
//      - This happens regardless of basis_match: ANY read is a
//        "measurement" that collapses the internal state.
//
//  * OUTPUT SEMANTICS (same cycle as first read):
//      - Just before the sampling edge, combinational logic decides:
//          • If read && !collapsed && basis_match && !fuse_blown && !kill_latch:
//                value_out = stored_value   (true secret, one time only)
//            else:
//                value_out = lfsr           (obfuscation)
//      - Because 'collapsed' and 'kill_latch' update on the *edge*, the
//        very first qualified read with matching basis returns the true
//        value once; wrong-basis reads still cause collapse but never
//        reveal the secret.
//
//  * SUBSEQUENT READS (post-collapse / killed):
//      - After collapse or kill, all reads emit only obfuscation
//        (LFSR output). 'output_enable' deasserts, and 'pad_enable'
//        remains permanently LOW once kill_latch/fuse_blown are set.
//
//  * TAMPER BEHAVIOR:
//      - 'fuse_blow' latches 'fuse_blown' and 'kill_latch', permanently
//        disabling the pad and preventing re-arming.
//      - 'battery_drop' immediately replaces 'stored_value' with LFSR
//        output, destroying any residual secret on power-loss events.
// ============================================================================

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
    // --- physical disable hooks ---
    output logic       pad_enable,      // Wire to IO pad OE; latches low permanently after collapse/fuse
    output logic       fuse_fire        // 1-cycle internal pulse at collapse to drive OTP/antifuse (optional)
);

  // --------------------------------------------------------------------------
  // Internal state
  // --------------------------------------------------------------------------
  logic [7:0] stored_value;
  logic [1:0] basis_metadata;
  logic       collapsed;    // logical collapse flag
  logic       fuse_blown;   // latched result of fuse request
  logic       kill_latch;   // physical disable latch (permanent)

  // --------------------------------------------------------------------------
  // Synthesizable 8-bit LFSR (x^8 + x^6 + x^5 + x^4 + 1) for obfuscation
  // In production silicon, this would typically be mixed with or replaced by
  // a true entropy source (RO-based TRNG, collapse jitter, etc.).
  // --------------------------------------------------------------------------
  logic [7:0] lfsr;

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      lfsr <= 8'hA5; // nonzero seed
    end else begin
      lfsr <= {lfsr[6:0], lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3]};
    end
  end

  // --------------------------------------------------------------------------
  // State and tamper latches
  // --------------------------------------------------------------------------
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      stored_value   <= '0;
      basis_metadata <= 2'b00;
      collapsed      <= 1'b0;
      fuse_blown     <= 1'b0;
      kill_latch     <= 1'b0;
      fuse_fire      <= 1'b0;
    end else begin
      // default: deassert single-cycle fuse_fire pulse
      fuse_fire <= 1'b0;

      // External tamper requests take priority
      if (fuse_blow) begin
        fuse_blown  <= 1'b1;
        kill_latch  <= 1'b1;   // physically disable immediately on fuse
      end

      if (battery_drop) begin
        // On power-loss tamper, destroy any residual secret
        stored_value <= lfsr;
      end

      // Initialization: load value and fresh basis; clear logical collapse
      // NOTE: fuse_blown is NOT cleared; fused parts cannot be re-armed.
      if (init && !fuse_blown) begin
        stored_value   <= value_in;
        basis_metadata <= lfsr[1:0]; // simple randomized basis (or drive externally)
        collapsed      <= 1'b0;
        // kill_latch stays as-is unless you explicitly allow re-provisioning
        // to re-arm hardware OE:
        // kill_latch <= 1'b0;
      end

      // FIRST read: irrevocably collapse AND physically kill on the SAME edge.
      // Any read is a "measurement" that destroys the secret; basis determines
      // whether the true value is seen during that one cycle.
      if (read && !collapsed && !fuse_blown) begin
        collapsed    <= 1'b1;   // logical disable (read-once)
        kill_latch   <= 1'b1;   // physical disable (permanent)
        fuse_fire    <= 1'b1;   // pulse to OTP/antifuse or wordline-kill (optional)
        stored_value <= lfsr;   // overwrite storage to defeat remanence
      end
    end
  end

  // Basis match (combinational)
  wire basis_match = (read_basis == basis_metadata);

  // --------------------------------------------------------------------------
  // Same-cycle output selection:
  //  - If read && !collapsed && basis_match && !fuse_blown && !kill_latch:
  //        output true stored_value (one time only).
  //  - Otherwise (wrong basis, post-collapse, fused, or killed):
  //        output obfuscation (LFSR).
  // --------------------------------------------------------------------------
  always_comb begin
    if (read && !collapsed && basis_match && !fuse_blown && !kill_latch)
      value_out = stored_value;
    else
      value_out = lfsr; // obfuscated output otherwise
  end

  // Logical OE: pulses only on the valid sampling edge while live and basis-matched
  assign output_enable = (read && !collapsed && basis_match && !fuse_blown && !kill_latch);

  // PHYSICAL OE to I/O pad:
  // once kill_latch or fuse_blown asserts, pad_enable stays LOW forever.
  assign pad_enable = output_enable & ~kill_latch & ~fuse_blown;

endmodule
