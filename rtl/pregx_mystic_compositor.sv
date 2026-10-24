// Orders four completed tile planes between sprite object boundaries, then
// accumulates accepted fragments in RGB. Deferred shadow objects are supplied
// last by the producer; every tile is completed before that partition starts.
// Tile read port is registered once; palette port is registered once.
`default_nettype none
module pregx_mystic_compositor (
    input logic clk, reset, line_start,
    input logic [7:0] k55regs[48],
    input logic [15:0] k38regs[16],
    input logic [9:0] alpha1, alpha2, alpha3,
    input logic sprite_busy,
    input logic order_valid,
    input logic [7:0] order_priority,
    input logic order_deferred,
    output logic order_ready,
    input logic fragment_valid,
    output logic fragment_ready,
    input logic [8:0] fragment_x,
    input logic [11:0] fragment_pen,
    input logic [9:0] fragment_level,
    input logic fragment_shadow,
    input logic [1:0] fragment_table, fragment_condition,
    input logic [7:0] fragment_z, fragment_pri,
    output logic [8:0] tile_x,
    input logic [11:0] tile_pen[4],
    input logic [3:0] tile_opaque,
    input logic [3:0] tile_nonempty,
    input logic [1:0] tile_category[4],
    output wire [10:0] palette_addr,
    input logic [23:0] palette_q,
    input logic [8:0] scan_x,
    output wire [23:0] rgb,
    output logic busy
);
    typedef enum logic [2:0] {IDLE,CLEAR,OBJECTS,TILE_PRIME,TILE_RUN,DRAIN,SELECT_WAIT,MASK_WAIT} state_t;
    state_t state;
    logic [3:0] done_tiles, enables;
    logic sprite_enable;
    logic [7:0] priorities[4], shadow_on, mix, mix_on;
    logic [9:0] levels[4];
    logic [7:0] tile_brightness[4], object_brightness;
    function automatic [7:0] brightness_factor(input logic [1:0] selector);
        case(selector)
            2'd1: return k38regs[11][7:0];
            2'd2: return k38regs[12][15:8];
            2'd3: return k38regs[12][7:0];
            default: return 8'hff;
        endcase
    endfunction
    logic [1:0] layer;
    logic [8:0] x;
    logic have_tile;
    logic [1:0] next_tile;
    logic [7:0] next_priority;
    // Two registered comparator levels keep tile priority selection out of
    // the object-ready path. Higher layer indices paint first on a tie.
    logic [1:0] pair_valid;
    logic [1:0] pair_tile[2];
    logic [7:0] pair_priority[2];
    always_ff @(posedge clk) begin
        if(reset || line_start) begin
            pair_valid<=2'd0;have_tile<=1'b0;next_tile<=2'd0;next_priority<=8'd0;
            for(int g=0;g<2;g++) begin pair_tile[g]<=2'd0;pair_priority[g]<=8'd0;end
        end else begin
            for(int g=0;g<2;g++) begin
                if(enables[2*g+1] && !done_tiles[2*g+1] &&
                   (!(enables[2*g] && !done_tiles[2*g]) ||
                    priorities[2*g+1]>=priorities[2*g])) begin
                    pair_valid[g]<=1'b1;pair_tile[g]<=2'(2*g+1);
                    pair_priority[g]<=priorities[2*g+1];
                end else begin
                    pair_valid[g]<=enables[2*g] && !done_tiles[2*g];
                    pair_tile[g]<=2'(2*g);pair_priority[g]<=priorities[2*g];
                end
            end
            if(pair_valid[1] && (!pair_valid[0] || pair_priority[1]>=pair_priority[0])) begin
                have_tile<=1'b1;next_tile<=pair_tile[1];next_priority<=pair_priority[1];
            end else begin
                have_tile<=pair_valid[0];next_tile<=pair_tile[0];next_priority<=pair_priority[0];
            end
        end
    end
    wire paint_before = have_tile &&
        (!sprite_busy || (order_valid && (order_deferred || next_priority>order_priority)));
    logic rgb_busy, rgb_ready, sprite_rgb_ready;
    logic rgb_valid;
    logic [8:0] rgb_x;
    logic [10:0] rgb_pen;
    logic [9:0] rgb_level;
    logic [7:0] rgb_brightness;
    logic rgb_tile, rgb_shadow;
    logic [7:0] rgb_top;
    logic [1:0] rgb_table,rgb_condition;
    logic [7:0] rgb_z,rgb_pri;
    wire [1:0] mix_mask = 2'(mix_on >> {layer,1'b0});
    wire [1:0] tile_mix = (tile_category[layer] & ~mix_mask) |
                           (2'(mix >> {layer,1'b0}) & mix_mask);
    wire [9:0] tile_level=levels[tile_mix];
    wire tile_accept = tile_opaque[layer] &&
                      !(!tile_level[8] && tile_level[7:0]==8'd0);
    // Keep the synchronous tile RAM address independent of its returned
    // opaque/category data. Tile runs start with an empty RGB pipeline and
    // visit each x once, so even transparent pixels can obey ready directly.
    wire advance_tile = rgb_ready;
    always_comb begin
        // Reading the next x on the current accepted edge maintains a one-
        // fragment/clock stream through the real registered tile line RAM.
        tile_x=x;
        if(state==TILE_RUN && advance_tile && x<9'd287) tile_x=x+9'd1;
        rgb_valid=fragment_valid && sprite_enable && state==OBJECTS;
        rgb_x=fragment_x;rgb_pen=fragment_pen[10:0];rgb_level=fragment_level;
        rgb_brightness=object_brightness;
        rgb_tile=1'b0;rgb_top=fragment_pri;rgb_shadow=fragment_shadow;
        rgb_table=fragment_table;rgb_condition=fragment_condition;
        rgb_z=fragment_z;rgb_pri=fragment_pri;
        if(state==TILE_RUN) begin
            rgb_valid=tile_accept;rgb_x=x;rgb_pen=tile_pen[layer][10:0];
            rgb_level=tile_level;rgb_tile=1'b1;
            rgb_brightness=tile_brightness[layer];
            rgb_top=shadow_on[{1'b0,layer}] ? priorities[layer] : 8'hff;
            rgb_shadow=1'b0;rgb_table=2'd0;rgb_condition=2'd3;
            rgb_z=8'd0;rgb_pri=priorities[layer];
        end
        order_ready=state==OBJECTS && !paint_before && !rgb_busy;
        fragment_ready=state==OBJECTS && (!sprite_enable || sprite_rgb_ready);
        busy=state!=IDLE;
    end
    logic [8:0] shadow_delta[9];
    always_comb for(int c=0;c<9;c++) shadow_delta[c]=k38regs[c+2][8:0];
    pregx_rgb_line accumulator(
        .clk(clk),.reset(reset),.line_start(line_start),
        .backdrop({k38regs[0][7:0],k38regs[1]}),.shadow_delta(shadow_delta),.noclip(k38regs[15][5]),
        .busy(rgb_busy),.fragment_valid(rgb_valid),.fragment_ready(rgb_ready),
        .probe_x(fragment_x),.probe_ready(sprite_rgb_ready),
        .fragment_x(rgb_x),.fragment_pen(rgb_pen),.fragment_level(rgb_level),
        .fragment_brightness(rgb_brightness),
        .fragment_tile(rgb_tile),.fragment_toppri(rgb_top),.fragment_shadow(rgb_shadow),
        .fragment_table(rgb_table),.fragment_condition(rgb_condition),
        .fragment_z(rgb_z),.fragment_pri(rgb_pri),
        .palette_addr(palette_addr),.palette_q(palette_q),.scan_x(scan_x),.scan_rgb(rgb)
    );
    always_ff @(posedge clk) begin
        if(reset) begin state<=IDLE;done_tiles<='0;x<='0;layer<='0;end
        else if(line_start) begin
            state<=CLEAR;done_tiles<='0;x<='0;
            enables<=k55regs[45][3:0] & {4{k38regs[15][0]}};
            sprite_enable<=k55regs[45][4] && k38regs[15][0];
            priorities[0]<=k55regs[7];priorities[1]<=k55regs[10];
            priorities[2]<=k55regs[13];priorities[3]<=k55regs[14];
            shadow_on<=k55regs[40];mix<=k55regs[33];mix_on<=k55regs[34];
            levels[0]<=10'd255;levels[1]<=alpha1;levels[2]<=alpha2;levels[3]<=alpha3;
            for(int l=0;l<4;l++)
                tile_brightness[l]<=brightness_factor(k55regs[42][2*l+:2]);
            object_brightness<=brightness_factor(k55regs[44][0] ? k55regs[43][1:0] : 2'd0);
        end else case(state)
            // Tile bank swaps after line_start. Sample the completed scan-bank
            // summary after RGB clear, then settle both selector registers.
            CLEAR: if(!rgb_busy) begin enables<=enables & tile_nonempty;state<=MASK_WAIT;end
            MASK_WAIT: state<=SELECT_WAIT;
            OBJECTS: begin
                if(paint_before && !rgb_busy) begin layer<=next_tile;x<='0;state<=TILE_PRIME;end
                else if(!sprite_busy && !have_tile && !rgb_busy) state<=IDLE;
            end
            TILE_PRIME: state<=TILE_RUN;
            TILE_RUN: if(advance_tile) begin
                if(x==9'd287) begin done_tiles[layer]<=1'b1;state<=DRAIN;end
                else x<=x+9'd1;
            end
            // Even a fully transparent tile may drain immediately. Allow the
            // updated done mask through both selector registers before ready.
            DRAIN: if(!rgb_busy) state<=SELECT_WAIT;
            SELECT_WAIT: state<=OBJECTS;
            default: state<=IDLE;
        endcase
    end
    // Logical palette has11address bits; raw palette bit11 is outside the
    // actual2048-entry RAM, preserved at the producer for its own diagnostics.
    wire unused_palette_bit = ^{fragment_pen[11],tile_pen[0][11],tile_pen[1][11],tile_pen[2][11],tile_pen[3][11]};
endmodule
`default_nettype wire
