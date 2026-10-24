// Board-specific inputs. Keep Gaia cabinet semantics in its qualified module.
// Mystic has four KONAMI8 players, coin1..4, Test at IN1.2 and physical DIP;
// its pinned board ports do not define a separate Service-credit input.
`default_nettype none
module pregx_inputs (
    input wire mystic,
    input wire [7:0] p1_keys,p2_keys,p3_keys,p4_keys,
    input wire [3:0] p1_dirs,p2_dirs,p3_dirs,p4_dirs,
    input wire test_manual,
    input wire [3:0] test_select,service_select,
    input wire [4:0] dips, // bit0 GaiaMono,1 GaiaFlip,2 MysticIndependent,3 Mystic4players,4 MysticMono
    output wire [15:0] in0_p1,
    output wire [7:0] in1,p2,
    output wire [15:0] mystic_p12,mystic_p34,
    output wire [7:0] mystic_in0
);
    wire [7:0] gaia_in1;
    gaia_inputs gaia(.p1_keys(p1_keys),.p2_keys(p2_keys),.p1_dirs(p1_dirs),.p2_dirs(p2_dirs),
        .test_manual(test_manual),.test_select(test_select),.service_select(service_select),
        .dips(dips[1:0]),.in0_p1(in0_p1),.in1(gaia_in1),.p2(p2));
    function automatic [7:0] player(input [7:0] keys,input [3:0] dirs);
        return ~{keys[7],keys[5],keys[1]|keys[2],keys[0]|keys[3],dirs};
    endfunction
    assign mystic_p12={p2,in0_p1[7:0]};
    assign mystic_p34={player(p4_keys,p4_dirs),player(p3_keys,p3_dirs)};
    assign mystic_in0={4'hf,~p4_keys[6],~p3_keys[6],in0_p1[9],in0_p1[8]};
    // Bit3 must stay0 (the original game waits if it is1). Main supplies DO/READY.
    assign in1=mystic ? {1'b1,~dips[3],~dips[2],dips[4],1'b0,in0_p1[11],2'b11} : gaia_in1;
endmodule
`default_nettype wire
