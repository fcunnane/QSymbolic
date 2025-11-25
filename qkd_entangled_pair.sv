// ============================================================================
// ATOMIC MEMORY™ / ROOM – E91-Style Entangled Pair (qkd_entangled_pair)
// ----------------------------------------------------------------------------
// QSymbolic Non-Commercial Research License (summary)
//
// - Free for personal, academic, and research use.
// - Any commercial use (products, services, silicon, cloud, etc.) requires
//   a separate written license from QSymbolic LLC.
// - Protected by U.S. Patent Pending: US 19/286,600.
// - See LICENSE in this repository for full terms.
// - Provided "AS IS", without warranty of any kind.
// ----------------------------------------------------------------------------
// Current collapse semantics (E91 entangled-pair adaptation):
//
//  * INIT:
//      - entangled_value <= fresh secret (TRNG/LFSR/etc.)
//      - entangled_basis <= new 2-bit basis
//      - collapsed       <= 0
//        (kill_latch/fuse_blown remain untouched to prevent re-arming)
//
//  * FIRST READ ATTEMPT (A or B):
//      - If (read_A || read_B) && live:
//           collapsed  <= 1
//           kill_latch <= 1
//           fuse_fire  <= 1
//           entangled_value <= lfsr (optional wipe)
//      - Both sides collapse simultaneously — E91-style shared measurement.
//
//  * SAME-CYCLE OUTPUT SEMANTICS:
//      - For each side independently:
//           If read_X && basis_X == entangled_basis && live:
//                out_X = entangled_value (true E91 correlation)
//           Else:
//                out_X = lfsr (noise/decoy)
//      - Wrong basis → collapse but no secret released (QKD security).
//
//  * AFTER COLLAPSE:
//      - All reads from both sides → noise only
//      - pad_enable_* permanently LOW
// ============================================================================

module qkd_entangled_pair (
    input  logic       clk,
    input  logic       reset,
    input  logic       init,            // load fresh entangled value + basis
    input  logic       read_A,          // one-cycle read strobes
    input  logic       read_B,
    input  logic [1:0] basis_A,
    input  logic [1:0] basis_B,
    // --- logical outputs ---
    output logic [7:0] out_A,           // true only once for matching basis / first read
    output logic [7:0] out_B,
    output logic       valid_A,         // pulses on valid sampling edge
    output logic       valid_B,
    // --- physical disable / tamper ---
    input  logic       fuse_blow,       // external physical kill
    output logic       pad_enable_A,    // I/O pad OEs; permanently LOW after collapse/fuse
    output logic       pad_enable_B,
    output logic       fuse_fire        // 1-cycle collapse pulse for OTP/antifuse
);

  // --------------------------------------------------------------------------
  // Shared entangled state (value + basis tag)
  // --------------------------------------------------------------------------
  logic [7:0] entangled_value;
  logic [1:0] entangled_basis;

  // Lifecycle & tamper state
  logic       collapsed;     // logical read-once
  logic       kill_latch;    // physical disable (permanent)
  logic       fuse_blown;    // external fuse latch

  // --------------------------------------------------------------------------
  // 8-bit LFSR for obfuscation / noise (same polynomial as other ROOM modules)
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
  // Lifecycle: init, collapse, fuse, optional wipe
  // --------------------------------------------------------------------------
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      entangled_value <= '0;
      entangled_basis <= 2'b00;
      collapsed       <= 1'b0;
      kill_latch      <= 1'b0;
      fuse_blown      <= 1'b0;
      fuse_fire       <= 1'b0;
    end else begin
      fuse_fire <= 1'b0;  // default deassert

      // External fuse → immediate physical kill
      if (fuse_blow) begin
        fuse_blown <= 1'b1;
        kill_latch <= 1'b1;
      end

      // INIT: load fresh entangled value + basis (unless fused)
      if (init && !fuse_blown) begin
        entangled_value <= lfsr;         // TRNG/LFSR/etc.
        entangled_basis <= lfsr[1:0];    // random basis tag
        collapsed       <= 1'b0;
        // kill_latch <= 1'b0; // Only if re-arming pad is allowed
      end

      // FIRST READ collapses BOTH parties
      if ((read_A || read_B) && !collapsed && !kill_latch && !fuse_blown) begin
        collapsed       <= 1'b1;
        kill_latch      <= 1'b1;
        fuse_fire       <= 1'b1;
        entangled_value <= lfsr; // optional wipe on collapse
      end
    end
  end

  // --------------------------------------------------------------------------
  // Authorization per party
  // --------------------------------------------------------------------------
  wire live = (!collapsed) && (!kill_latch) && (!fuse_blown);

  wire auth_A = live && (basis_A == entangled_basis);
  wire auth_B = live && (basis_B == entangled_basis);

  // --------------------------------------------------------------------------
  // Same-cycle outputs for A and B
  // --------------------------------------------------------------------------
  always_comb begin
    out_A   = (read_A && auth_A) ? entangled_value : lfsr;
    out_B   = (read_B && auth_B) ? entangled_value : lfsr;

    valid_A = (read_A && auth_A);
    valid_B = (read_B && auth_B);
  end

  // --------------------------------------------------------------------------
  // Physical OE: permanently LOW after collapse/fuse
  // --------------------------------------------------------------------------
  assign pad_enable_A = valid_A & ~kill_latch & ~fuse_blown;
  assign pad_enable_B = valid_B & ~kill_latch & ~fuse_blown;

endmodule
