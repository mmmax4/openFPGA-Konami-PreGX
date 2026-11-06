`default_nettype none
module m3_vio14_sound_top(input wire clk,reset,pause,pix_sync,irq_pulse,input wire[1:0]profile,
 input wire main_wr,input wire[3:0]main_off,input wire[7:0]main_data,
 input wire[1:0]rom_ack,pcm_ack,input wire[7:0]rom_q[2],pcm_q[2],
 output wire[1:0]rom_req,pcm_req,dbg_wr,dbg_rd,dbg_step,dbg_wait,raw_wr,raw_rd,irq_ack,
 output wire[17:0]rom_addr[2],output wire[21:0]pcm_addr[2],
 output wire[15:0]cpu_addr[2],snd_l[2],snd_r[2],output wire[7:0]cpu_wdata[2],cpu_rdata[2],
 output wire[3:0]chip_wr,chip_rd,chip_stall,
 output wire[9:0]chip_addr[4],output wire[7:0]chip_wdata[4],chip_rdata[4],
 output wire cen_8m,cen_48k);
 wire c8,c48;
 clk_enables enables(.clk(clk),.reset(reset),.pix_sync(pix_sync),.mystic(profile==1),.cen_16m(),.cen_8m(c8),.cen_pix(),.cen_48k(c48));
 assign cen_8m=c8&&!pause;assign cen_48k=c48&&!pause;
 wire lat_wr0;wire[1:0]lat_off0;wire[7:0]lat_wdata0,lat_rdata0;
 gaia_sound_baseline b0(.clk(clk),.reset(reset),.mystic(profile==1),.violent(profile==2),.cen_8m(cen_8m),.cen_48k(cen_48k),
 .rom_req(rom_req[0]),.rom_addr(rom_addr[0]),.rom_ack(rom_ack[0]),.rom_q(rom_q[0]),
 .pcm_req(pcm_req[0]),.pcm_addr(pcm_addr[0]),.pcm_ack(pcm_ack[0]),.pcm_q(pcm_q[0]),
 .lat_wr(lat_wr0),.lat_off(lat_off0),.lat_wdata(lat_wdata0),.lat_rdata(lat_rdata0),.irq_pulse(irq_pulse),
 .snd_l(snd_l[0]),.snd_r(snd_r[0]),.dbg_pc(cpu_addr[0]),.dbg_wr(dbg_wr[0]),.dbg_rd(dbg_rd[0]),.dbg_step(dbg_step[0]),.dbg_wait(dbg_wait[0]),.dbg_wdata(cpu_wdata[0]));
 k054321 latch0(.clk(clk),.reset(reset),.m_wr(main_wr),.m_rd(1'b0),.m_off(main_off),.m_wdata(main_data),.m_rdata(),.s_wr(lat_wr0),.s_off(lat_off0),.s_wdata(lat_wdata0),.s_rdata(lat_rdata0),.volume(),.active());
 assign cpu_rdata[0]=b0.cpu_di;
 assign raw_wr[0]=b0.mem_wr_raw;assign raw_rd[0]=b0.mem_rd_raw;
 assign irq_ack[0]=!b0.m1_n&&!b0.iorq_n;
 assign chip_wr[0]=b0.u_k1.cs&&b0.u_k1.wr;assign chip_rd[0]=b0.u_k1.cs&&b0.u_k1.rd;
 assign chip_addr[0]=b0.u_k1.addr;assign chip_wdata[0]=b0.u_k1.wdata;assign chip_rdata[0]=b0.u_k1.rdata;assign chip_stall[0]=b0.u_k1.rd_stall;
 assign chip_wr[1]=b0.u_k2.cs&&b0.u_k2.wr;assign chip_rd[1]=b0.u_k2.cs&&b0.u_k2.rd;
 assign chip_addr[1]=b0.u_k2.addr;assign chip_wdata[1]=b0.u_k2.wdata;assign chip_rdata[1]=b0.u_k2.rdata;assign chip_stall[1]=b0.u_k2.rd_stall;
 wire lat_wr1;wire[1:0]lat_off1;wire[7:0]lat_wdata1,lat_rdata1;
 gaia_sound b1(.clk(clk),.reset(reset),.mystic(profile==1),.violent(profile==2),.cen_8m(cen_8m),.cen_48k(cen_48k),
 .rom_req(rom_req[1]),.rom_addr(rom_addr[1]),.rom_ack(rom_ack[1]),.rom_q(rom_q[1]),
 .pcm_req(pcm_req[1]),.pcm_addr(pcm_addr[1]),.pcm_ack(pcm_ack[1]),.pcm_q(pcm_q[1]),
 .lat_wr(lat_wr1),.lat_off(lat_off1),.lat_wdata(lat_wdata1),.lat_rdata(lat_rdata1),.irq_pulse(irq_pulse),
 .snd_l(snd_l[1]),.snd_r(snd_r[1]),.dbg_pc(cpu_addr[1]),.dbg_wr(dbg_wr[1]),.dbg_rd(dbg_rd[1]),.dbg_step(dbg_step[1]),.dbg_wait(dbg_wait[1]),.dbg_wdata(cpu_wdata[1]));
 k054321 latch1(.clk(clk),.reset(reset),.m_wr(main_wr),.m_rd(1'b0),.m_off(main_off),.m_wdata(main_data),.m_rdata(),.s_wr(lat_wr1),.s_off(lat_off1),.s_wdata(lat_wdata1),.s_rdata(lat_rdata1),.volume(),.active());
 assign cpu_rdata[1]=b1.cpu_di;
 assign raw_wr[1]=b1.mem_wr_raw;assign raw_rd[1]=b1.mem_rd_raw;
 assign irq_ack[1]=!b1.m1_n&&!b1.iorq_n;
 assign chip_wr[2]=b1.u_k1.cs&&b1.u_k1.wr;assign chip_rd[2]=b1.u_k1.cs&&b1.u_k1.rd;
 assign chip_addr[2]=b1.u_k1.addr;assign chip_wdata[2]=b1.u_k1.wdata;assign chip_rdata[2]=b1.u_k1.rdata;assign chip_stall[2]=b1.u_k1.rd_stall;
 assign chip_wr[3]=b1.u_k2.cs&&b1.u_k2.wr;assign chip_rd[3]=b1.u_k2.cs&&b1.u_k2.rd;
 assign chip_addr[3]=b1.u_k2.addr;assign chip_wdata[3]=b1.u_k2.wdata;assign chip_rdata[3]=b1.u_k2.rdata;assign chip_stall[3]=b1.u_k2.rd_stall;
endmodule
`default_nettype wire
