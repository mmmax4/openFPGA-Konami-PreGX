// Configuration-owned APF autosave requester. Full RBF reload separates games.
// Keep pending writes until successful completion; later writes need a new save.
`default_nettype none
module pregx_nv_save #(
    parameter int unsigned SETTLE_CYCLES=148500000,
    parameter int unsigned BOOT_CYCLES=371250000
)(
    input wire clk,loaded,run,dirty_toggle,inmenu,
    input wire ack,done,input wire [2:0] error,
    output logic request
);
    typedef enum logic [1:0] {IDLE,WAIT_ACK,WAIT_DONE} state_t;
    state_t state;
    logic dirty_d,inmenu_d,pending,again,done_armed;
    logic [27:0] timer;
    logic [28:0] boot_timer;
    wire dirty_event=(dirty_toggle!=dirty_d);
    initial begin
        state=IDLE;request=0;dirty_d=0;inmenu_d=0;pending=0;again=0;
        done_armed=0;timer=0;boot_timer=0;
    end
    always_ff @(posedge clk) begin
        dirty_d<=dirty_toggle;inmenu_d<=inmenu;
        if(loaded && run && boot_timer!=29'(BOOT_CYCLES))boot_timer<=boot_timer+29'd1;
        if(timer!=28'(SETTLE_CYCLES))timer<=timer+28'd1;
        case(state)
            IDLE: begin
                request<=0;
                if(loaded && run && ((pending &&
                    (timer==28'(SETTLE_CYCLES)||(inmenu&&!inmenu_d))) ||
                    boot_timer==29'(BOOT_CYCLES-1))) begin
                    request<=1;state<=WAIT_ACK;again<=0;
                    // Parser done is sticky until a new command starts. Wait
                    // for its low phase before accepting the next high phase.
                    done_armed<=!done;
                end
            end
            WAIT_ACK: begin
                if(!done)done_armed<=1;
                if(ack)begin request<=0;state<=WAIT_DONE;end
            end
            WAIT_DONE: if(!done)done_armed<=1;
            default: begin request<=0;state<=IDLE;end
        endcase
        // The host may finish directly without first publishing busy/ack.
        if(state!=IDLE && done && done_armed)begin
            request<=0;state<=IDLE;
            if(error!=0)begin pending<=1;timer<=0;end
            else pending<=again||dirty_event;
        end
        // Last assignment wins, including simultaneous launch/completion.
        if(dirty_event)begin pending<=1;again<=1;timer<=0;end
    end
endmodule
`default_nettype wire
