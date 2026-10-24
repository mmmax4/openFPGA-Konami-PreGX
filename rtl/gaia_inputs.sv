// Gaiapolis cabinet inputs. Layout: pinned MAME dadandrn ports, not Mystic.
// Buttons are logical APF keys after OS remapping; selectors are momentary.
`default_nettype none
module gaia_inputs (
    input wire [7:0] p1_keys, p2_keys, // {Start,Select,R,L,Y,X,B,A}
    input wire [3:0] p1_dirs, p2_dirs, // {Down,Up,Right,Left}
    input wire test_manual,
    input wire [3:0] test_select, service_select,
    input wire [1:0] dips,            // bit0 Mono, bit1 Flip On; default 0
    output wire [15:0] in0_p1,
    output wire [7:0] in1, p2
);
    function automatic cabinet_button(input [3:0] sel, input [7:0] keys);
        case (sel)
            4'd1: cabinet_button=keys[0];
            4'd2: cabinet_button=keys[1];
            4'd3: cabinet_button=keys[2];
            4'd4: cabinet_button=keys[3];
            4'd5: cabinet_button=keys[4];
            4'd6: cabinet_button=keys[5];
            4'd7: cabinet_button=keys[6];
            4'd8: cabinet_button=keys[7];
            default: cabinet_button=1'b0;
        endcase
    endfunction
    wire test_sw = test_manual | cabinet_button(test_select,p1_keys);
    wire service_sw = cabinet_button(service_select,p1_keys);
    assign in0_p1 = ~{2'b00,1'b0,service_sw,test_sw,1'b0,p2_keys[6],p1_keys[6],
        p1_keys[7],p1_keys[5],p1_keys[1]|p1_keys[2],p1_keys[0]|p1_keys[3],p1_dirs};
    assign p2 = ~{p2_keys[7],p2_keys[5],p2_keys[1]|p2_keys[2],p2_keys[0]|p2_keys[3],p2_dirs};
    // DO/READY placeholders are replaced by gaia_main's real EEPROM pins.
    assign in1 = {2'b11,~dips[1],dips[0],~test_sw,1'b0,2'b11};
endmodule
`default_nettype wire
