`default_nettype none
module tb_m2_inputs (
 input logic mystic,input logic [7:0] p1_keys,p2_keys,p3_keys,p4_keys,
 input logic [3:0] p1_dirs,p2_dirs,p3_dirs,p4_dirs,
 input logic test_manual,input logic [3:0] test_select,service_select,input logic [4:0] dips,
 output wire [15:0] in0_p1,legacy_in0,mystic_p12,mystic_p34,
 output wire [7:0] in1,p2,legacy_in1,legacy_p2,mystic_in0
);
 pregx_inputs dut(.*);
 gaia_inputs legacy(.p1_keys(p1_keys),.p2_keys(p2_keys),.p1_dirs(p1_dirs),.p2_dirs(p2_dirs),
 .test_manual(test_manual),.test_select(test_select),.service_select(service_select),.dips(dips[1:0]),
 .in0_p1(legacy_in0),.in1(legacy_in1),.p2(legacy_p2));
endmodule
`default_nettype wire
