// ============================================================================
// ATOMIC MEMORY™ / ROOM – BB84-Style Collapse Register
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
// Current collapse semantics (BB84 adaptation):
//
//  * INIT:
//      - On init && not fused:
//           stored_value <= new secret (from TRNG/LFSR)
//           basis        <= new 2-bit random basis tag
//           collapsed    <= 0
//        kill_latch/fuse_blown remain as-is to prevent re-arming after fuse.
//
//  * FIRST READ ATTEMPT (measurement):
//      - On first read && live (not collapsed, not fused/killed):
//           collapsed  <= 1
//           kill_latch <= 1
//           fuse_fire  <= 1-cycle pulse
//           stored_value overwritten with LFSR (optional wipe)
//      - This occurs *regardless* of basis match.
//        WRONG-BASIS READ → destroys the secret, returns only obfuscation.
//
//  * OUTPUT SEMANTICS (same cycle):
//      - If read && live && basis_match:
//            value_out = stored_value (true value, once only)
//        else:
//            value_out = lfsr (noise)
//
//  * AFTER COLLAPSE:
//      - All reads → noise only
//      - pad_enable remains permanently LOW (physical kill)
// ============================================================================

module qkd_collapse_register (
    input  logic       clk,
    input  logic       reset,
    input  logic       init,            // load fresh value + basis
    input  logic       read,            // one-cycle read strobe (sync)
    input  logic [1:0] basis_in,        // reader's measurement basis
    // --- data outputs ---
    output logic [7:0] value_out,       // true value only once (if basis-match)
    output logic       output_enable,   // pulses on valid sampling edge
    // --- physical disable / tamper ---
    input  logic       fuse_blow,       // external request to blow fuse / kill
    output logic       pad_enable,      // I/O pad OE; killed permanently on collapse/fuse
    output logic       fuse_fire        // 1-cycle collapse pulse for OTP/antifuse
);

  // --------------------------------------------------------------------------
  // Internal storage & metadata
  // --------------------------------------------------------------------------
  logic [7:0] stored_value;
  logic [1:0] basis;

  // Lifecycle / tamper latches
  logic       collapsed;    // logical read-once
  logic       kill_latch;   // physical permanent disable
  logic       fuse_blown;   // latched external fuse

  // --------------------------------------------------------------------------
  // 8-bit LFSR for obfuscation (same polynomial as other ROOM modules)
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
  // Lifecycle logic: init, collapse, fuse
  // --------------------------------------------------------------------------
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      stored_value <= '0;
      basis        <= 2'b00;
      collapsed    <= 1'b0;
      kill_latch   <= 1'b0;
      fuse_blown   <= 1'b0;
      fuse_fire    <= 1'b0;
    end else begin
      fuse_fire <= 1'b0;  // default

      // External fuse → immediate permanent kill
      if (fuse_blow) begin
        fuse_blown <= 1'b1;
        kill_latch <= 1'b1;
      end

      // INIT: load fresh value and randomized basis
      if (init && !fuse_blown) begin
        stored_value <= lfsr;       // in production use TRNG/QRNG
        basis        <= lfsr[1:0];  // random BB84-style basis
        collapsed    <= 1'b0;
        // kill_latch <= 1'b0; // Only if you allow re-arming of physical OE
      end

      // FIRST READ ATTEMPT collapses the cell (QKD-style measurement)
      if (read && !collapsed && !kill_latch && !fuse_blown) begin
        collapsed    <= 1'b1;      // logical disable
        kill_latch   <= 1'b1;      // physical disable (permanent)
        fuse_fire    <= 1'b1;      // OTP/antifuse trigger pulse
        stored_value <= lfsr;      // optional: wipe secret on collapse
      end
    end
  end

  // --------------------------------------------------------------------------
  // Authorization: first-use, basis-match, not killed/fused
  // --------------------------------------------------------------------------
  wire basis_ok   = (basis_in == basis);
  wire live       = (!collapsed) && (!kill_latch) && (!fuse_blown);
  wire authorized = live && basis_ok;

  // --------------------------------------------------------------------------
  // Same-cycle output logic
  // --------------------------------------------------------------------------
  always_comb begin
    if (read && authorized)
      value_out = stored_value;   // true BB84 outcome
    else
      value_out = lfsr;           // noise (decoy or post-collapse)
  end

  // Logical OE (one-cycle pulse)
  assign output_enable = (read && authorized);

  // Physical OE to pad: permanently killed once collapse/fuse occurs
  assign pad_enable = output_enable & ~kill_latch & ~fuse_blown;

endmodule
