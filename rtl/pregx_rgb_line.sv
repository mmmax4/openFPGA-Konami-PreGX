// Ordered Mystic RGB line accumulator. The caller supplies fragments in global
// sprite/tile order and performs sprite solid-Z/pen acceptance before admission.
// Palette read is one registered clock, as on gaia_main's scanout port.
// Same-address requests wait until older writes retire; distinct pixels sustain
// one fragment/clock. Producer order and machine wiring are qualified separately.
`default_nettype none
module pregx_rgb_line #(
    parameter int WIDTH = 288,
    parameter int AW = 9
) (
    input logic clk, reset,
    input logic line_start,
    input logic [23:0] backdrop,
    input logic [8:0] shadow_delta [9],
    input logic noclip,
    output logic busy,
    input logic fragment_valid,
    output logic fragment_ready,
    input logic [AW-1:0] fragment_x,
    // Read-only admission probe: keeps a producer ready path before its X mux.
    input logic [AW-1:0] probe_x,
    output logic probe_ready,
    input logic [10:0] fragment_pen,
    input logic [9:0] fragment_level,
    input logic [7:0] fragment_brightness,
    input logic fragment_tile,
    input logic [7:0] fragment_toppri,
    input logic fragment_shadow,
    input logic [1:0] fragment_table,
    input logic [1:0] fragment_condition,
    input logic [7:0] fragment_z, fragment_pri,
    output wire [10:0] palette_addr,
    input logic [23:0] palette_q,
    input logic [AW-1:0] scan_x,
    output logic [23:0] scan_rgb
);
    localparam int DEPTH = 1 << AW;
    logic bank, clearing, initialized;
    logic [AW-1:0] clear_x;
    logic [23:0] line_backdrop;
    logic [8:0] line_delta[9];
    logic line_noclip;
    // Explicit banks avoid a flattened three-address (RMW read/write plus
    // scanout) RAM. Each physical bank needs one read and one write port;
    // scanout reads the bank opposite the current render/RMW bank.
    logic [23:0] colors0[DEPTH],colors1[DEPTH];
    logic [23:0] color0_q,color1_q;
    logic read_bank,scan_active;
    // Only the current render line needs topmost and shadow Z/priority state.
    logic [23:0] state_ram[DEPTH]; // {topmost, shadowZ, shadowPriority}
    wire [23:0] dst_q=read_bank ? color1_q : color0_q;
    logic [23:0] state_q;
    assign scan_rgb=scan_active ? (read_bank ? color0_q : color1_q) : 24'd0;
    logic [3:0] pending;
    logic [AW-1:0] addresses[4];
    logic [23:0] state_pipe[1:3];
    logic write_pipe[1:3];
    logic [9:0] level0;
    logic [7:0] brightness0;
    logic tile0, shadow0;
    logic [1:0] table0, condition0;
    logic [7:0] top0, z0, pri0;
    logic address_pending;
    always_comb begin
        address_pending = 1'b0;
        for (int i=0;i<4;i++)
            if (pending[i] && addresses[i]==fragment_x) address_pending=1'b1;
    end
    assign fragment_ready = initialized && !reset && !line_start && !clearing &&
                            !address_pending && {1'b0,fragment_x} < (AW+1)'(WIDTH);
    logic probe_pending;
    always_comb begin
        probe_pending = 1'b0;
        for (int i=0;i<4;i++)
            if (pending[i] && addresses[i]==probe_x) probe_pending=1'b1;
    end
    assign probe_ready = initialized && !reset && !line_start && !clearing &&
                         !probe_pending && {1'b0,probe_x} < (AW+1)'(WIDTH);
    wire accept = fragment_valid && fragment_ready;
    assign palette_addr = fragment_pen;
    assign busy = clearing || (|pending);

    function automatic [7:0] shade_channel(input logic [4:0] c,
                                          input logic [8:0] delta,
                                          input logic wrap_color);
        logic signed [9:0] sum;
        logic signed [9:0] displacement;
        // The palette shadow lookup takes RGB15 then expands each 5-bit byte.
        // Pinned dipalette clamps displacement to[-255,255] before wrap.
        // Its own source questions this policy; no silicon claim for-256.
        displacement=delta==9'h100 ? -10'sd255 : $signed({delta[8],delta});
        sum = $signed({2'd0,c,c[4:2]}) + displacement;
        return wrap_color ? sum[7:0] :
               sum<10'sd0 ? 8'd0 : sum>10'sd255 ? 8'd255 : sum[7:0];
    endfunction
    logic [23:0] shadow_rgb;
    logic [8:0] deltas[3];
    logic shadow_allowed, write_allowed;
    logic [23:0] next_state;
    always_comb begin
        for (int c=0;c<3;c++)
            deltas[c] = table0==2'd3 ? -9'sd80 : line_delta[4'(table0)*4'd3+4'(c)];
        shadow_allowed = state_q[15:8]>=z0 && state_q[7:0]>pri0;
        if (condition0==2'd1)
            shadow_allowed &= state_q[23:16]!=8'hff && pri0>state_q[23:16];
        else if (condition0==2'd2)
            shadow_allowed &= state_q[23:16]!=8'hff && pri0==state_q[23:16];
        // A zero-alpha tile returns before recording topmost. Sprite alpha0
        // culling belongs to drawmode acceptance in the actual sprite caller.
        write_allowed = shadow0 ? shadow_allowed :
                        !(tile0 && !level0[8] && level0[7:0]==8'd0);
        next_state = shadow0 ? {state_q[23:16],z0,pri0} : {top0,state_q[15:0]};
        shadow_rgb = {
            shade_channel(dst_q[23:19],deltas[0],line_noclip),
            shade_channel(dst_q[15:11],deltas[1],line_noclip),
            shade_channel(dst_q[7:3],deltas[2],line_noclip)};
    end
    wire blend_valid;
    wire [23:0] blend_rgb;
    pregx_rgb_blend_pipeline blend(
        .clk(clk),.reset(reset || line_start),.valid_in(pending[0]),
        .src(palette_q),.dst(dst_q),.brightness(brightness0),
        .source_override(shadow0),.override_rgb(shadow_rgb),
        .level(shadow0 ? 10'd255 : level0),
        .is_tile(tile0),.valid_out(blend_valid),.rgb(blend_rgb)
    );
    always_ff @(posedge clk) begin
        if (reset) begin
            bank<=1'b0; clearing<=1'b0; initialized<=1'b0; clear_x<='0; pending<='0;
        end else if (line_start) begin
            bank<=~bank; clearing<=1'b1; initialized<=1'b1; clear_x<='0; pending<='0;
            line_backdrop<=backdrop; line_noclip<=noclip;
            for (int c=0;c<9;c++) line_delta[c]<=shadow_delta[c];
        end else begin
            // Only pending[0] consumes this payload on the following edge.
            // Capture even on a bubble: pen classification must not drive
            // the shadow-table register's enable across the sprite/RGB path.
            table0<=fragment_table;
            brightness0<=fragment_brightness;
            pending<={pending[2:0],accept};
            if (clearing) begin
                if (clear_x==AW'(WIDTH-1)) clearing<=1'b0;
                else clear_x<=clear_x+1'b1;
            end
            if (accept) begin
                addresses[0]<=fragment_x; level0<=fragment_level;
                tile0<=fragment_tile; top0<=fragment_toppri;
                shadow0<=fragment_shadow;
                condition0<=fragment_condition; z0<=fragment_z; pri0<=fragment_pri;
            end
            if (pending[0]) begin
                addresses[1]<=addresses[0];
                state_pipe[1]<=next_state; write_pipe[1]<=write_allowed;
            end
            for (int i=2;i<4;i++) if(pending[i-1]) begin
                addresses[i]<=addresses[i-1];
                state_pipe[i]<=state_pipe[i-1]; write_pipe[i]<=write_pipe[i-1];
            end
        end
    end
    // The two RAM writes are mutually exclusive and use a single write port.
    // A new line/reset cancels in-flight operations before changing the bank.
    always_ff @(posedge clk) begin
        color0_q<=colors0[bank ? scan_x : fragment_x];
        color1_q<=colors1[bank ? fragment_x : scan_x];
        read_bank<=bank;scan_active<=!reset;
        state_q<=state_ram[fragment_x];
        if (!reset && !line_start) begin
            if (clearing) begin
                if(bank) colors1[clear_x]<=line_backdrop;
                else colors0[clear_x]<=line_backdrop;
                state_ram[clear_x]<=24'hffffff;
            end else if (blend_valid && write_pipe[3]) begin
                if(bank) colors1[addresses[3]]<=blend_rgb;
                else colors0[addresses[3]]<=blend_rgb;
                state_ram[addresses[3]]<=state_pipe[3];
            end
        end
    end
endmodule
`default_nettype wire
