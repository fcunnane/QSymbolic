module classical_room_register (
    input  logic       clk,
    input  logic       reset,
    input  logic       init,           // load new value
    input  logic       read,           // synchronous one-cycle read strobe
    input  logic [7:0] value_in,       // value to store on init
    output logic [7:0] value_out,      // presents value in SAME cycle as read (pre-edge)
    output logic       output_enable,  // 1 for the sampling edge (logical OE)
    // --- added for physical disable ---
    output logic       pad_enable,     // drive this to the IO buffer's OE; goes low permanently after first read
    output logic       fuse_blow       // 1-cycle pulse at collapse; route to OTP/antifuse/kill circuitry
);

  // Internal storage and one-time latches
  logic [7:0] stored_value;
  logic       collapsed;   // logical collapse (read-once)
  logic       kill_latch;  // physical disable latch (permanent pad/OE kill)

  // Synthesizable 8-bit LFSR for obfuscation (x^8 + x^6 + x^5 + x^4 + 1)
  logic [7:0] lfsr;
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      lfsr <= 8'hA5; // arbitrary nonzero seed
    end else begin
      lfsr <= {lfsr[6:0], lfsr[7]^lfsr[5]^lfsr[4]^lfsr[3]};
    end
  end

  // Lifecycle: store, collapse (logical), and kill (physical)
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      stored_value <= '0;
      collapsed    <= 1'b0;
      kill_latch   <= 1'b0;
      fuse_blow    <= 1'b0;
    end else begin
      fuse_blow <= 1'b0; // default

      if (init) begin
        stored_value <= value_in;
        collapsed    <= 1'b0;   // reset logical collapse on re-init
        kill_latch   <= 1'b0;   // (optional) clear physical kill on re-provisioning flow
                                // set to 1'b1 if provisioning must also be one-time
      end

      // SAME EDGE as read is sampled: latch collapse and physical kill
      if (read && !collapsed && !kill_latch) begin
        collapsed   <= 1'b1;    // logical disable
        kill_latch  <= 1'b1;    // physical disable (permanent)
        fuse_blow   <= 1'b1;    // 1-cycle pulse to blow OTP / cut wordline / kill pad driver
        // Immediate zeroization/hardening (optional but recommended):
        stored_value <= lfsr;   // overwrite with pseudorandom to defeat remanence
      end
    end
  end

  // Same-cycle output selection (combinational):
  // If (read && !collapsed && !kill_latch) is true just before the sampling edge,
  // present stored_value for capture; otherwise present obfuscation.
  always_comb begin
    if (read && !collapsed && !kill_latch)
      value_out = stored_value;
    else
      value_out = lfsr;   // obfuscated output (post-collapse or idle)
  end

  // Logical OE: pulses only at the valid sampling edge
  assign output_enable = (read && !collapsed && !kill_latch);

  // PHYSICAL OE: wire THIS to the I/O pad enable; once kill_latch=1 it stays low forever
  assign pad_enable = output_enable & ~kill_latch;

endmodule
