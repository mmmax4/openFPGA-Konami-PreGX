//------------------------------------------------------------------------------
// Gaiapolis main board: 68000 @ 16 MHz and everything on its bus.
//
// Address decode follows docs/hardware.md section 3 (gaiapols_map). The CPU
// is TG68K.C, paced by a token bucket the way the S.T.U.N. Runner core paces
// its 68010 -- STEP_COST_BUS/STEP_COST_INT/STEP_GAIN set the step rate; the
// values are calibrated against MAME's frame timing (docs/hardware.md
// section 10, "68000 pacing").
//
// What lives here: work RAM, K056832 tile RAM (all 16 pages, one visible
// through the banked window), palette, sprite RAM through the K053247's
// scattered window, the ROZ control block and line RAM, and the register
// files of every video chip, exported to the renderers. Renderers read the
// memories through their own ports.
//
// All five ROM-readback windows are real. The self-test checksums every
// graphics ROM through them, and the full-system bench showed what a stub
// costs: with 440000/450000 returning 0 the DATA ROM item failed and the test
// re-ran it forever. They share the renderers' ROM ports through arbiters
// that give the renderer priority.
//   440000  K056832 mw_rom_word_r: bank regs[0x1a]|regs[0x1b]<<16 (mod 256)
//           selects 2048 four-byte groups; a word is one half of a group.
//           regsb[2] bit 3 asks for the fifth plane, which this ROM set does
//           not populate, so that reads 0.
//   450000  K055673 rom_word_r (4bpp): a 16-bit little-endian view of the
//           sprite ROM at the offset in k053246 regs 6/7/4.
//------------------------------------------------------------------------------
`default_nettype none

module gaia_main #(
    parameter string HEXDIR = "rtl/data",
    parameter int STEP_COST_BUS = 16, // tokens per kernel step that runs a bus cycle: 4 clocks, as the 68000's
    parameter int STEP_COST_INT = 8,  // tokens per internal step: 2 clocks
    parameter int STEP_GAIN = 4       // tokens per cen_16m: 4 tokens = one 16 MHz clock
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        pause,
    input  logic        violent,       // EAC profile, stable through reset/run
    input  logic        mystic,        // stable profile from reset to unload
    input  logic        metam,
    input  logic        lvc_cpu_stall,
    output logic        lvc_req,lvc_we,
    output logic[12:0]   lvc_addr,
    output logic[1:0]    lvc_be,
    output logic[15:0]   lvc_wdata,
    input  logic        lvc_ack,input logic[15:0]lvc_q,
    output logic[7:0]    k50regs[8],
    output logic        lvc_rom_req,output logic[14:0]lvc_rom_addr,
    input logic         lvc_rom_ack,input logic[63:0]lvc_rom_q,
    input  logic        raster_start,
    input  logic [8:0]  raster_line,
    input  logic [15:0] mystic_p12, mystic_p34,
    input  logic [7:0]  mystic_in0,
    input  logic        cen_16m,

    // program ROM, 3 MB
    output logic        rom_req,
    output logic [22:1] rom_addr,
    input  logic        rom_ack,
    input  logic [15:0] rom_q,

    // ROZ ROMs for the readback windows (shared with the renderer's ports)
    output logic        map_req,
    output logic [19:0] map_addr,
    input  logic        map_ack,
    input  logic [15:0] map_q,
    output logic        chr_req,
    output logic [20:0] chr_addr,
    input  logic        chr_ack,
    input  logic [15:0] chr_q,
    // tile ROM (K056832 readback) and sprite ROM (K055673 readback)
    output logic        trom_req,
    output logic [19:0] trom_addr,
    input  logic        trom_ack,
    input  logic [31:0] trom_q,
    input  logic [7:0] trom_fifth,
    output logic        srom_req,
    output logic [19:0] srom_addr,
    input  logic        srom_ack,
    input  logic [63:0] srom_q,
    input  logic [15:0] srom_fifth,

    // vblank interrupt (IRQ5, held until acknowledged)
    input  logic        vblank_rise,

    // inputs, active low as the board sees them. in1[1:0] are replaced by the
    // EEPROM's DO and READY lines on the way in (dddeeprom_r).
    input  logic [15:0] in0_p1,
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic  [7:0] in1,
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic  [7:0] p2,

    // ER5911 serial EEPROM
    output logic        eep_di,
    output logic        eep_cs,
    output logic        eep_clk,
    input  logic        eep_do,
    input  logic        eep_ready,

    // K054321 main side: byte registers at word offsets 0..15
    output logic        snd_wr,
    output logic        snd_rd,
    output logic  [3:0] snd_off,
    output logic  [7:0] snd_wdata,
    input  logic  [7:0] snd_rdata,
    output logic        snd_irq,        // 6E0000 write: Z80 IRQ0

    // K054000 collision chip: byte registers at word offsets 0..31
    output logic        col_wr,
    output logic        col_rd,
    output logic  [4:0] col_off,
    output logic  [7:0] col_wdata,
    input  logic  [7:0] col_rdata,

    // video chip register files
    output logic [15:0] k56regs  [32],
    output logic [15:0] k56regsb [4],
    output logic  [7:0] k55regs  [48],
    output logic [15:0] k38regs  [16],
    output logic [15:0] rozctrl  [16],
    output logic [15:0] rozclip  [2],
    output logic        roz_enable,
    output logic  [1:0] roz_rombank,
    output logic  [7:0] k46regs  [8],
    output logic [15:0] k47regs  [8],

    // memories the renderers read
    // tile RAM lives outside (the Pocket's SRAM); the CPU window's accesses
    // go out as request/ack, writes byte-enabled, and the kernel waits for them
    output logic        vc_req,
    output logic        vc_we,
    output logic [15:0] vc_addr,
    output logic  [1:0] vc_be,
    output logic [15:0] vc_wdata,
    input  logic        vc_ack,
    input  logic [15:0] vc_q,
    input  logic [10:0] sram_raddr,
    output logic [15:0] sram_q,
    input  logic [10:0] pal_raddr,
    output logic [23:0] pal_q,

    // diagnostics
    output logic [23:0] dbg_addr,
    output logic [15:0] dbg_data,       // data_in of the last completed read
    output logic  [1:0] dbg_busstate,
    output logic        dbg_step,
    output logic        dbg_irq5,
    output logic        dbg_irq2, dbg_irq4, dbg_rb_oob,
    output logic        dbg_spr_we           // a CPU write into the sprite RAM (benches)
);
    // Runtime profile is held through the full reset/reload window. Track it
    // continuously, including reset, and keep the high-fanout decoders local.
    (* preserve, dont_merge *) logic board_mystic, board_violent, board_metam, board_rng, board_readback;
    always_ff @(posedge clk) begin
        board_mystic <= mystic; board_violent <= violent;board_metam<=metam;board_rng<=violent||metam;
        board_readback <= mystic || violent || metam;
    end

    logic trom_req_g, srom_req_g;
    logic [18:0] trom_addr_g;
    logic [19:0] srom_addr_g;
    logic rb_req, rb_sprite, rb_ack;
    logic [15:0] rb_data;
    logic mt_req, ms_req;
    logic [19:0] mt_addr;
    logic [19:0] ms_addr;
    // Reset clears both producers; the profile-stable CPU dispatch sets only
    // its own producer. Combine their registered valid bits without a late
    // profile mux on the shared memory request; payload selection is unchanged.
    assign trom_req = mt_req | trom_req_g;
    assign trom_addr = board_readback ? mt_addr : {1'b0,trom_addr_g};
    assign srom_req = ms_req | srom_req_g;
    assign srom_addr = board_readback ? ms_addr : srom_addr_g;
    mystic_rom_readback u_rb (
        .clk(clk), .reset(reset), .violent(board_violent), .metam(board_metam), .req(rb_req), .sprite(rb_sprite),
        .offset(A[13:1]), .tile_bank({k56regs[27],k56regs[26]}),
        .tile_plane5(k56regsb[2][3]), .sprite_word({k46regs[6],k46regs[7],k46regs[4]}),
        .ack(rb_ack), .data(rb_data), .out_of_range(dbg_rb_oob),
        .tile_req(mt_req), .tile_addr(mt_addr), .tile_ack(trom_ack), .tile_q(trom_q), .tile_fifth(trom_fifth),
        .spr_req(ms_req), .spr_addr(ms_addr), .spr_ack(srom_ack), .spr_q(srom_q), .spr_fifth(srom_fifth)
    );
    // ------------------------------------------------------------ TG68K
    logic        clkena;
    logic [15:0] data_in;
    logic  [2:0] ipl_n;
    /* verilator lint_off UNUSEDSIGNAL */
    logic [31:0] addr_out;   // a 68000 has 24 address lines and no A0
    /* verilator lint_on UNUSEDSIGNAL */
    logic [15:0] data_write;
    logic        nWr, nUDS, nLDS;
    logic  [1:0] busstate;
    logic        nResetOut;
    logic [31:0] regin_out, vbr_out;
    logic  [3:0] cacr_out;
    logic  [2:0] fc;
    logic        longword, clr_berr, skipFetch;
    logic  [2:0] step_gap;

    TG68KdotC_Kernel cpu (
        .clk            ( clk ),
        .nReset         ( ~reset ),
        .clkena_in      ( clkena ),
        .data_in        ( data_in ),
        .IPL            ( ipl_n ),
        .IPL_autovector ( 1'b1 ),
        .berr           ( 1'b0 ),
        .CPU            ( 2'b00 ),          // 68000
        .addr_out       ( addr_out ),
        .data_write     ( data_write ),
        .nWr            ( nWr ),
        .nUDS           ( nUDS ),
        .nLDS           ( nLDS ),
        .busstate       ( busstate ),
        .longword       ( longword ),
        .nResetOut      ( nResetOut ),
        .FC             ( fc ),
        .clr_berr       ( clr_berr ),
        .skipFetch      ( skipFetch ),
        .regin_out      ( regin_out ),
        .CACR_out       ( cacr_out ),
        .VBR_out        ( vbr_out )
    );

    wire [23:1] A_cpu     = addr_out[23:1];
    wire        is_wr = (busstate == 2'b11);
    wire  [5:0] step_cost = (busstate == 2'b01 || skipFetch) ? 6'(STEP_COST_INT) : 6'(STEP_COST_BUS);
    wire        cuds   = ~nUDS;             // D15:8
    wire        clds   = ~nLDS;             // D7:0
    assign dbg_addr     = {addr_out[23:1], 1'b0};
    assign dbg_data     = data_in;
    assign dbg_busstate = busstate;

    // K055550 masters the same decoded memory ports while the CPU is held.
    logic k550_busy, k550_go, k550_we, k550_done;
    logic k550_owned, k550_owned_d;
    logic [23:1] k550_a;
    logic [1:0] k550_be;
    logic [15:0] k550_wd, k550_q, k550_rd;
    logic e_rom_pend, e_vr_pend, e_vw_pend;
    // Registered ownership removes busy/start from the whole address/data
    // decode path. CPU command posting already enforces the three-cycle gap;
    // the engine waits two clocks before m_go. Keep CPU held through the
    // final ownership cycle so its address is restored before the next step.
    always_ff @(posedge clk) begin
        if (reset || !board_violent) begin k550_owned <= 1'b0; k550_owned_d <= 1'b0; end
        else begin k550_owned <= k550_busy; k550_owned_d <= k550_owned; end
    end
    // Register the shared bus before decode. Both masters already supply a
    // settling interval: CPU step_gap and engine S_A1/S_A2. The extra release
    // hold above restores the CPU bus before allowing its next transaction.
    logic [23:1] A;
    logic uds, lds;
    logic [15:0] wdat;
    wire [23:1] shared_a = k550_owned ? k550_a : A_cpu;
    wire [47:0] mmio_k55;
    wire [31:0] mmio_k56;
    wire [3:0] mmio_k56b;
    wire mmio_k000, mmio_local_other, mmio_vram;
    wire [26:0] mmio_board;
    wire sel_lvc_ram,sel_lvc_reg,sel_lvc_rom;
    logic[2:0]lvc_rom_sel;
    // Destination and payload are sampled from the SAME raw master bus.
    // CPU step_gap and the engine S_A1/S_A2 interval already settle that bus.
    // This moves decode before A, without adding a write/ACK cycle.
    pregx_mmio_targets mmio_targets(
        .clk(clk),.mystic(board_mystic),.violent(board_violent),.metam(board_metam),.a(shared_a),
        .k55(mmio_k55),.k56(mmio_k56),.k56b(mmio_k56b),
        .k000(mmio_k000),.local_other(mmio_local_other),.vram(mmio_vram),
        .board(mmio_board),.lvc_ram(sel_lvc_ram),.lvc_reg(sel_lvc_reg),.lvc_rom(sel_lvc_rom)
    );
    always_ff @(posedge clk) begin
        A <= shared_a;
        uds <= k550_owned ? k550_be[1] : cuds;
        lds <= k550_owned ? k550_be[0] : clds;
        wdat <= k550_owned ? k550_wd : data_write;
    end

    // --------------------------------------------------------- decode
    wire sel_rom    = mmio_board[0];                       // 000000-2fffff
    wire sel_sprwin = mmio_board[1];                      // 400000-40ffff
    wire sel_vram   = mmio_board[2];           // 410000-413fff (mirror at 412000)
    wire sel_pal    = mmio_board[3];          // 420000-421fff
    wire sel_k46    = mmio_board[4];                 // 430000-430007
    wire sel_tmrb   = mmio_board[5];          // 440000-441fff  tile ROM readback
    wire sel_sprrb  = mmio_board[6];                  // 450000-45000f  sprite ROM readback
    wire sel_k47    = mmio_board[7];                  // 450010-45001f
    wire sel_rozct  = mmio_board[8];                  // 460000-46001f
    wire sel_rozli  = mmio_board[9];                    // 470000-470fff
    wire sel_clip   = mmio_board[10];                 // 484000-484003
    wire sel_k252   = mmio_board[11];                  // 486000-48601f
    wire sel_k321   = mmio_board[12];                  // 48a000-48a01f
    wire sel_k338   = mmio_board[13];                  // 48c000-48c01f
    wire sel_in0    = mmio_board[14];                 // 48e000
    wire sel_in1    = mmio_board[15];                 // 48e020
    wire sel_wram   = mmio_board[16];                      // 600000-60ffff
    wire sel_k000   = mmio_board[17];                  // 660000-66003f
    wire sel_eep    = mmio_board[18];                 // 6a0000
    wire sel_rozen  = mmio_board[19];                 // 6c0000
    wire sel_sndirq = mmio_board[20];                 // 6e0000
    wire sel_rb0    = mmio_board[21];                  // 800000-87ffff
    wire sel_rb1    = mmio_board[22];                  // a00000-a7ffff
    wire sel_rb2    = mmio_board[23];                     // c00000-dfffff
    /* verilator lint_off UNUSEDSIGNAL */
    wire sel_wdog   = board_rng ? (A[23:1] == 23'h13e000) : (board_mystic ? (A[23:1] == 23'h249000) : (A[23:1]  == 23'h700000));                 // e00000: decoded, deliberately ignored
    /* verilator lint_on UNUSEDSIGNAL */

    wire sel_p12 = mmio_board[24];
    wire sel_p34 = mmio_board[25];
    wire sel_k550 = mmio_board[26];

    // -------------------------------------------------------- memories
    // work RAM 32K x 16, byte lanes
    logic [1:0][7:0] wram [32768];
    logic [15:0] wram_q;
    // K056832 tile RAM, 16 pages x 4096 words; CPU sees the selected page
    // palette 2048 x {word0, word1}; word0 = 00RR, word1 = GGBB
    // palette: two 16-bit words per entry (00RR, GGBB), each a byte-enabled
    // RAM in Quartus's template form so it infers rather than becoming 64K
    // registers; the CPU and the mixer each read a copy
    logic [1:0][7:0] pal0 [2048];
    logic [1:0][7:0] pal1 [2048];
    logic [1:0][15:0] pal_cpu_q, pal_rd_q;
    logic        pal_we;
    logic [10:0] pal_waddr;
    logic  [1:0] pal_wsel;             // which word, {word1, word0}
    logic  [1:0] pal_wbe;              // {uds, lds}
    logic [15:0] pal_wdata;
    always_ff @(posedge clk) begin
        if (pal_we && pal_wsel[0]) begin
            if (pal_wbe[1]) pal0[pal_waddr][1] <= pal_wdata[15:8];
            if (pal_wbe[0]) pal0[pal_waddr][0] <= pal_wdata[7:0];
        end
        pal_cpu_q[0] <= pal0[A[12:2]];
        pal_rd_q[0]  <= pal0[pal_raddr];
    end
    always_ff @(posedge clk) begin
        if (pal_we && pal_wsel[1]) begin
            if (pal_wbe[1]) pal1[pal_waddr][1] <= pal_wdata[15:8];
            if (pal_wbe[0]) pal1[pal_waddr][0] <= pal_wdata[7:0];
        end
        pal_cpu_q[1] <= pal1[A[12:2]];
        pal_rd_q[1]  <= pal1[pal_raddr];
    end
    // sprite RAM 0x800 words behind the scattered window, plus the plain
    // 32K x 16 the rest of the 64 KB window lands in (the board has it, and
    // the self-test writes and reads all of it)
    logic [15:0] sram [2048] /*verilator public_flat_rd*/;
    logic [15:0] sram_cpu_q;
    logic [15:0] sshadow [32768];
    logic [15:0] sshadow_q;
    // ROZ line RAM
    logic [15:0] rozli [2048];
    logic [15:0] rozli_q;
    // K053252 bytes (kept so reads return what was written)
    logic  [7:0] k252 [16];

    // tile-RAM page select: regs[0x19] bits {4:3, 1:0}, or the external
    // linescroll page when regs[0] bit 1 is set (not fitted on this board)
    wire [3:0] vram_page = {k56regs[25][4:3], k56regs[25][1:0]};
    wire       vram_ext  = k56regs[0][1];
    wire [15:0] vram_cpu_addr = {vram_page, A[12:1]};

    // scattered sprite window: word w of the chip lives at
    // 400000 + ((w & 0x7f8) << 5) + (w & 7) * 2; the rest is shadow RAM.
    // MAME's test is (word offset & 0x78) == 0, i.e. A[7:4] all clear --
    // four bits, not three. With A[7] left out, two CPU addresses aliased
    // onto one chip word and the self-test marked both sprite-window RAMs bad.
    wire        spr_hit  = board_rng ? (A[15:12] == 4'd0) : (A[7:4] == 4'd0);
    wire [10:0] spr_word = board_rng ? A[11:1] : {A[15:8], A[3:1]};

    always_ff @(posedge clk) begin
        wram_q      <= wram[A[15:1]];
        sram_cpu_q  <= sram[spr_word];
        sshadow_q   <= sshadow[A[15:1]];
        sram_q      <= sram[sram_raddr];
        rozli_q     <= rozli[A[11:1]];
    end
    // xRGB888 across the two words: word0 = 00RR, word1 = GGBB
    assign pal_q = {pal_rd_q[0][7:0], pal_rd_q[1]};

    // ------------------------------------------------- bus sequencer
    typedef enum logic [3:0] {
        B_IDLE, B_RAM_RD, B_WAIT_ROM, B_WAIT_MAP0, B_WAIT_MAP0B, B_WAIT_MAP1, B_WAIT_CHR,
        B_WAIT_TROM, B_WAIT_SROM, B_WAIT_VRAM, B_WAIT_VRAMW, B_WAIT_MRB, B_WAIT_LVC, B_WAIT_LVCW, B_WAIT_LVCROM
    } bst_t;
    bst_t bst;
    logic [5:0]  tok;
    logic        irq5_pend;
    logic        irq2_pend, irq4_pend, irq6_pend;
    logic [15:0] rd_mux;
    logic [7:0]  rb_hi;
    logic [15:0] in1_word;

    assign ipl_n = board_rng ? (irq6_pend ? 3'b001 : irq5_pend ? 3'b010 : 3'b111) : board_mystic ? (irq4_pend ? 3'b011 : irq2_pend ? 3'b101 : 3'b111) :
                           (irq5_pend ? 3'b010 : 3'b111);    // level 5

    // K056832 readback: 32-bit group index = bank * 2048 + (offset >> 1).
    // Only the low byte of the bank and the low 22 bits of the sprite word
    // index can address the ROMs fitted; the rest of each register is ignored.
    /* verilator lint_off UNUSEDSIGNAL */
    wire [23:0] tile_bank32 = {k56regs[27][7:0], k56regs[26]};      // regs[0x1b]<<16 | regs[0x1a]
    wire  [7:0] tile_bank   = tile_bank32[7:0];                    // mod 256 banks
    wire [18:0] trom_group  = {tile_bank, A[12:2]};
    wire        tile_plane5 = k56regsb[2][3];
    // K055673 readback: 16-bit word index from k053246 regs 6/7/4
    wire [23:0] spr_romofs  = {k46regs[6], k46regs[7], k46regs[4]};
    wire [23:0] spr_widx    = {spr_romofs[23:2], 2'b00} + (A[3] ? 24'd0 : 24'd2) + {22'd0, A[2:1]};
    logic [1:0] srom_sel;
    /* verilator lint_on UNUSEDSIGNAL */
    assign dbg_irq5 = irq5_pend;
    assign dbg_irq2 = irq2_pend;
    assign dbg_irq4 = irq4_pend;
    // MAME's dddeeprom_r: an access that includes the high byte returns IN1
    // there with a zero low byte; only a low-byte access reads P2
    assign in1_word = board_readback ? (lds ? {8'd0,in1[7:2],eep_ready,eep_do} : 16'd0) :
                                   {in1[7:2],eep_ready,eep_do,uds ? 8'h00 : p2};

    // Sources are mutually exclusive for every address/profile combination
    // (m3-decode/decode02: all 33,554,432 cases). Keep the read path parallel
    // rather than giving the protection bus a fourteen-level priority chain.
    always_comb begin
        rd_mux = ({16{sel_wram}}   & wram_q)
               | ({16{sel_pal}}    & (A[1] ? pal_cpu_q[1] : pal_cpu_q[0]))
               | ({16{sel_sprwin}} & (spr_hit ? sram_cpu_q : sshadow_q))
               | ({16{sel_rozli}}  & rozli_q)
               | ({16{sel_rozct}}  & rozctrl[A[4:1]])
               | ({16{sel_k550}}   & k550_q)
               | ({16{sel_k252}}   & {8'h00, k252[A[4:1]]})
               | ({16{sel_in0}}    & (board_readback ? {8'd0,mystic_in0} : in0_p1))
               | ({16{sel_p12}}    & mystic_p12)
               | ({16{sel_p34}}    & mystic_p34)
               | ({16{sel_in1}}    & in1_word)
               | ({16{sel_k321}}   & (board_readback ? (lds ? {8'd0,snd_rdata} : 16'd0) : {snd_rdata,8'h00}))
               | ({16{sel_k000}}   & {8'h00, col_rdata})
               | ({16{sel_lvc_reg}} & {8'd0,k50regs[A[3:1]]});
        // sel_vram answers zero here, as before (external linescroll mode).
    end

    wire cpu_step = (!board_metam || !lvc_cpu_stall) && !pause && !k550_owned && !k550_owned_d && tok >= 6'(step_cost) && !clkena && step_gap==3'd0;
    wire cpu_wr = bst==B_IDLE && cpu_step && fc!=3'b111 && !(busstate==2'b01 || skipFetch) && is_wr;
    wire cpu_local_read = bst==B_IDLE && cpu_step && fc!=3'b111 && !(busstate==2'b01 || skipFetch) && !is_wr;
    wire engine_wr = board_violent && k550_go && k550_we;
    k055550 #(.HEXDIR(HEXDIR)) u_k550 (
        .clk(clk),.reset(reset || !board_violent),.wr(cpu_wr && sel_k550),
        .idx(A[5:1]),.be({uds,lds}),.wdata(wdat),.rd_idx(A[5:1]),.rd_q(k550_q),.busy(k550_busy),
        .m_go(k550_go),.m_we(k550_we),.m_a(k550_a),.m_be(k550_be),.m_wd(k550_wd),.m_done(k550_done),.m_rd(k550_rd)
    );
    always_ff @(posedge clk) begin
        k550_done <= 1'b0;
        clkena   <= 1'b0;
        dbg_step <= 1'b0;
        dbg_spr_we <= 1'b0;
        snd_wr <= 1'b0; snd_rd <= 1'b0; snd_irq <= 1'b0; pal_we <= 1'b0;
        col_wr <= 1'b0; col_rd <= 1'b0;
        step_gap <= {step_gap[1:0], clkena};

        if (reset) begin
            lvc_req<=1'b0;lvc_we<=1'b0;lvc_rom_req<=1'b0;
            irq6_pend <= 1'b0; e_rom_pend<=1'b0; e_vr_pend<=1'b0; e_vw_pend<=1'b0;
            bst <= B_IDLE; tok <= '0; step_gap <= '0; irq5_pend <= 1'b0; vc_req <= 1'b0;
            irq2_pend <= 1'b0; irq4_pend <= 1'b0; rb_req <= 1'b0; rb_sprite <= 1'b0;
            rom_req <= 1'b0; map_req <= 1'b0; chr_req <= 1'b0; trom_req_g <= 1'b0; srom_req_g <= 1'b0;
            roz_enable <= 1'b0; roz_rombank <= 2'd0;
            eep_di <= 1'b0; eep_cs <= 1'b0; eep_clk <= 1'b0;
            for (int i = 0; i < 32; i++) k56regs[i] <= '0;
            for (int i = 0; i < 4;  i++) k56regsb[i] <= '0;
            for (int i = 0; i < 48; i++) k55regs[i] <= '0;
            for (int i = 0; i < 16; i++) begin k38regs[i] <= '0; k252[i] <= '0; end
            for (int i = 0; i < 16; i++) rozctrl[i] <= '0;
            for (int i = 0; i < 8;  i++) begin k46regs[i] <= '0; k47regs[i] <= '0;k50regs[i]<='0; end
            rozclip[0] <= '0; rozclip[1] <= '0;
        end else begin
            if (cen_16m && !pause && tok < 6'd48) tok <= tok + 6'(STEP_GAIN);

            // IRQ5 is asserted at vblank and held until the kernel's
            // interrupt-acknowledge cycle -- a *read* with FC = 111, which
            // TG68K performs even with IPL_autovector (MAME's HOLD_LINE).
            // Nothing on the board answers it; the vector is internal.
            if (vblank_rise && !pause && !board_mystic && !board_violent && !board_metam) irq5_pend <= 1'b1;

            case (bst)
                B_IDLE: begin
                    // sample the bus only after the kernel has settled (see the
                    // S.T.U.N. Runner core's note on the four-clock gap)
                    // Stop between bus cycles. Outstanding requests below must
                    // still accept their ACK and complete once while paused.
                    if (cpu_step) begin
                        if (fc == 3'b111) begin
                            // interrupt acknowledge: the IRQ drops, the step completes
                            clkena <= 1'b1; tok <= tok - 6'(STEP_COST_BUS); dbg_step <= 1'b1;
                            if (!board_rng || A[3:1]==3'd5) irq5_pend <= 1'b0;
                            if (board_rng && A[3:1]==3'd6) irq6_pend<=1'b0;
                            if (board_mystic && A[3:1] == 3'd4) irq4_pend <= 1'b0;
                            if (board_mystic && A[3:1] == 3'd2) irq2_pend <= 1'b0;
                        end else if (busstate == 2'b01 || skipFetch) begin
                            clkena <= 1'b1; tok <= tok - 6'(STEP_COST_INT); dbg_step <= 1'b1;
                        end else if (is_wr) begin
                            // writes are posted: complete immediately
                            tok <= tok - 6'(STEP_COST_BUS); clkena <= 1'b1; dbg_step <= 1'b1;
                            // sel_wdog and anything unmapped: ignored
                        end else begin
                            // reads
                            tok <= tok - 6'(STEP_COST_BUS);
                            if (sel_rom) begin
                                rom_addr <= A[22:1]; rom_req <= 1'b1; bst <= B_WAIT_ROM;
                            end else if(sel_lvc_ram)begin
                                lvc_req<=1'b1;lvc_we<=1'b0;lvc_addr<=A[13:1];
                                lvc_be<={uds,lds};lvc_wdata<=wdat;bst<=B_WAIT_LVC;
                            end else if(sel_lvc_rom)begin
                                lvc_rom_sel<=A[4:2];
                                lvc_rom_addr<={k50regs[7][6:0],A[12:5]};
                                // reg6 addresses beyond the original256KiB device.
                                lvc_rom_req<=k50regs[6]==8'd0;
                                bst<=k50regs[6]==8'd0 ? B_WAIT_LVCROM : B_RAM_RD;
                            end else if (sel_vram && !vram_ext) begin
                                vc_req <= 1'b1; vc_we <= 1'b0; vc_addr <= vram_cpu_addr; bst <= B_WAIT_VRAM;
                            end else if (sel_rb0) begin
                                // (gfx4[0x20000 + off] << 8) | gfx4[0x60000 + off], off = word offset
                                map_addr <= 20'h20000 + {2'd0, A[18:1]}; map_req <= 1'b1; bst <= B_WAIT_MAP0;
                            end else if (sel_rb1) begin
                                // gfx4[off / 2] in the low byte
                                map_addr <= {3'd0, A[18:2]}; map_req <= 1'b1; bst <= B_WAIT_MAP1;
                            end else if (sel_rb2) begin
                                // gfx3[(bank * 0x100000 + off) / 2] << 8
                                chr_addr <= {roz_rombank, A[20:2]}; chr_req <= 1'b1; bst <= B_WAIT_CHR;
                            end else if (board_readback && (sel_tmrb || sel_sprrb)) begin
                                rb_req <= 1'b1; rb_sprite <= sel_sprrb; bst <= B_WAIT_MRB;
                            end else if (sel_tmrb) begin
                                if (tile_plane5) begin
                                    bst <= B_RAM_RD;             // rd_mux gives 0
                                end else begin
                                    trom_addr_g <= trom_group; trom_req_g <= 1'b1; bst <= B_WAIT_TROM;
                                end
                            end else if (sel_sprrb) begin
                                srom_addr_g <= spr_widx[21:2]; srom_sel <= spr_widx[1:0];
                                srom_req_g <= 1'b1; bst <= B_WAIT_SROM;
                            end else begin
                                if (sel_k321 && (!board_readback || lds)) snd_rd <= 1'b1;
                                if (sel_k000) col_rd <= 1'b1;
                                bst <= B_RAM_RD;
                            end
                        end
                    end
                end

                // block RAMs and latches answer one cycle after the live address
                B_WAIT_LVC: if(lvc_ack)begin
                    lvc_req<=1'b0;data_in<=lvc_q;clkena<=1'b1;dbg_step<=1'b1;bst<=B_IDLE;
                end
                B_WAIT_LVCW: if(lvc_ack)begin
                    lvc_req<=1'b0;clkena<=1'b1;dbg_step<=1'b1;bst<=B_IDLE;
                end
                B_WAIT_LVCROM: if(lvc_rom_ack)begin
                    lvc_rom_req<=1'b0;data_in<={8'd0,lvc_rom_q[63-{lvc_rom_sel,3'b000}-:8]};
                    clkena<=1'b1;dbg_step<=1'b1;bst<=B_IDLE;
                end
                B_RAM_RD: begin
                    data_in <= rd_mux; clkena <= 1'b1; dbg_step <= 1'b1; bst <= B_IDLE;
                end
                B_WAIT_ROM: if (rom_ack) begin
                    rom_req <= 1'b0; data_in <= rom_q; clkena <= 1'b1; dbg_step <= 1'b1; bst <= B_IDLE;
                end
                B_WAIT_VRAM: if (vc_ack) begin
                    vc_req <= 1'b0; data_in <= vc_q; clkena <= 1'b1; dbg_step <= 1'b1; bst <= B_IDLE;
                end
                B_WAIT_VRAMW: if (vc_ack) begin
                    vc_req <= 1'b0; clkena <= 1'b1; dbg_step <= 1'b1; bst <= B_IDLE;
                end
                B_WAIT_MAP0: if (map_ack) begin
                    rb_hi <= map_addr[0] ? map_q[7:0] : map_q[15:8];
                    map_addr <= 20'h60000 + {2'd0, A[18:1]}; bst <= B_WAIT_MAP0B;
                end
                B_WAIT_MAP0B: if (map_ack) begin
                    map_req <= 1'b0;
                    data_in <= {rb_hi, map_addr[0] ? map_q[7:0] : map_q[15:8]};
                    clkena <= 1'b1; dbg_step <= 1'b1; bst <= B_IDLE;
                end
                B_WAIT_MAP1: if (map_ack) begin
                    map_req <= 1'b0;
                    data_in <= {8'h00, map_addr[0] ? map_q[7:0] : map_q[15:8]};
                    clkena <= 1'b1; dbg_step <= 1'b1; bst <= B_IDLE;
                end
                B_WAIT_CHR: if (chr_ack) begin
                    chr_req <= 1'b0;
                    data_in <= {chr_addr[0] ? chr_q[7:0] : chr_q[15:8], 8'h00};
                    clkena <= 1'b1; dbg_step <= 1'b1; bst <= B_IDLE;
                end
                B_WAIT_MRB: if (rb_ack) begin
                    rb_req <= 1'b0; data_in <= rb_data;
                    clkena <= 1'b1; dbg_step <= 1'b1; bst <= B_IDLE;
                end
                B_WAIT_TROM: if (trom_ack) begin
                    trom_req_g <= 1'b0;
                    // rom[addr+1] | rom[addr] << 8: the group's first or second byte pair
                    data_in <= A[1] ? trom_q[15:0] : trom_q[31:16];
                    clkena <= 1'b1; dbg_step <= 1'b1; bst <= B_IDLE;
                end
                B_WAIT_SROM: if (srom_ack) begin
                    srom_req_g <= 1'b0;
                    // (u16*) view on a little-endian host: low byte is the even byte
                    case (srom_sel)
                        2'd0: data_in <= {srom_q[55:48], srom_q[63:56]};
                        2'd1: data_in <= {srom_q[39:32], srom_q[47:40]};
                        2'd2: data_in <= {srom_q[23:16], srom_q[31:24]};
                        default: data_in <= {srom_q[7:0], srom_q[15:8]};
                    endcase
                    clkena <= 1'b1; dbg_step <= 1'b1; bst <= B_IDLE;
                end
                default: bst <= B_IDLE;
            endcase
            // Engine transactions drain even while paused; new CPU commands are gated.
            if (board_violent && k550_go && !k550_we) begin
                if (sel_rom) begin rom_addr<=A[22:1];rom_req<=1'b1;e_rom_pend<=1'b1;end
                else if (sel_vram && !vram_ext) begin vc_req<=1'b1;vc_we<=1'b0;vc_addr<=vram_cpu_addr;e_vr_pend<=1'b1;end
                else begin k550_rd<=rd_mux;k550_done<=1'b1;end
            end
            if(e_rom_pend && rom_ack) begin rom_req<=1'b0;e_rom_pend<=1'b0;k550_rd<=rom_q;k550_done<=1'b1;end
            if(e_vr_pend && vc_ack) begin vc_req<=1'b0;e_vr_pend<=1'b0;k550_rd<=vc_q;k550_done<=1'b1;end
            if(e_vw_pend && vc_ack) begin vc_req<=1'b0;e_vw_pend<=1'b0;k550_done<=1'b1;end
            if(engine_wr && !(sel_vram && !vram_ext)) k550_done<=1'b1;
            // Preserve the old ordinary-read leaf, including live VRAM mode.
            // Only static address/profile predicates move to the capture stage.
            if (cpu_local_read && (mmio_local_other || (mmio_vram && vram_ext))) begin
                snd_off <= A[4:1]; col_off <= A[5:1];
            end
            if(cpu_wr || engine_wr) begin
                if (mmio_k000 && lds) begin
                    col_wr <= 1'b1; col_off <= A[5:1]; col_wdata <= wdat[7:0];
                end
                // These windows are disjoint from all other write targets.
                // Constant destinations remove prefix/index/priority decode
                // from the register-bank enables. Reset still wins above.
                for (int i=0;i<48;i++)
                    if (mmio_k55[i])
                        k55regs[i] <= (lds && !uds) ? wdat[7:0] : wdat[15:8];
                for (int i=0;i<32;i++)
                    if (mmio_k56[i])
                        k56regs[i] <= {uds ? wdat[15:8] : k56regs[i][15:8],
                                      lds ? wdat[7:0] : k56regs[i][7:0]};
                for (int i=0;i<4;i++)
                    if (mmio_k56b[i])
                        k56regsb[i] <= {uds ? wdat[15:8] : k56regsb[i][15:8],
                                       lds ? wdat[7:0] : k56regsb[i][7:0]};
                            if(sel_lvc_ram)begin
                                lvc_req<=1'b1;lvc_we<=1'b1;lvc_addr<=A[13:1];
                                lvc_be<={uds,lds};lvc_wdata<=wdat;
                                clkena<=1'b0;dbg_step<=1'b0;bst<=B_WAIT_LVCW;
                            end else if(sel_lvc_reg)begin
                                if(lds)k50regs[A[3:1]]<=wdat[7:0];
                            end else if (sel_wram) begin
                                if (uds) wram[A[15:1]][1] <= wdat[15:8];
                                if (lds) wram[A[15:1]][0] <= wdat[7:0];
                            end else if (sel_vram) begin
                                if (!vram_ext) begin
                                    // the external tile RAM: a byte-enabled write the kernel waits for
                                    vc_req <= 1'b1; vc_we <= 1'b1; vc_addr <= vram_cpu_addr;
                                    vc_be <= {uds, lds}; vc_wdata <= wdat;
                                    if (cpu_wr) begin clkena <= 1'b0; dbg_step <= 1'b0; bst <= B_WAIT_VRAMW; end
                                    else e_vw_pend <= 1'b1;
                                end
                            end else if (sel_pal) begin
                                pal_we <= 1'b1; pal_waddr <= A[12:2]; pal_wsel <= {A[1], ~A[1]};
                                pal_wbe <= {uds, lds}; pal_wdata <= wdat;
                            end else if (sel_sprwin) begin
                                if (spr_hit) dbg_spr_we <= 1'b1;
                                if (spr_hit)
                                    sram[spr_word] <= {uds ? wdat[15:8] : sram_cpu_q[15:8],
                                                       lds ? wdat[7:0]  : sram_cpu_q[7:0]};
                                else
                                    sshadow[A[15:1]] <= {uds ? wdat[15:8] : sshadow_q[15:8],
                                                         lds ? wdat[7:0]  : sshadow_q[7:0]};
                            end else if (sel_k46) begin
                                // k053246_w: byte pair per word
                                if (uds) k46regs[{A[2:1], 1'b0}] <= wdat[15:8];
                                if (lds) k46regs[{A[2:1], 1'b1}] <= wdat[7:0];
                            end else if (sel_k47) begin
                                k47regs[A[3:1]] <= {uds ? wdat[15:8] : k47regs[A[3:1]][15:8],
                                                    lds ? wdat[7:0]  : k47regs[A[3:1]][7:0]};
                            end else if (sel_rozct) begin
                                // 16 words: 0-7 zoom coefficients, 8-15 the chip's own
                                // clip window (unused by the renderer, but they must not
                                // alias onto the coefficients).
                                rozctrl[A[4:1]] <= {uds ? wdat[15:8] : rozctrl[A[4:1]][15:8],
                                                    lds ? wdat[7:0]  : rozctrl[A[4:1]][7:0]};
                            end else if (sel_rozli) begin
                                rozli[A[11:1]] <= {uds ? wdat[15:8] : rozli_q[15:8],
                                                   lds ? wdat[7:0]  : rozli_q[7:0]};
                            end else if (sel_clip) begin
                                rozclip[A[1]] <= {uds ? wdat[15:8] : rozclip[A[1]][15:8],
                                                  lds ? wdat[7:0]  : rozclip[A[1]][7:0]};
                            end else if (sel_k252) begin
                                if (lds) k252[A[4:1]] <= wdat[7:0];
                            end else if (sel_k321) begin
                                // umask16(0xff00): the high byte
                                if (board_readback ? lds : uds) begin
                                    snd_wr <= 1'b1; snd_off <= A[4:1];
                                    snd_wdata <= board_readback ? wdat[7:0] : wdat[15:8];
                                end
                            end else if (sel_k338) begin
                                k38regs[A[4:1]] <= {uds ? wdat[15:8] : k38regs[A[4:1]][15:8],
                                                    lds ? wdat[7:0]  : k38regs[A[4:1]][7:0]};
                            end else if (sel_eep) begin
                                if (board_mystic ? uds : lds) begin
                                    eep_di <= board_mystic ? wdat[8] : wdat[0];
                                    eep_cs <= board_mystic ? wdat[9] : wdat[1];
                                    eep_clk <= board_mystic ? wdat[10] : wdat[2];
                                end
                            end else if (sel_rozen) begin
                                if (uds) begin roz_enable <= wdat[8]; roz_rombank <= wdat[15:14]; end
                            end else if (sel_sndirq) begin
                                snd_irq <= 1'b1;
                            end
            end
            if(board_rng && raster_start && !pause) begin
                if(raster_line==(board_metam ? 9'd26 : 9'd24)) irq6_pend<=1'b1;
                if(raster_line==(board_metam ? 9'd250 : 9'd248) && k46regs[5][4]) irq5_pend<=1'b1;
            end
            if (board_mystic && raster_start && !pause && k56regsb[3][0]) begin
                if (raster_line == 9'd240) irq2_pend <= 1'b1;
                if (raster_line == 9'd0) irq4_pend <= 1'b1;
            end

        end
    end
endmodule


// Pocket-local timing adaptation of the existing three board maps. The
// pinned MiSTer Vio/Mystic decode and lane contracts were compared before
// implementation; no external RTL is imported (M3_VIO03_FIT09_STRUCTURAL_PLAN).
// Capture one-hot destinations alongside the main board's address/data bundle.
// Reset is deliberately not a target input: the consumer's reset dominates
// all commits while this stage continues to track the selected master bus.
module pregx_mmio_targets (
    input wire clk,mystic,violent,metam,
    input wire [23:1] a,
    output wire [47:0] k55,
    output wire [31:0] k56,
    output wire [3:0] k56b,
    output wire k000,local_other,vram,
    output wire [26:0] board,
    output logic lvc_ram,lvc_reg,lvc_rom
);
    // The complete static board selection travels with the same raw bus
    // capture as A/lanes/data. Consumer priority and live controls stay local.
    wire [26:0] raw_board;
    wire rng_map=violent||metam;
    (* preserve, dont_merge *) logic [26:0] board_r;
    assign board=board_r;
    assign raw_board[0] = rng_map ? (a[23:21] == 3'd0) : (mystic ? (a[23:21] == 3'd0) : (a[23:20] <= 4'h2));
    assign raw_board[1] = rng_map ? (a[23:16] == 8'h21) : ((a[23:16] == 8'h40));
    assign raw_board[2] = rng_map ? (a[23:15] == 9'h060) : (mystic ? (a[23:14] == 10'h180) : (a[23:14] == 10'b0100_0001_00));
    assign raw_board[3] = rng_map ? (a[23:13] == 11'h198) : (mystic ? (a[23:13] == 11'h380) : (a[23:13] == 11'b0100_0010_000));
    assign raw_board[4] = rng_map ? (a[23:3] == 21'h048000) : (mystic ? (a[23:3] == 21'h090800) : (a[23:3]  == 21'h086000));
    assign raw_board[5] = rng_map ? (a[23:13] == 11'h188) : (mystic ? (a[23:14] == 10'h1a0) : (a[23:13] == 11'b0100_0100_000));
    assign raw_board[6] = rng_map ? (a[23:4] == 20'h24400) : (mystic ? (a[23:4] == 20'h48200) : (a[23:4]  == 20'h45000));
    assign raw_board[7] = rng_map ? (a[23:4] == 20'h24401) : (mystic ? (a[23:4] == 20'h48201) : (a[23:4]  == 20'h45001));
    assign raw_board[8] = !rng_map && !mystic && (a[23:5]  == 19'h23000);
    assign raw_board[9] = !rng_map && !mystic && (a[23:12] == 12'h470);
    assign raw_board[10] = !rng_map && !mystic && (a[23:2]  == 22'h121000);
    assign raw_board[11] = rng_map ? (a[23:5] == 19'h13000) : (mystic ? (a[23:5] == 19'h24e00) : (a[23:5]  == 19'h24300));
    assign raw_board[12] = rng_map ? (a[23:5] == 19'h13400) : (mystic ? (a[23:5] == 19'h24c00) : (a[23:5]  == 19'h24500));
    assign raw_board[13] = rng_map ? (a[23:5] == 19'h12a00) : (mystic ? (a[23:5] == 19'h24500) : (a[23:5]  == 19'h24600));
    assign raw_board[14] = rng_map ? (a[23:1] == 23'h13c000) : (mystic ? (a[23:1] == 23'h24b000) : (a[23:1]  == 23'h247000));
    assign raw_board[15] = rng_map ? (a[23:1] == 23'h13c001) : (mystic ? (a[23:1] == 23'h24b001) : (a[23:1]  == 23'h247010));
    assign raw_board[16] = rng_map ? (a[23:16] == 8'h20) : (mystic ? (a[23:16] == 8'h20) : (a[23:16] == 8'h60));
    assign raw_board[17] = !rng_map && !mystic && (a[23:6]  == 18'h19800);
    assign raw_board[18] = rng_map ? (a[23:1] == 23'h13e000) : (mystic ? (a[23:1] == 23'h248000) : (a[23:1]  == 23'h350000));
    assign raw_board[19] = !rng_map && !mystic && (a[23:1]  == 23'h360000);
    assign raw_board[20] = rng_map ? (a[23:1] == 23'h132000) : (mystic ? (a[23:1] == 23'h24d000) : (a[23:1]  == 23'h370000));
    assign raw_board[21] = !rng_map && !mystic && (a[23:19] == 5'b1000_0);
    assign raw_board[22] = !rng_map && !mystic && (a[23:19] == 5'b1010_0);
    assign raw_board[23] = !rng_map && !mystic && (a[23:21] == 3'b110);
    assign raw_board[24] = rng_map ? (a[23:1] == 23'h13a000) : mystic && (a[23:1] == 23'h24a000);
    assign raw_board[25] = rng_map ? (a[23:1] == 23'h13a001) : mystic && (a[23:1] == 23'h24a001);
    assign raw_board[26] = violent && (a[23:6] == 18'h09700);
    wire group55 = rng_map ? (a[23:8]==16'h2580) :
                    mystic ? (a[23:8]==16'h4800) : (a[23:8]==16'h4880);
    wire group56 = rng_map ? (a[23:6]==18'h09c00) :
                    mystic ? (a[23:6]==18'h12300) : (a[23:6]==18'h12000);
    wire group56b = rng_map ? (a[23:3]==21'h04d800) :
                     mystic ? (a[23:3]==21'h093c00) : (a[23:3]==21'h090400);
    wire raw_rom = rng_map ? (a[23:21]==3'd0) :
                   mystic ? (a[23:21]==3'd0) : (a[23:20]<=4'h2);
    wire raw_vram = rng_map ? (a[23:15]==9'h060) :
                    mystic ? (a[23:14]==10'h180) : (a[23:14]==10'b0100_0001_00);
    wire raw_rb0 = !rng_map && !mystic && a[23:19]==5'b1000_0;
    wire raw_rb1 = !rng_map && !mystic && a[23:19]==5'b1010_0;
    wire raw_rb2 = !rng_map && !mystic && a[23:21]==3'b110;
    wire raw_tmrb = rng_map ? (a[23:13]==11'h188) :
                    mystic ? (a[23:14]==10'h1a0) : (a[23:13]==11'b0100_0100_000);
    wire raw_sprrb = rng_map ? (a[23:4]==20'h24400) :
                     mystic ? (a[23:4]==20'h48200) : (a[23:4]==20'h45000);
    (* preserve, dont_merge *) logic k000_r,local_other_r,vram_r;
    assign k000=k000_r;assign local_other=local_other_r;assign vram=vram_r;
    (* preserve, dont_merge *) logic [47:0] k55_r;
    (* preserve, dont_merge *) logic [31:0] k56_r;
    (* preserve, dont_merge *) logic [3:0] k56b_r;
    assign k55=k55_r;assign k56=k56_r;assign k56b=k56b_r;
    always_ff @(posedge clk) begin
        board_r <= raw_board;
        lvc_ram<=metam && a[23:14]==10'h093;
        lvc_reg<=metam && a[23:4]==20'h25000;
        lvc_rom<=metam && a[23:13]==11'h190;
        k000_r <= !rng_map && !mystic && a[23:6]==18'h19800;
        local_other_r <= !(raw_rom || raw_vram || raw_rb0 || raw_rb1 || raw_rb2 || raw_tmrb || raw_sprrb || (metam && (a[23:14]==10'h093 || a[23:13]==11'h190)));
        vram_r <= raw_vram;
        // All seven K55 bits include the original <48 guard and A7 holes.
        for (int i=0;i<48;i++) k55_r[i] <= group55 && a[7:1]==7'(i);
        for (int i=0;i<32;i++) k56_r[i] <= group56 && a[5:1]==5'(i);
        for (int i=0;i<4;i++) k56b_r[i] <= group56b && a[2:1]==2'(i);
    end
endmodule
