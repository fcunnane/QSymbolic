// ============================================================================
// ATOMIC MEMORY™ / ROOM – Symbolic QKD Register
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
// Current collapse semantics (Symbolic-QKD adaptation):
//
//  * INIT:
//      - Randomized basis_tag, phase_tag, and stored_value loaded.
//      - Policy tags (authorized_id, time window) initialized.
//      - collapse cleared; kill_latch/fuse_blown not cleared (cannot re-arm).
//
//  * FIRST READ ATTEMPT (measurement-like):
//      - On first read && live:
//            collapsed  <= 1
//            kill_latch <= 1
//            fuse_fire  <= 1
//            stored_value <= lfsr (optional wipe)
//      - Wrong metadata still collapses—secret destroyed.
//
//  * SAME-CYCLE OUTPUT SEMANTICS:
//      - If (read && all metadata match && live):
//            value_out = stored_value    (true value for one cycle)
//        else:
//            value_out = lfsr            (noise)
//
//  * AFTER COLLAPSE:
//      - No further true outputs
//      - pad_enable permanently LOW
// ============================================================================

module symbolic_qkd_register (
    input  logic       clk,
    input  logic       reset,
    input  logic       init,             // initialize value + metadata
    input  logic       read,             // one-cycle read strobe (sync)
    input  logic [1:0] basis_in,         // reader basis
    input  logic [1:0] phase_in,         // reader phase
    input  logic [3:0] identity_in,      // reader identity
    input  logic [7:0] time_in,          // current time
    // --- logical outputs ---
    output logic [7:0] value_out,        // true value only once if metadata match
    output logic       output_enable,    // 1-cycle logical OE pulse
    // --- physical disable / tamper ---
    input  logic       fuse_blow,
    output logic       pad_enable,       // hardware OE; permanently LOW after collapse/fuse
    output logic       fuse_fire         // 1-cycle pulse to OTP/antifuse
);

  // --------------------------------------------------------------------------
  // Internal value and symbolic metadata
  // --------------------------------------------------------------------------
  logic [7:0] stored_value;
  logic [1:0] basis_tag;
  logic [1:0] phase_tag;

  logic [3:0] authorized_id;
  logic [7:0] valid_time_start;
  logic [7:0] valid_time_end;

  // Lifecycle and tamper state
  logic       collapsed;    // logical read-once
  logic       kill_latch;   // physical disable (permanent)
  logic       fuse_blown;   // external fuse latch

  // --------------------------------------------------------------------------
  // Obfuscation LFSR (same polynomial as all ROOM modules)
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
  // Lifecycle: init, collapse, fuse logic
  // --------------------------------------------------------------------------
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      stored_value     <= '0;
      basis_tag        <= 2'b00;
      phase_tag        <= 2'b00;
      authorized_id    <= 4'h0;
      valid_time_start <= 8'd0;
      valid_time_end   <= 8'd0;
      collapsed        <= 1'b0;
      kill_latch       <= 1'b0;
      fuse_blown       <= 1'b0;
      fuse_fire        <= 1'b0;
    end else begin
      fuse_fire <= 1'b0;

      // Permanent kill from external fuse
      if (fuse_blow) begin
        fuse_blown <= 1'b1;
        kill_latch <= 1'b1;
      end

      // Initialization (cannot re-arm fused part)
      if (init && !fuse_blown) begin
        stored_value     <= lfsr;        // TRNG/LFSR/etc.
        basis_tag        <= lfsr[1:0];   // randomized BB84-style basis
        phase_tag        <= lfsr[3:2];   // randomized phase
        authorized_id    <= 4'hA;        // symbolic policy
        valid_time_start <= 8'd10;       // symbolic time window
        valid_time_end   <= 8'd200;
        collapsed        <= 1'b0;
        // kill_latch    <= 1'b0; // Only if re-arming pad is allowed
      end

      // FIRST READ collapses the register
      if (read && !collapsed && !kill_latch && !fuse_blown) begin
        collapsed    <= 1'b1;    // logical disable
        kill_latch   <= 1'b1;    // physical disable (permanent)
        fuse_fire    <= 1'b1;    // collapse pulse
        stored_value <= lfsr;    // optional: wipe on collapse
      end
    end
  end

  // --------------------------------------------------------------------------
  // Metadata authorization checks
  // --------------------------------------------------------------------------
  wire basis_ok = (basis_in == basis_tag);
  wire phase_ok = (phase_in == phase_tag);
  wire id_ok    = (identity_in == authorized_id);
  wire time_ok  = (time_in >= valid_time_start) && (time_in <= valid_time_end);

  wire live       = (!collapsed) && (!kill_latch) && (!fuse_blown);
  wire authorized = live && basis_ok && phase_ok && id_ok && time_ok;

  // --------------------------------------------------------------------------
  // Same-cycle output logic
  // --------------------------------------------------------------------------
  always_comb begin
    if (read && authorized)
      value_out = stored_value;   // true symbolic-QKD release (one time only)
    else
      value_out = lfsr;           // noise or post-collapse obfuscation
  end

  // Logical OE pulse
  assign output_enable = (read && authorized);

  // Physical OE: permanently LOW after collapse/fuse
  assign pad_enable = output_enable & ~kill_latch & ~fuse_blown;

endmodule
