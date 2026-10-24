//altclkctrl CBX_SINGLE_OUTPUT_FILE="ON" CLOCK_TYPE="Global Clock" DEVICE_FAMILY="Cyclone V" ENA_REGISTER_MODE="falling edge" USE_GLITCH_FREE_SWITCH_OVER_IMPLEMENTATION="ON" clkselect ena inclk outclk
//VERSION_BEGIN 21.1 cbx_altclkbuf 2022:06:23:22:02:32:SJ cbx_cycloneii 2022:06:23:22:02:32:SJ cbx_lpm_add_sub 2022:06:23:22:02:32:SJ cbx_lpm_compare 2022:06:23:22:02:32:SJ cbx_lpm_decode 2022:06:23:22:02:32:SJ cbx_lpm_mux 2022:06:23:22:02:32:SJ cbx_mgl 2022:06:23:22:26:17:SJ cbx_nadder 2022:06:23:22:02:32:SJ cbx_stratix 2022:06:23:22:02:32:SJ cbx_stratixii 2022:06:23:22:02:32:SJ cbx_stratixiii 2022:06:23:22:02:32:SJ cbx_stratixv 2022:06:23:22:02:32:SJ  VERSION_END
// synthesis VERILOG_INPUT_VERSION VERILOG_2001
// altera message_off 10463



// Copyright (C) 2022  Intel Corporation. All rights reserved.
//  Your use of Intel Corporation's design tools, logic functions 
//  and other software and tools, and any partner logic 
//  functions, and any output files from any of the foregoing 
//  (including device programming or simulation files), and any 
//  associated documentation or information are expressly subject 
//  to the terms and conditions of the Intel Program License 
//  Subscription Agreement, the Intel Quartus Prime License Agreement,
//  the Intel FPGA IP License Agreement, or other applicable license
//  agreement, including, without limitation, that your use is for
//  the sole purpose of programming logic devices manufactured by
//  Intel and sold by Intel or its authorized distributors.  Please
//  refer to the applicable agreement for further details, at
//  https://fpgasoftware.intel.com/eula.



//synthesis_resources = cyclonev_clkena 1 reg 2 
//synopsys translate_off
`timescale 1 ps / 1 ps
//synopsys translate_on
module  pregx_vidmux_sub
	( 
	clkselect,
	ena,
	inclk,
	outclk) /* synthesis synthesis_clearbox=1 */;
	input   [1:0]  clkselect;
	input   ena;
	input   [3:0]  inclk;
	output   outclk;
`ifndef ALTERA_RESERVED_QIS
// synopsys translate_off
`endif
	tri0   [1:0]  clkselect;
	tri1   ena;
	tri0   [3:0]  inclk;
`ifndef ALTERA_RESERVED_QIS
// synopsys translate_on
`endif

	(* ALTERA_ATTRIBUTE = {"POWER_UP_LEVEL=LOW"} *)
	reg	[1:0]	select_reg;
	wire  wire_sd2_outclk;
	wire  wire_sd1_enaout;
	wire  wire_sd1_outclk;
	wire  [1:0]  clkselect_wire;
	wire  [3:0]  inclk_wire;
	wire  [1:0]  select_enable_wire;

	// synopsys translate_off
	initial
		select_reg = 0;
	// synopsys translate_on
	always @ ( posedge wire_sd2_outclk)
		if (wire_sd1_enaout == 1'b0)   select_reg <= clkselect_wire[1:0];
	cyclonev_clkselect   sd2
	( 
	.clkselect({select_reg}),
	.inclk(inclk_wire),
	.outclk(wire_sd2_outclk));
	cyclonev_clkena   sd1
	( 
	.ena((ena & (~ select_enable_wire[1]))),
	.enaout(wire_sd1_enaout),
	.inclk(wire_sd2_outclk),
	.outclk(wire_sd1_outclk));
	defparam
		sd1.clock_type = "Global Clock",
		sd1.ena_register_mode = "falling edge",
		sd1.lpm_type = "cyclonev_clkena";
	assign
		clkselect_wire = {clkselect},
		inclk_wire = {inclk},
		outclk = wire_sd1_outclk,
		select_enable_wire = {(select_enable_wire[0] | (clkselect_wire[1] ^ select_reg[1])), (clkselect_wire[0] ^ select_reg[0])};
endmodule //pregx_vidmux_sub
//VALID FILE // (C) 2001-2022 Intel Corporation. All rights reserved.
// Your use of Intel Corporation's design tools, logic functions and other 
// software and tools, and its AMPP partner logic functions, and any output 
// files from any of the foregoing (including device programming or simulation 
// files), and any associated documentation or information are expressly subject 
// to the terms and conditions of the Intel Program License Subscription 
// Agreement, Intel FPGA IP License Agreement, or other applicable 
// license agreement, including, without limitation, that your use is for the 
// sole purpose of programming logic devices manufactured by Intel and sold by 
// Intel or its authorized distributors.  Please refer to the applicable 
// agreement for further details.



// synopsys translate_off
`timescale 1 ps / 1 ps
// synopsys translate_on
module  pregx_vidmux  (
    ena,
    clkselect,
    inclk0x,
    inclk1x,
    inclk2x,
    inclk3x,
    outclk);

    input    ena;
    input  [1:0]  clkselect;
    input    inclk0x;
    input    inclk1x;
    input    inclk2x;
    input    inclk3x;
    output   outclk;
`ifndef ALTERA_RESERVED_QIS
// synopsys translate_off
`endif
    tri1     ena;
    tri0 [1:0]  clkselect;
`ifndef ALTERA_RESERVED_QIS
// synopsys translate_on
`endif

    wire  sub_wire0;
    wire  outclk;
    wire  sub_wire1;
    wire [3:0] sub_wire2;
    wire  sub_wire3;
    wire  sub_wire4;
    wire  sub_wire5;

    assign  outclk = sub_wire0;
    assign  sub_wire1 = inclk0x;
    assign sub_wire2[3:0] = {sub_wire5, sub_wire4, sub_wire3, sub_wire1};
    assign  sub_wire3 = inclk1x;
    assign  sub_wire4 = inclk2x;
    assign  sub_wire5 = inclk3x;

    pregx_vidmux_sub  pregx_vidmux_sub_component (
                .clkselect (clkselect),
                .ena (ena),
                .inclk (sub_wire2),
                .outclk (sub_wire0));

endmodule