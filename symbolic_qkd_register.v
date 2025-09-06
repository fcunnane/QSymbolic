//You may use this software for **personal, research, academic, and other noncommercial purposes** free of charge.  
//Any **commercial use** requires a separate license from QSymbolic LLC.  
//This software is provided **“as is”**, without warranties or conditions of any kind.

module symbolic_qkd_register (
    input  logic       clk,
    input  logic       reset,
    input  logic       init,              // initialize value + metadata
    input  logic       read,              // one-cycle read strobe (sync)
    input  logic [1:0] basis_in,          // reader basis
    input  logic [1:0] phase_in,          // reader phase
    input  logic [3:0] identity_in,       // reader identity
    input  logic [7:0] time_in,           // current time
    // --- logical data outputs ---
    output logic [7:0] value_out,         // presents value pre-edge; collapses same cycle
    output logic       output_enable,     // pulses on valid sampling edge (logical OE)
    // --- physical disable / tamper hooks ---
    input  logic       fuse_blow,         // external request to hard-disable (tamper/CSR)
    output logic       pad_enable,        // PHYSICAL OE to pad; latches LOW permanently after kill/fuse
    output logic       fuse_fire          // 1-cycle pulse at collapse to drive OTP/antifuse/kill
);

  // Internal state and metadata
  logic [7:0] stored_value;
  logic [1:0] basis_tag;
  logic [1:0] phase_tag;
  logic [3:0] authorized_id;
  logic [7:0] valid_time_start;
  logic [7:0] valid_time_end;

  // Lifecycle & tamper
  logic       collapsed;     // logical disable (read-once)
  logic       kill_latch;    // physical disable (permanent)
  logic       fuse_blown;    // latched fuse state

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
      stored_value      <= '0;
      basis_tag         <= 2'b00;
      phase_tag         <= 2'b00;
      authorized_id     <= 4'h0;
      valid_time_start  <= 8'd0;
      valid_time_end    <= 8'd0;
      collapsed         <= 1'b0;
      kill_latch        <= 1'b0;
      fuse_blown        <= 1'b0;
      fuse_fire         <= 1'b0;
    end else begin
      fuse_fire <= 1'b0; // default deassert single-cycle pulse

      // External fuse → immediate permanent physical disable
      if (fuse_blow) begin
        fuse_blown <= 1'b1;
        kill_latch <= 1'b1;
      end

      // Load fresh value and metadata; clear logical collapse
      // NOTE: For true OTP provisioning, DO NOT clear kill_latch/fuse_blown here.
      if (init && !fuse_blown) begin
        stored_value      <= lfsr;        // or external entropy
        basis_tag         <= lfsr[1:0];   // randomized basis
        phase_tag         <= lfsr[3:2];   // randomized phase
        authorized_id     <= 4'hA;        // example policy
        valid_time_start  <= 8'd10;       // example window [10,200]
        valid_time_end    <= 8'd200;
        collapsed         <= 1'b0;
        // kill_latch <= 1'b0; // ← uncomment ONLY if re-arming physical OE after init is allowed
      end

      // SAME EDGE: any live read consumes the cell and physically kills output
      if (read && !collapsed && !kill_latch && !fuse_blown) begin
        collapsed    <= 1'b1;   // logical disable
        kill_latch   <= 1'b1;   // physical disable (permanent)
        fuse_fire    <= 1'b1;   // trigger OTP/antifuse / wordline-kill
        // Optional: wipe storage on collapse to defeat remanence
        stored_value <= lfsr;
      end
    end
  end

  // Metadata checks (combinational)
  wire basis_ok = (basis_in   == basis_tag);
  wire phase_ok = (phase_in   == phase_tag);
  wire id_ok    = (identity_in== authorized_id);
  wire time_ok  = (time_in >= valid_time_start) && (time_in <= valid_time_end);

  // Authorization requires first-use and no physical disable/fuse
  wire authorized = (!collapsed) & basis_ok & phase_ok & id_ok & time_ok & (!kill_latch) & (!fuse_blown);

  // Same-cycle output selection:
  // If (read && authorized) just before the edge, present stored_value for capture;
  // on that SAME edge, collapse/kill latches and path reverts to LFSR.
  always_comb begin
    if (read && authorized)
      value_out = stored_value;
    else
      value_out = lfsr;  // obfuscated otherwise
  end

  // Logical OE: pulse only during a valid sampling edge
  assign output_enable = (read && authorized);

  // PHYSICAL OE to pad: once kill_latch/fuse_blown assert, stays LOW permanently
  assign pad_enable = output_enable & ~kill_latch & ~fuse_blown;

endmodule
