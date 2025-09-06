//You may use this software for **personal, research, academic, and other noncommercial purposes** free of charge.  
//Any **commercial use** requires a separate license from QSymbolic LLC.  
//This software is provided **“as is”**, without warranties or conditions of any kind.

//**E91 in spirit (qkd_entangled_pair):**
//- Shared “entangled” value + common basis tag
//- Either party’s read collapses the pair for both
//- Matching basis → correlated outputs (same value)
//- Mismatched basis → noise; collapse still enforced

module qkd_entangled_pair (
    input  logic       clk,
    input  logic       reset,
    input  logic       init,            // load fresh entangled value + basis
    input  logic       read_A,          // one-cycle read strobes (sync)
    input  logic       read_B,
    input  logic [1:0] basis_A,
    input  logic [1:0] basis_B,
    // --- data outputs (logical) ---
    output logic [7:0] out_A,           // presents value pre-edge; collapses same cycle
    output logic [7:0] out_B,
    output logic       valid_A,         // pulses only on valid sampling edge
    output logic       valid_B,
    // --- physical disable / tamper hooks ---
    input  logic       fuse_blow,       // external request to blow fuse / hard kill
    output logic       pad_enable_A,    // PHYSICAL OE to I/O pads; latch LOW permanently after kill/fuse
    output logic       pad_enable_B,
    output logic       fuse_fire        // 1-cycle pulse at collapse to drive OTP/antifuse/kill circuit
);

  // Shared entangled value & metadata
  logic [7:0] entangled_value;
  logic [1:0] entangled_basis;

  // Lifecycle & tamper
  logic       collapsed;     // logical disable (read-once)
  logic       kill_latch;    // physical disable (permanent) — shared by both sides
  logic       fuse_blown;    // latched result of fuse request

  // Synthesizable 8-bit LFSR (x^8 + x^6 + x^5 + x^4 + 1) for obfuscation/entropy
    // In production you would use an entropy source of your choosing
  logic [7:0] lfsr;
  always_ff @(posedge clk or posedge reset) begin
    if (reset)       lfsr <= 8'hA5; // nonzero seed
    else             lfsr <= {lfsr[6:0], lfsr[7]^lfsr[5]^lfsr[4]^lfsr[3]};
  end

  // Lifecycle & initialization
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      entangled_value <= '0;
      entangled_basis <= 2'b00;
      collapsed       <= 1'b0;
      kill_latch      <= 1'b0;
      fuse_blown      <= 1'b0;
      fuse_fire       <= 1'b0;
    end else begin
      fuse_fire <= 1'b0; // default deassert (single-cycle pulse)

      // External fuse request → immediate permanent physical disable
      if (fuse_blow) begin
        fuse_blown <= 1'b1;
        kill_latch <= 1'b1;
      end

      // Load a fresh pair; clear LOGICAL collapse (do not clear kill/fuse unless factory re-arm)
      if (init && !fuse_blown) begin
        entangled_value <= lfsr;        // or TRNG
        entangled_basis <= lfsr[1:0];   // randomized basis tag
        collapsed       <= 1'b0;
        // kill_latch <= 1'b0; // ← uncomment ONLY if re-arming pads after init is allowed
      end

      // SAME EDGE: collapse and physically kill when either side reads while live
      if ((read_A || read_B) && !collapsed && !kill_latch && !fuse_blown) begin
        collapsed  <= 1'b1;   // logical disable
        kill_latch <= 1'b1;   // physical disable (permanent, both sides)
        fuse_fire  <= 1'b1;   // pulse to OTP/antifuse / wordline- or SA-kill
        // Optional hardening: wipe on collapse to defeat remanence
        entangled_value <= lfsr;
      end
    end
  end

  // Authorization per party (QKD-style basis check + first-use + not killed/fused)
  wire live       = (!collapsed) && (!kill_latch) && (!fuse_blown);
  wire auth_A     = live && (basis_A == entangled_basis);
  wire auth_B     = live && (basis_B == entangled_basis);

  // Same-cycle outputs:
  // If (read_X && auth_X) is true just before the sampling edge, present entangled_value for capture.
  // On that SAME edge, collapse/kill latch and path immediately reverts to LFSR.
  always_comb begin
    out_A   = (read_A && auth_A) ? entangled_value : lfsr;
    out_B   = (read_B && auth_B) ? entangled_value : lfsr;
    valid_A = (read_A && auth_A);
    valid_B = (read_B && auth_B);
  end

  // PHYSICAL OE to I/O pads: once kill_latch/fuse_blown asserts, stays LOW permanently
  assign pad_enable_A = valid_A & ~kill_latch & ~fuse_blown;
  assign pad_enable_B = valid_B & ~kill_latch & ~fuse_blown;

endmodule
