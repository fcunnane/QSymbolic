//You may use this software for **personal, research, academic, and other noncommercial purposes** free of charge.  
//Any **commercial use** requires a separate license from QSymbolic LLC.  
//This software is provided **“as is”**, without warranties or conditions of any kind.

module metadata_collapse_register (
    input  logic        clk,
    input  logic        reset,
    input  logic        init,              // load new value + policy
    input  logic        read,              // one-cycle read strobe (sync)
    input  logic [7:0]  value_in,          // value to store on init
    input  logic [3:0]  device_id_in,
    input  logic [1:0]  role_in,           // 00=guest, 01=peer, 10=admin
    input  logic [1:0]  basis_in,          // 00=rect., 01=diag., etc.
    input  logic [7:0]  current_time,
    output logic [7:0]  value_out,         // collapses same cycle as read
    output logic        output_enable,     // pulses during sampling edge
    // --- added for physical disable ---
    input  logic        fuse_blow,         // external request to blow fuse (tamper/CSR)
    output logic        pad_enable,        // wire to I/O pad OE; latches LOW permanently after kill/fuse
    output logic        fuse_fire          // 1-cycle pulse at collapse to drive OTP/antifuse/kill circuit
);

  // Stored value and policy (could also be loaded from control regs)
  logic [7:0] stored_value;
  logic [3:0] allowed_device_id;
  logic [1:0] required_role;
  logic [1:0] expected_basis;
  logic [7:0] valid_time_start;
  logic [7:0] valid_time_end;

  // Lifecycle
  logic       collapsed;    // logical disable
  logic [1:0] read_count;   // counts successful reads (enforce 1)
  logic       kill_latch;   // physical disable latch (permanent)
  logic       fuse_blown;   // latched result of fuse request

  // Synthesizable 8-bit LFSR (x^8 + x^6 + x^5 + x^4 + 1) for obfuscation
  logic [7:0] lfsr;
  always_ff @(posedge clk or posedge reset) begin
    if (reset)       lfsr <= 8'hA5; // nonzero seed
    else             lfsr <= {lfsr[6:0], lfsr[7]^lfsr[5]^lfsr[4]^lfsr[3]};
  end

  // -------- Initialization & lifecycle latches --------
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      stored_value      <= '0;
      allowed_device_id <= 4'h0;
      required_role     <= 2'b00;
      expected_basis    <= 2'b00;
      valid_time_start  <= 8'd0;
      valid_time_end    <= 8'd0;
      collapsed         <= 1'b0;
      read_count        <= 2'd0;
      kill_latch        <= 1'b0;
      fuse_blown        <= 1'b0;
      fuse_fire         <= 1'b0;
    end else begin
      // default deassert single-cycle pulse
      fuse_fire <= 1'b0;

      // External fuse request → immediate permanent physical disable
      if (fuse_blow) begin
        fuse_blown <= 1'b1;
        kill_latch <= 1'b1;
      end

      // Load new value and policy; clear logical collapse & first-use counter.
      // NOTE: For true OTP provisioning, DO NOT clear kill_latch/fuse_blown here.
      if (init) begin
        stored_value      <= value_in;
        // Example policy defaults; replace with config regs as needed
        allowed_device_id <= 4'hA;     // trusted device
        required_role     <= 2'b01;    // peer or higher
        expected_basis    <= 2'b00;    // rectilinear
        valid_time_start  <= 8'd10;    // window [10,100]
        valid_time_end    <= 8'd100;
        collapsed         <= 1'b0;
        read_count        <= 2'd0;
        // kill_latch <= 1'b0; // <- uncomment ONLY if re-arming physical OE after init is allowed
      end
    end
  end

  // -------- Combinational Authorization & Outputs --------

  // Metadata checks
  wire dev_ok   = (device_id_in == allowed_device_id);
  wire role_ok  = (role_in      >= required_role);
  wire basis_ok = (basis_in     == expected_basis);
  wire time_ok  = (current_time >= valid_time_start) &&
                  (current_time <= valid_time_end);

  // First-use and lifecycle gating
  wire first_use_ok = (!collapsed) && (read_count == 2'd0) && !kill_latch && !fuse_blown;

  // Compound authorization
  wire authorized = dev_ok & role_ok & basis_ok & time_ok & first_use_ok;

  // Same-cycle output select:
  //  - If (read && authorized) is true just before the edge, present stored_value for capture.
  //  - On that SAME edge we will latch collapse + kill, so path flips to LFSR immediately after.
  always_comb begin
    if (read && authorized)
      value_out = stored_value;
    else
      value_out = lfsr;  // obfuscated otherwise (mismatch, post-collapse, or killed)
  end

  // Logical OE: pulse only during valid sampling edge
  assign output_enable = (read && authorized);

  // PHYSICAL OE to I/O pad: once kill_latch/fuse_blown asserts, stays LOW permanently
  assign pad_enable = output_enable & ~kill_latch & ~fuse_blown;

  // -------- Finalize lifecycle updates at the sampling edge --------
  always_ff @(posedge clk or posedge reset) begin
    if (!reset) begin
      if (read && authorized) begin
        collapsed  <= 1'b1;   // logical disable
        read_count <= 2'd1;   // consume the one allowed read
        kill_latch <= 1'b1;   // physical disable (permanent)
        fuse_fire  <= 1'b1;   // 1-cycle pulse: drive OTP/antifuse / wordline-kill
        // Optional hardening: wipe storage on collapse to defeat remanence
        stored_value <= lfsr;
      end
    end
  end

endmodule
