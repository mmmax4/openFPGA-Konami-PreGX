// Actual M4 object-list and streamed renderer; original public setup only.
`default_nettype none
module m4_sprite_top(
 input logic clk,reset,build,start,inspect,ready,order_ready,
 input logic[9:0]inspect_index,input logic[8:0]line,
 input logic ram_we,input logic[10:0]ram_waddr,input logic[15:0]ram_wdata,
 input logic[7:0]k55[48],k46[8],input logic[15:0]k38[16],k47[8],
 output wire build_done,overflow,busy,output wire[9:0]count,output wire[31:0]list_q,
 output wire rom_req,output wire[19:0]rom_addr,input logic rom_ack,input logic[63:0]rom_q,
 output wire order_valid,output wire[7:0]order_priority,output wire order_deferred,
 output wire valid,output wire[8:0]x,output wire[11:0]pen,output wire[9:0]level,
 output wire shadow,output wire[1:0]table_index,condition,
 output wire[7:0]z,priority_code
);
 logic[15:0]ram[2048],ram_q;
 wire[10:0]ol_a,dr_a;wire ol_busy;wire[9:0]dr_list,ol_zoom,dr_zoom;
 wire[7:0]yr_addr;wire[21:0]yr_q;wire[10:0]recip_a;wire[23:0]zoom_q,recip_q;
 always_ff @(posedge clk)begin
  if(ram_we)ram[ram_waddr]<=ram_wdata;
  ram_q<=ram[ol_busy?ol_a:dr_a];
 end
 logic[2:0]shadowon;logic[7:0]shdpri[3];
 always_comb for(int t=0;t<3;t++)begin
  shadowon[t]=0;shdpri[t]=k55[37+t];
  for(int c=0;c<3;c++)begin
   logic[8:0]d;d=k38[2+t*3+c][8:0];if(d[8]?(d<9'h1f9):(d>9'd7))shadowon[t]=1;
  end
 end
 function automatic logic[9:0]alpha(input logic[1:0]effect);
  logic[7:0]v;logic[4:0]l;
  case(effect)1:v=k38[13][7:0];2:v=k38[14][15:8];3:v=k38[14][7:0];default:v=0;endcase
  l=v[5]?v[4:0]:5'd31-v[4:0];return effect==0?10'd255:{k38[15][1],v[5],l,l[4:2]};
 endfunction
 sprite_tables #(.HEXDIR("rtl/data")) tables(.clk(clk),.zoom_addr(ol_busy?ol_zoom:dr_zoom),.zoom_q(zoom_q),.recip_addr(recip_a),.recip_q(recip_q));
 k053247_objlist list(.clk(clk),.reset(reset),.metam(1'b1),.mystic(1'b0),.violent(1'b0),.intro_postportrait(1'b0),
 .stream_enable(1'b1),.shdprisel(k55[41][5:0]),.start(build),.done(build_done),.busy(ol_busy),
 .opset(k47[6]),.objset1(k46[5]),.shadowon(shadowon),.shdpri(shdpri),.k46_offy({k46[2],k46[3]}),
 .zoom_addr(ol_zoom),.zoom_q(zoom_q),.yr_addr(yr_addr),.yr_q(yr_q),.ram_addr(ol_a),.ram_q(ram_q),
 .list_idx(inspect?inspect_index:dr_list),.list_q(list_q),.count(count),.overflow(overflow));
 k053247_draw draw(.clk(clk),.reset(reset),.metam(1'b1),.mystic(1'b0),.violent(1'b0),.rom_fifth(16'd0),
 .stream_enable(1'b1),.order_valid(order_valid),.order_priority(order_priority),.order_deferred(order_deferred),.order_ready(order_ready),
 .fragment_valid(valid),.fragment_ready(ready),.fragment_x(x),.fragment_pen(pen),.fragment_level(level),
 .fragment_shadow(shadow),.fragment_table(table_index),.fragment_condition(condition),.fragment_z(z),.fragment_pri(priority_code),
 .alpha1(alpha(1)),.alpha2(alpha(2)),.alpha3(alpha(3)),.line_start(start),.line(line),.busy(busy),
 .k46r5(k46[5]),.k46_offx({k46[0],k46[1]}),.k46_offy({k46[2],k46[3]}),.opset(k47[6]),.colorbase({k55[27][3:0],4'd0}),
 .list_idx(dr_list),.list_q(list_q),.list_count(count),.yr_addr(yr_addr),.yr_q(yr_q),.ram_addr(dr_a),.ram_q(ram_q),
 .rom_req(rom_req),.rom_addr(rom_addr),.rom_ack(rom_ack),.rom_q(rom_q),.zoom_addr(dr_zoom),.zoom_q(zoom_q),.recip_addr(recip_a),.recip_q(recip_q),
 .px(9'd0),.out_opaque(),.out_pen(),.out_pri(),.out_effect(),.out_shadow(),.out_shtab(),.out_shpri(),.shadow_overlap(),
 .dbg_objs(),.dbg_rows(),.dbg_cols(),.dbg_pxw());
endmodule
`default_nettype wire
