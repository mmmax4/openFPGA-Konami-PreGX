// Mutually exclusive Gaia ROZ / Metamorphic road staging. The same physical
// sixteen 512x16 banks preserve the old 8192x16 tile-cache capacity. All reads
// are one registered cycle: bank selectors belong to that same read edge.
// Ownership must be stable under machine reset before either renderer runs.
`default_nettype none
module pregx_video_ram (
    input logic clk, metam,
    input logic g_we, input logic [12:0] g_wa, g_ra,
    input logic [15:0] g_wdata, output wire [15:0] g_q,
    input logic f_we, input logic [10:0] f_wa, f_ra,
    input logic [15:0] f_wdata, output wire [15:0] f_q,
    input logic c_we, input logic [8:0] c_wa, c_ra,
    input logic [52:0] c_wdata, output wire [52:0] c_q,
    input logic cache_we, input logic [8:0] cache_wa, cache_ra,
    input logic [79:0] cache_wdata, output wire [79:0] cache_q,
    input logic g_lb_we, input logic [11:0] g_lb_wa, g_lb_ra,
    input logic [11:0] g_lb_wdata, output wire [11:0] g_lb_q,
    input logic r_lb_we, input logic [11:0] r_lb_wa, r_lb_ra,
    input logic [8:0] r_lb_wdata, output wire [8:0] r_lb_q
);
    wire [63:0] padded_column = {11'd0,c_wdata};
    logic [15:0] bank_q[16];
    logic [3:0] g_bank;
    logic [1:0] f_bank;
    always_ff @(posedge clk) begin
        g_bank <= g_ra[12:9];
        f_bank <= f_ra[10:9];
    end
    genvar b;
    generate
    for (b=0;b<16;b=b+1) begin: banks
        logic [15:0] mem[512];
        wire [8:0] r_ra, r_wa;
        wire [15:0] r_data;
        wire r_we;
        if (b<4) begin: frame_words
            assign r_ra=f_ra[8:0]; assign r_wa=f_wa[8:0];
            assign r_we=f_we && f_wa[10:9]==2'(b);
            assign r_data=f_wdata;
        end else if (b<8) begin: columns
            assign r_ra=c_ra; assign r_wa=c_wa; assign r_we=c_we;
            assign r_data=padded_column[16*(b-4)+:16];
        end else if (b<13) begin: groups
            assign r_ra=cache_ra; assign r_wa=cache_wa; assign r_we=cache_we;
            assign r_data=cache_wdata[16*(b-8)+:16];
        end else begin: spare
            assign r_ra=9'd0; assign r_wa=9'd0;
            assign r_we=1'b0; assign r_data=16'd0;
        end
        wire we=metam ? r_we : (g_we && g_wa[12:9]==4'(b));
        wire [8:0] wa=metam ? r_wa : g_wa[8:0];
        wire [8:0] ra=metam ? r_ra : g_ra[8:0];
        wire [15:0] wd=metam ? r_data : g_wdata;
        always_ff @(posedge clk) begin
            if(we) mem[wa]<=wd;
            bank_q[b]<=mem[ra];
        end
    end
    endgenerate
    assign g_q=bank_q[g_bank];
    assign f_q=bank_q[{2'd0,f_bank}];
    assign c_q={bank_q[7][4:0],bank_q[6],bank_q[5],bank_q[4]};
    assign cache_q={bank_q[12],bank_q[11],bank_q[10],bank_q[9],bank_q[8]};

    // Preserve Gaia's eight384-pixel banks; road run-ahead uses the same span.
    logic [11:0] line_mem[3072];
    logic [11:0] line_q;
    wire lb_we=metam ? r_lb_we : g_lb_we;
    wire [11:0] lb_wa=metam ? r_lb_wa : g_lb_wa;
    wire [11:0] lb_ra=metam ? r_lb_ra : g_lb_ra;
    wire [11:0] lb_wd=metam ? {3'd0,r_lb_wdata} : g_lb_wdata;
    always_ff @(posedge clk) begin
        if(lb_we) line_mem[lb_wa]<=lb_wd;
        line_q<=line_mem[lb_ra];
    end
    assign g_lb_q=line_q;
    assign r_lb_q=line_q[8:0];
endmodule
`default_nettype wire
