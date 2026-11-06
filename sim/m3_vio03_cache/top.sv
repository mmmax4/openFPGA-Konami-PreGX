`default_nettype none
module m3_vio03_cache_top(
 input wire clk,reset,enable,c_req,input wire [19:0] c_addr,
 output wire c_ack,output wire [63:0] c_q,
 output wire m_req,output wire [19:0] m_addr,
 input wire m_ack,input wire [63:0] m_q,
 output wire [2:0] diagnostic_state,
 output wire [5:0] diagnostic_valid_count
);
 pregx_vio_sprite_cache dut(.clk(clk),.reset(reset),.enable(enable),
  .c_req(c_req),.c_addr(c_addr),.c_ack(c_ack),.c_q(c_q),
  .m_req(m_req),.m_addr(m_addr),.m_ack(m_ack),.m_q(m_q));
 // Passive observations; all transactions use the public interface above.
 assign diagnostic_state=dut.state;
 assign diagnostic_valid_count=6'($countones(dut.valid));
endmodule
`default_nettype wire
