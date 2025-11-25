// ============================================================================
// ATOMIC MEMORY™ / ROOM collapse_register_keyexchange
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
// Current collapse semantics (single-byte key fragment):
//
//  * INIT:
//      - 'init' loads a fresh 8-bit key fragment into 'stored_entropy'
//        and arms the register, as long as the fuse has not been blown.
//      - Logical collapse state is cleared, but physical kill remains
//        if already asserted (for true OTP provisioning).
//
//  * FIRST QUALIFIED READ (live cell):
//      - When 'read' is asserted while the cell is live (not collapsed,
//        not killed, not fused), the module:
//          • presents 'stored_entropy' on 'key_fragment' for that cycle
//          • asserts 'output_enable' for that sampling edge
//          • sets 'collapsed'  = 1 (logical read-once)
//          • sets 'kill_latch' = 1 (physical disable / pad kill)
//          • pulses 'fuse_fire' for one cycle
//          • overwrites 'stored_entropy' with LFSR output to destroy
//            the original secret
//
//  * SUBSEQUENT READS (post-collapse / killed):
//      - All later reads, or reads while killed/fused, do NOT reveal the
//        original value. Instead, the output is obfuscation (LFSR).
//      - 'output_enable' deasserts once the cell is collapsed/killed.
//      - 'pad_enable' permanently deasserts once kill_latch/fuse_blown
//        is set, enforcing a physical one-time pad drive.
//
//  * EXTERNAL FUSE / KILL:
//      - 'fuse_blow' immediately latches 'fuse_blown' and 'kill_latch',
//        permanently disabling the pad and preventing re-arming via 'init'.
// ============================================================================

module collapse_register_keyexchange (
    input  logic       clk,
    input  logic       reset,
    input  logic       init,            // load fresh key fragment / entropy (arms logical collapse)
    input  logic       read,            // one-cycle read strobe (sync)
    input  logic [7:0] entropy_in,      // TRNG/QRNG/seed input for initial value
    // --- data outputs ---
    output logic [7:0] key_fragment,    // presents key on first live read; obfuscation otherwise
    output logic       output_enable,   // pulses during valid sampling edge (logical OE)
    // --- physical disable / tamper hooks ---
    input  logic       fuse_blow,       // external request to blow fuse / hard kill
    output logic       pad_enable,      // PHYSICAL OE to I/O pad; latches LOW permanently after kill/fuse
    output logic       fuse_fire        // 1-cycle pulse at collapse to drive OTP/antifuse/kill circuit
);

  // --------------------------------------------------------------------------
  // Internal storage & lifecycle state
  // --------------------------------------------------------------------------
  logic [7:0] stored_entropy;  // holds key fragment while live; overwritten on collapse
  logic       collapsed;       // logical read-once flag
  logic       kill_latch;      // permanent physical disable
  logic       fuse_blown;      // latched result of external fuse request

  // --------------------------------------------------------------------------
  // Synthesizable 8-bit LFSR (x^8 + x^6 + x^5 + x^4 + 1) for obfuscation
  // In a production ASIC, this would be replaced or mixed with a true entropy
  // source (RO-based TRNG, collapse jitter, etc.).
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
  // Lifecycle: init, collapse, external fuse / kill
  // --------------------------------------------------------------------------
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      stored_entropy <= '0;
      collapsed      <= 1'b0;
      kill_latch     <= 1'b0;
      fuse_blown     <= 1'b0;
      fuse_fire      <= 1'b0;
    end else begin
      // default: deassert single-cycle pulse
      fuse_fire <= 1'b0;

      // External fuse request → immediate permanent physical disable
      if (fuse_blow) begin
        fuse_blown <= 1'b1;
        kill_latch <= 1'b1;
      end

      // Load new entropy; clear logical collapse if fuse not blown.
      // NOTE: For strict OTP provisioning, kill_latch/fuse_blown are
      // *not* cleared here, so a fused device cannot be re-armed.
      if (init && !fuse_blown) begin
        stored_entropy <= entropy_in;
        collapsed      <= 1'b0;
        // Uncomment ONLY if re-arming pad after init is allowed:
        // kill_latch   <= 1'b0;
      end

      // SAME EDGE: irrevocably collapse on first live read (if not killed/fused)
      if (read && !collapsed && !kill_latch && !fuse_blown) begin
        collapsed      <= 1'b1;   // logical read-once disable
        kill_latch     <= 1'b1;   // physical pad disable (permanent)
        fuse_fire      <= 1'b1;   // pulse to OTP/antifuse / wordline-kill
        // Destroy original secret: overwrite with obfuscation state
        stored_entropy <= lfsr;
      end
    end
  end

  // --------------------------------------------------------------------------
  // Same-cycle output selection:
  //  - While live and on the first qualified read: output true key fragment.
  //  - Otherwise (idle, post-collapse, killed/fused): output obfuscation LFSR.
  // --------------------------------------------------------------------------
  wire live = (!collapsed) && (!kill_latch) && (!fuse_blown);

  always_comb begin
    if (read && live)
      key_fragment = stored_entropy;
    else
      key_fragment = lfsr;   // obfuscated otherwise (idle, post-collapse, or killed)
  end

  // Logical OE: pulse only during the valid sampling edge while live
  assign output_enable = (read && live);

  // PHYSICAL OE to I/O pad:
  // once kill_latch or fuse_blown asserts, pad_enable stays LOW permanently.
  assign pad_enable = output_enable & ~kill_latch & ~fuse_blown;

endmodule
