// Ordered RGB arithmetic from pinned MAME K054338/drawgfx contracts.
// This primitive is not a complete mixer: priority/Z/shadows, destination
// hazards, palette delivery and line deadlines belong to its real consumer.
// Three registered stages, accepts one item/clock. Output for an input sampled
// at edgeN is valid just after edgeN+2. Reset discards all in-flight items.
`default_nettype none
module pregx_rgb_blend (
    input logic clk,reset,valid_in,
    input logic [23:0] src,dst,
    input logic [9:0] level,
    input logic is_tile,
    output logic valid_out,
    output logic [23:0] rgb
);
    // Retain the original arithmetic-only public interface and its tests.
    pregx_rgb_blend_pipeline pipeline(
        .clk(clk),.reset(reset),.valid_in(valid_in),.src(src),.dst(dst),
        .brightness(8'hff),.source_override(1'b0),.override_rgb(24'd0),
        .level(level),.is_tile(is_tile),.valid_out(valid_out),.rgb(rgb)
    );
endmodule

// Brightness and alpha occupy separate existing register stages. Palette
// multiplication must not follow the shadow arithmetic/mux: those paths are
// independent until both results have been registered. No extra valid stage.
/* verilator lint_off DECLFILENAME */
module pregx_rgb_blend_pipeline (
    input logic clk,reset,valid_in,
    input logic [23:0] src,dst,
    input logic [7:0] brightness,
    input logic source_override,
    input logic [23:0] override_rgb,
    input logic [9:0] level,
    input logic is_tile,
    output logic valid_out,
    output logic [23:0] rgb
);
/* verilator lint_on DECLFILENAME */
    logic valid0,valid1;
    logic [23:0] src0,dst0,src1,dst1;
    logic [23:0] override_rgb0;
    logic [7:0] bright0[3];
    logic brightness_bypass0, source_override0;
    logic [23:0] scaled_src0;
    function automatic [7:0] brightness_product(input logic [7:0] c,factor);
        // The low byte is deliberately discarded by brightness quantization.
        /* verilator lint_off UNUSEDSIGNAL */
        logic [15:0] product;
        /* verilator lint_on UNUSEDSIGNAL */
        product=c*factor;
        return product[15:8];
    endfunction
    always_comb for(int c=0;c<3;c++)
        scaled_src0[c*8+:8]=source_override0 ? override_rgb0[c*8+:8] :
                          brightness_bypass0 ? src0[c*8+:8] : bright0[c];
    logic [8:0] src_weight0,dst_weight0;
    logic additive0,copy0,additive1,copy1;
    logic [16:0] src_term1[3],dst_term1[3];
    function automatic [7:0] channel(
        input logic [16:0] s,d,input logic [7:0] background,foreground,
        input logic additive,copy_source
    );
        logic [17:0] weighted;
        logic [8:0] added;
        weighted={1'b0,s}+{1'b0,d};
        added={1'b0,background}+{1'b0,8'(s>>8)};
        return copy_source ? foreground : additive ?
            (added[8] ? 8'd255 : added[7:0]) : 8'(weighted>>8);
    endfunction
    always_ff @(posedge clk) begin
        if(reset)begin valid0<=0;valid1<=0;valid_out<=0;end
        else begin valid0<=valid_in;valid1<=valid0;valid_out<=valid1;end
        if(valid_in)begin
            // Keep the shadow/table path out of the palette/product register
            // inputs too; select only already registered sources in stage1.
            src0<=src;override_rgb0<=override_rgb;source_override0<=source_override;
            dst0<=dst;additive0<=level[8];
            brightness_bypass0<=brightness==8'hff;
            for(int c=0;c<3;c++)
                bright0[c]<=brightness_product(src[c*8+:8],brightness);
            // Tiles test the masked byte, sprites test the complete encoded
            // value before selecting the opaque fast path (MIXPRI differs).
            copy0<=!level[8] && ((level==10'd255)||(is_tile&&level[7:0]==8'd255));
            src_weight0<={1'b0,level[7:0]}+((level[8]&&is_tile)?9'd1:9'd0);
            dst_weight0<=9'd256-{1'b0,level[7:0]};
        end
        if(valid0)begin
            src1<=scaled_src0;dst1<=dst0;additive1<=additive0;copy1<=copy0;
            for(int c=0;c<3;c++)begin
                src_term1[c]<=scaled_src0[c*8+:8]*src_weight0;
                dst_term1[c]<=dst0[c*8+:8]*dst_weight0;
            end
        end
        if(valid1)for(int c=0;c<3;c++)
            rgb[c*8+:8]<=channel(src_term1[c],dst_term1[c],dst1[c*8+:8],src1[c*8+:8],additive1,copy1);
    end
endmodule
`default_nettype wire
