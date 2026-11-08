// Road-state transaction adapter to the existing Pocket psram_port. Preserve
// its loader-compatible early write ACK, but return only w_commit to the road
// state owner. The uncached r0 path supplies mutable CPU/DMA/snapshot reads.
`default_nettype none
module pregx_road_psram_bridge (
    input logic clk,reset,
    input logic req,we,input logic [13:0] addr,
    input logic [1:0] be,input logic [15:0] wdata,
    output logic ack,output logic [15:0] q,
    output logic r_req,output logic [22:0] r_addr,
    input logic r_ack,input logic [15:0] r_q,
    output logic w_req,output logic [22:0] w_addr,
    output logic [1:0] w_be,output logic [15:0] w_data,
    input logic w_accept,w_commit
);
    typedef enum logic [2:0] {IDLE,READ_WAIT,WRITE_ACCEPT,WRITE_COMMIT,HOLD} state_t;
    state_t state;
    logic [13:0] tag;
    logic [1:0] be_tag;
    logic [15:0] data_tag;
    always_ff @(posedge clk) begin
        ack<=1'b0;
        if(reset)begin
            state<=IDLE;r_req<=1'b0;w_req<=1'b0;
            r_addr<=23'd0;w_addr<=23'd0;w_be<=2'd0;w_data<=16'd0;
        end else case(state)
            IDLE: if(req)begin
                tag<=addr;be_tag<=be;data_tag<=wdata;
                if(we)begin
                    w_req<=1'b1;w_addr<={9'd0,addr};w_be<=be;w_data<=wdata;
                    state<=WRITE_ACCEPT;
                end else begin
                    r_req<=1'b1;r_addr<={9'd0,addr};state<=READ_WAIT;
                end
            end
            READ_WAIT: if(r_ack)begin
                r_req<=1'b0;q<=r_q;
                ack<=req && !we && addr==tag;state<=HOLD;
            end
            WRITE_ACCEPT: if(w_accept)begin w_req<=1'b0;state<=WRITE_COMMIT;end
            WRITE_COMMIT: if(w_commit)begin
                ack<=req && we && addr==tag && be==be_tag && wdata==data_tag;
                state<=HOLD;
            end
            HOLD: if(!req)state<=IDLE;
            default:begin r_req<=1'b0;w_req<=1'b0;state<=IDLE;end
        endcase
    end
endmodule
`default_nettype wire
