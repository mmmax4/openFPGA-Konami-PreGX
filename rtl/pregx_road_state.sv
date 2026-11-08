// K053250 CPU RAM and two DMA pages in external mutable memory. Semantics
// reference: frozen MAME0.289 k053250.cpp (BSD-3-Clause, Olivier Galibert).
// 0..1fff CPU words; 2000..27ff/2800..2fff DMA pages. The selected page is
// the NEXT DMA destination, so display intentionally lags one DMA.
// mem_ack must mean the read is returned or the write is COMMITTED. A write
// queue's early acceptance ACK must never be connected directly to this port.
`default_nettype none
module pregx_road_state (
    input logic clk,reset,frame_tick,
    input logic reg4_dma,
    output logic initialized,dma_busy,
    input logic cpu_req,cpu_we,
    input logic [12:0] cpu_addr,
    input logic [1:0] cpu_be,
    input logic [15:0] cpu_wdata,
    output logic cpu_ack,output logic [15:0] cpu_q,
    // Snapshot begin is legal only at snapshot_allowed. Keep snapshot_active
    // through the last returned word; it prevents a DMA changing that picture.
    input logic snapshot_begin,snapshot_active,snapshot_req,
    input logic [10:0] snapshot_addr,
    output wire snapshot_allowed,
    output logic snapshot_ack,output logic [15:0] snapshot_q,
    output logic page,
    output logic mem_req,mem_we,
    output logic [13:0] mem_addr,
    output logic [1:0] mem_be,
    output logic [15:0] mem_wdata,
    input logic mem_ack,input logic [15:0] mem_q
);
    typedef enum logic [3:0] {CLEAR_WAIT,CLEAR_GAP,IDLE,CPU_WAIT,CPU_GAP,
        DMA_READ,DMA_READ_GAP,DMA_WRITE,DMA_WRITE_GAP,SNAP_WAIT,SNAP_GAP} state_t;
    state_t state;
    logic r4_prev,limited,pending,cpu_hold,snapshot_hold,snapshot_page;
    logic [13:0] clear_addr;
    logic [10:0] index;
    logic [15:0] transfer_data;
    logic [12:0] cpu_tag;
    logic cpu_write_tag;
    logic [1:0] cpu_be_tag;
    logic [15:0] cpu_data_tag;
    logic [10:0] snapshot_tag;
    assign snapshot_allowed=initialized && !dma_busy && state==IDLE;
    always_ff @(posedge clk) begin
        cpu_ack<=1'b0;snapshot_ack<=1'b0;r4_prev<=reg4_dma;
        if(reset) begin
            state<=CLEAR_WAIT;clear_addr<=14'd0;initialized<=1'b0;
            dma_busy<=1'b1;limited<=1'b0;pending<=1'b0;page<=1'b0;
            cpu_hold<=1'b0;snapshot_hold<=1'b0;snapshot_page<=1'b0;
            mem_req<=1'b0;mem_we<=1'b0;mem_addr<=14'd0;
            mem_be<=2'b11;mem_wdata<=16'd0;index<=11'd0;
        end else begin
            if(!cpu_req)cpu_hold<=1'b0;
            if(!snapshot_req)snapshot_hold<=1'b0;
            if(frame_tick)limited<=1'b0;
            if(initialized && r4_prev && !reg4_dma && (!limited || frame_tick)) begin
                pending<=1'b1;dma_busy<=1'b1;
            end
            if(snapshot_begin && snapshot_allowed)snapshot_page<=page;
            case(state)
                CLEAR_WAIT: begin
                    mem_req<=1'b1;mem_we<=1'b1;mem_addr<=clear_addr;
                    mem_be<=2'b11;mem_wdata<=16'd0;
                    if(mem_req && mem_ack)begin mem_req<=1'b0;state<=CLEAR_GAP;end
                end
                CLEAR_GAP: begin
                    if(clear_addr==14'h2fff)begin
                        initialized<=1'b1;dma_busy<=1'b0;state<=IDLE;
                    end else begin clear_addr<=clear_addr+14'd1;state<=CLEAR_WAIT;end
                end
                IDLE: begin
                    if(pending && !snapshot_active)begin
                        pending<=1'b0;limited<=1'b1;index<=11'd0;state<=DMA_READ;
                    end else if(snapshot_req && !snapshot_hold)begin
                        snapshot_tag<=snapshot_addr;
                        mem_addr<={2'b10,snapshot_page,snapshot_addr};
                        mem_we<=1'b0;mem_be<=2'b11;mem_req<=1'b1;state<=SNAP_WAIT;
                    end else if(cpu_req && !cpu_hold)begin
                        cpu_tag<=cpu_addr;cpu_write_tag<=cpu_we;
                        cpu_be_tag<=cpu_be;cpu_data_tag<=cpu_wdata;
                        mem_addr<={1'b0,cpu_addr};mem_we<=cpu_we;
                        mem_be<=cpu_be;mem_wdata<=cpu_wdata;mem_req<=1'b1;state<=CPU_WAIT;
                    end
                end
                CPU_WAIT: if(mem_ack)begin
                    mem_req<=1'b0;cpu_q<=mem_q;cpu_hold<=1'b1;
                    cpu_ack<=cpu_req && cpu_addr==cpu_tag && cpu_we==cpu_write_tag &&
                        (!cpu_write_tag || (cpu_be==cpu_be_tag && cpu_wdata==cpu_data_tag));
                    state<=CPU_GAP;
                end
                CPU_GAP: state<=IDLE;
                DMA_READ: begin
                    mem_req<=1'b1;mem_we<=1'b0;mem_addr<={3'd0,index};mem_be<=2'b11;
                    if(mem_req && mem_ack)begin transfer_data<=mem_q;mem_req<=1'b0;state<=DMA_READ_GAP;end
                end
                DMA_READ_GAP: state<=DMA_WRITE;
                DMA_WRITE: begin
                    mem_req<=1'b1;mem_we<=1'b1;mem_addr<={2'b10,page,index};
                    mem_be<=2'b11;mem_wdata<=transfer_data;
                    if(mem_req && mem_ack)begin mem_req<=1'b0;state<=DMA_WRITE_GAP;end
                end
                DMA_WRITE_GAP: begin
                    if(index==11'h7ff)begin page<=~page;dma_busy<=1'b0;state<=IDLE;end
                    else begin index<=index+11'd1;state<=DMA_READ;end
                end
                SNAP_WAIT: if(mem_ack)begin
                    mem_req<=1'b0;snapshot_q<=mem_q;snapshot_hold<=1'b1;
                    snapshot_ack<=snapshot_req && snapshot_addr==snapshot_tag;state<=SNAP_GAP;
                end
                SNAP_GAP: state<=IDLE;
                default:begin mem_req<=1'b0;state<=IDLE;end
            endcase
        end
    end
endmodule
`default_nettype wire
