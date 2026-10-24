//------------------------------------------------------------------------------
// SPDX-License-Identifier: MIT
// SPDX-FileType: SOURCE
// SPDX-FileCopyrightText: (c) 2023, OpenGateware authors and contributors
//------------------------------------------------------------------------------
//
// Copyright (c) 2023, Marcus Andrade <marcus@opengateware.org>
// Copyright (c) 2022, Analogue Enterprises Limited
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//
//------------------------------------------------------------------------------
// Platform Specific top-level -- Gaiapolis (Konami, 1993)
// Instantiated by the real top-level: apf_top
//
// The machine (gaia_core) is platform-agnostic; this file is the APF glue:
// bridge, data slots, the interact menu, video and audio hand-off, and the
// memories. The 20 MB ROM image lives in SDRAM and the two PSRAMs
// (target/pocket/gaia_mem.sv); the 128-byte EEPROM is the save slot.
//
// The screen is a 376x224 raster at 59.19 Hz, 8 MHz pixels, shown rotated
// 90 degrees (video.json) as the cabinet's monitor was.
//------------------------------------------------------------------------------

`default_nettype none

module core_top
    #(
         //! ------------------------------------------------------------------------
         //! System Configuration Parameters
         //! ------------------------------------------------------------------------
         // Memory
         parameter USE_SDRAM    = 1,       //! Enable SDRAM (tiles, PCM, sprites)
         parameter USE_SRAM     = 1,       //! Enable SRAM (K056832 tile RAM)
         parameter USE_CRAM0    = 1,       //! Enable Cellular RAM #1 (ROZ)
         parameter USE_CRAM1    = 1,       //! Enable Cellular RAM #2 (68000 and Z80 programs)
         // Cartridge port
         parameter USE_ANALOGIZER = 1,     //! Analogizer adapter (docs/analogizer.md)
         // Video
         parameter BPP_R        = 8,       //! Bits Per Pixel Red
         parameter BPP_G        = 8,       //! Bits Per Pixel Green
         parameter BPP_B        = 8,       //! Bits Per Pixel Blue
         // Audio
         parameter AUDIO_DW     = 16,      //! Audio Bits
         parameter AUDIO_S      = 1,       //! Signed Audio
         parameter STEREO       = 1,       //! Stereo Output
         parameter AUDIO_MIX    = 0,       //! [0] No Mix | [1] 25% | [2] 50% | [3] 100% (mono)
         // Gamepad/Joystick
         parameter JOY_PADS     = 4,       //! Total Number of Gamepads
         parameter JOY_ALT      = 0,       //! 2 Players Alternate
         // Data I/O - [MPU -> FPGA]
         parameter DIO_MASK     = 4'h0,    //! Upper 4 bits of address
         parameter DIO_AW       = 27,      //! Address Width
         parameter DIO_DW       = 8,       //! Data Width (8 or 16 bits)
         parameter DIO_DELAY    = 7,       //! Number of clock cycles to delay each write output
         parameter DIO_HOLD     = 4,       //! Number of clock cycles to hold the ioctl_wr signal high
         // HiScore I/O - [MPU <-> FPGA]
         parameter HS_AW        = 16,      //! Max size of game RAM address for highscores
         parameter HS_SW        = 8,       //! Max size of capture RAM For highscore data (default 8 = 256 bytes max)
         parameter HS_CFG_AW    = 2,       //! Max size of RAM address for highscore.dat entries (default 4 = 16 entries max)
         parameter HS_CFG_LW    = 2,       //! Max size of length for each highscore.dat entries (default 1 = 256 bytes max)
         parameter HS_CONFIG    = 2,       //! Dataslot index for config transfer
         parameter HS_DATA      = 3,       //! Dataslot index for save data transfer
         parameter HS_NVM_SZ    = 32'd93,  //! Number bytes required for Save
         parameter HS_MASK      = 4'h1,    //! Upper 4 bits of address
         parameter HS_WR_DELAY  = 4,       //! Number of clock cycles to delay each write output
         parameter HS_WR_HOLD   = 1,       //! Number of clock cycles to hold the nvram_wr signal high
         parameter HS_RD_DELAY  = 4,       //! Number of clock cycles it takes for a read to complete
         // Save I/O - [MPU <-> FPGA]
         parameter SIO_MASK     = 4'h1,    //! Upper 4 bits of address
         parameter SIO_AW       = 27,      //! Address Width
         parameter SIO_DW       = 8,       //! Data Width (8 or 16 bits)
         parameter SIO_WR_DELAY = 4,       //! Number of clock cycles to delay each write output
         parameter SIO_WR_HOLD  = 1,       //! Number of clock cycles to hold the nvram_wr signal high
         parameter SIO_RD_DELAY = 4,       //! Number of clock cycles it takes for a read to complete
         parameter SIO_SAVE_IDX = 2        //! Dataslot index for save data transfer
     ) (
         //! --------------------------------------------------------------------
         //! Clock Inputs 74.25mhz.
         //! Not Phase Aligned, Treat These Domains as Asynchronous
         //! --------------------------------------------------------------------
         input wire          clk_74a, // mainclk1
         input wire          clk_74b, // mainclk1

         //! --------------------------------------------------------------------
         //! Cartridge Interface
         //! --------------------------------------------------------------------
         inout  wire   [7:0] cart_tran_bank2,
         output wire         cart_tran_bank2_dir,
         inout  wire   [7:0] cart_tran_bank3,
         output wire         cart_tran_bank3_dir,
         inout  wire   [7:0] cart_tran_bank1,
         output wire         cart_tran_bank1_dir,
         inout  wire   [7:4] cart_tran_bank0,
         output wire         cart_tran_bank0_dir,
         inout  wire         cart_tran_pin30,
         output wire         cart_tran_pin30_dir,
         output wire         cart_pin30_pwroff_reset,
         inout  wire         cart_tran_pin31,
         output wire         cart_tran_pin31_dir,

         //! --------------------------------------------------------------------
         //! Infrared
         //! --------------------------------------------------------------------
         input  wire         port_ir_rx,
         output wire         port_ir_tx,
         output wire         port_ir_rx_disable,

         //! --------------------------------------------------------------------
         //! GBA link port
         //! --------------------------------------------------------------------
         inout  wire         port_tran_si,
         output wire         port_tran_si_dir,
         inout  wire         port_tran_so,
         output wire         port_tran_so_dir,
         inout  wire         port_tran_sck,
         output wire         port_tran_sck_dir,
         inout  wire         port_tran_sd,
         output wire         port_tran_sd_dir,

         //! --------------------------------------------------------------------
         //! Cellular PSRAM 0 and 1, two chips (64mbit x2 dual die per chip)
         //! --------------------------------------------------------------------
         output wire [21:16] cram0_a,
         inout  wire  [15:0] cram0_dq,
         input  wire         cram0_wait,
         output wire         cram0_clk,
         output wire         cram0_adv_n,
         output wire         cram0_cre,
         output wire         cram0_ce0_n,
         output wire         cram0_ce1_n,
         output wire         cram0_oe_n,
         output wire         cram0_we_n,
         output wire         cram0_ub_n,
         output wire         cram0_lb_n,

         output wire [21:16] cram1_a,
         inout  wire  [15:0] cram1_dq,
         input  wire         cram1_wait,
         output wire         cram1_clk,
         output wire         cram1_adv_n,
         output wire         cram1_cre,
         output wire         cram1_ce0_n,
         output wire         cram1_ce1_n,
         output wire         cram1_oe_n,
         output wire         cram1_we_n,
         output wire         cram1_ub_n,
         output wire         cram1_lb_n,

         //! --------------------------------------------------------------------
         //! SDRAM, 512mbit 16bit
         //! --------------------------------------------------------------------
         output wire  [12:0] dram_a,        // Address bus
         output wire   [1:0] dram_ba,       // Bank select (single bits)
         inout  wire  [15:0] dram_dq,       // Bidirectional data bus
         output wire   [1:0] dram_dqm,      // High/low byte mask
         output wire         dram_clk,      // Chip clock
         output wire         dram_cke,      // Clock enable
         output wire         dram_ras_n,    // Select row address (active low)
         output wire         dram_cas_n,    // Select column address (active low)
         output wire         dram_we_n,     // Write enable (active low)

         //! --------------------------------------------------------------------
         //! SRAM, 1mbit 16bit
         //! --------------------------------------------------------------------
         output wire  [16:0] sram_a,        // Address bus
         inout  wire  [15:0] sram_dq,       // Bidirectional data bus
         output wire         sram_oe_n,     // Output enable
         output wire         sram_we_n,     // Write enable
         output wire         sram_ub_n,     // Upper Byte Mask
         output wire         sram_lb_n,     // Lower Byte Mask

         //! --------------------------------------------------------------------
         //! vblank driven by dock for sync in a certain mode
         //! --------------------------------------------------------------------
         input  wire         vblank,

         //! --------------------------------------------------------------------
         //! I/O to 6515D breakout USB UART
         //! --------------------------------------------------------------------
         output wire         dbg_tx,
         input  wire         dbg_rx,

         //! --------------------------------------------------------------------
         //! I/O pads near jtag connector user can solder to
         //! --------------------------------------------------------------------
         output wire         user1,
         input  wire         user2,

         //! --------------------------------------------------------------------
         //! RFU internal i2c bus
         //! --------------------------------------------------------------------
         inout  wire         aux_sda,
         output wire         aux_scl,

         //! --------------------------------------------------------------------
         //! RFU, do not use !!!
         //! --------------------------------------------------------------------
         output wire         vpll_feed,

         //! --------------------------------------------------------------------
         //! Video Output to Scaler
         //! --------------------------------------------------------------------
         output wire  [23:0] video_rgb,
         output wire         video_rgb_clock,
         output wire         video_rgb_clock_90,
         output wire         video_hs,
         output wire         video_vs,
         output wire         video_de,
         output wire         video_skip,

         //! --------------------------------------------------------------------
         //! Audio
         //! --------------------------------------------------------------------
         output wire         audio_mclk,
         output wire         audio_lrck,
         output wire         audio_dac,
         input  wire         audio_adc,

         //! --------------------------------------------------------------------
         //! Bridge Bus Connection (synchronous to clk_74a)
         //! --------------------------------------------------------------------
         output wire         bridge_endian_little,
         input  wire  [31:0] bridge_addr,
         input  wire         bridge_rd,
         output reg   [31:0] bridge_rd_data,
         input  wire         bridge_wr,
         input  wire  [31:0] bridge_wr_data,

         //! --------------------------------------------------------------------
         //! Controller Data
         //! --------------------------------------------------------------------
         input  wire  [31:0] cont1_key,
         input  wire  [31:0] cont2_key,
         input  wire  [31:0] cont3_key,
         input  wire  [31:0] cont4_key,
         input  wire  [31:0] cont1_joy,
         input  wire  [31:0] cont2_joy,
         input  wire  [31:0] cont3_joy,
         input  wire  [31:0] cont4_joy,
         input  wire  [15:0] cont1_trig,
         input  wire  [15:0] cont2_trig,
         input  wire  [15:0] cont3_trig,
         input  wire  [15:0] cont4_trig
     );

    // not using the IR port, so turn off both the LED, and
    // disable the receive circuit to save power
    assign port_ir_tx         = 0;
    assign port_ir_rx_disable = 1;

    // bridge endianness
    assign bridge_endian_little = 0;

    // cart is unused unless the Analogizer has it (pocket_analogizer, below,
    // which holds these same levels until its menu entry enables it), so
    // set all level translators accordingly
    // directions are 0:IN, 1:OUT
    generate
        if(USE_ANALOGIZER == 0) begin
            assign cart_tran_bank3         = 8'hzz;
            assign cart_tran_bank3_dir     = 1'b0;
            assign cart_tran_bank2         = 8'hzz;
            assign cart_tran_bank2_dir     = 1'b0;
            assign cart_tran_bank1         = 8'hzz;
            assign cart_tran_bank1_dir     = 1'b0;
            assign cart_tran_bank0         = 4'hf;
            assign cart_tran_bank0_dir     = 1'b1;
            assign cart_tran_pin30         = 1'b0;  // reset or cs2, we let the hw control it by itself
            assign cart_tran_pin30_dir     = 1'bz;
            assign cart_pin30_pwroff_reset = 1'b0;  // hardware can control this
            assign cart_tran_pin31         = 1'bz;  // input
            assign cart_tran_pin31_dir     = 1'b0;  // input
        end
    endgenerate

    // link port is input only
    assign port_tran_so      = 1'bz;
    assign port_tran_so_dir  = 1'b0; // SO is output only
    assign port_tran_si      = 1'bz;
    assign port_tran_si_dir  = 1'b0; // SI is input only
    assign port_tran_sck     = 1'bz;
    assign port_tran_sck_dir = 1'b0; // clock direction can change
    assign port_tran_sd      = 1'bz;
    assign port_tran_sd_dir  = 1'b0; // SD is input and not used

    assign video_skip = 1'b0;

    assign dbg_tx    = 1'bZ;
    assign user1     = 1'bZ;
    assign aux_scl   = 1'bZ;
    assign vpll_feed = 1'bZ;

    // Tie off the memory the pins not being used
    generate
        if(USE_CRAM0 == 0) begin
            assign cram0_a     = 'h0;
            assign cram0_dq    = {16{1'bZ}};
            assign cram0_clk   = 0;
            assign cram0_adv_n = 1;
            assign cram0_cre   = 0;
            assign cram0_ce0_n = 1;
            assign cram0_ce1_n = 1;
            assign cram0_oe_n  = 1;
            assign cram0_we_n  = 1;
            assign cram0_ub_n  = 1;
            assign cram0_lb_n  = 1;
        end
        if(USE_CRAM1 == 0) begin
            assign cram1_a     = 'h0;
            assign cram1_dq    = {16{1'bZ}};
            assign cram1_clk   = 0;
            assign cram1_adv_n = 1;
            assign cram1_cre   = 0;
            assign cram1_ce0_n = 1;
            assign cram1_ce1_n = 1;
            assign cram1_oe_n  = 1;
            assign cram1_we_n  = 1;
            assign cram1_ub_n  = 1;
            assign cram1_lb_n  = 1;
        end
        if(USE_SDRAM == 0) begin
            assign dram_a     = 'h0;
            assign dram_ba    = 'h0;
            assign dram_dq    = {16{1'bZ}};
            assign dram_dqm   = 'h0;
            assign dram_clk   = 'h0;
            assign dram_cke   = 'h0;
            assign dram_ras_n = 'h1;
            assign dram_cas_n = 'h1;
            assign dram_we_n  = 'h1;
        end
        if(USE_SRAM == 0) begin
            assign sram_a    = 'h0;
            assign sram_dq   = {16{1'bZ}};
            assign sram_oe_n = 1;
            assign sram_we_n = 1;
            assign sram_ub_n = 1;
            assign sram_lb_n = 1;
        end
    endgenerate

    //! ------------------------------------------------------------------------
    //! Host/Target Command Handler
    //! ------------------------------------------------------------------------
    wire        reset_n;  // driven by host commands, can be used as core-wide reset
    wire [31:0] cmd_bridge_rd_data;

    // bridge host commands
    // synchronous to clk_74a
    wire        status_boot_done  = pll_core_locked_s;
    wire        status_setup_done = pll_core_locked_s; // rising edge triggers a target command
    wire        status_running    = reset_n;           // we are running as soon as reset_n goes high

    wire        dataslot_requestread;
    wire [15:0] dataslot_requestread_id;
    wire        dataslot_requestread_ack = 1;
    wire        dataslot_requestread_ok  = 1;

    wire        dataslot_requestwrite;
    wire [15:0] dataslot_requestwrite_id;
    wire [31:0] dataslot_requestwrite_size;
    wire        dataslot_requestwrite_ack = 1;
    wire        dataslot_requestwrite_ok  = 1;

    wire        dataslot_update;
    wire [15:0] dataslot_update_id;
    wire [31:0] dataslot_update_size;

    wire        dataslot_allcomplete;

    wire [31:0] rtc_epoch_seconds;
    wire [31:0] rtc_date_bcd;
    wire [31:0] rtc_time_bcd;
    wire        rtc_valid;

    wire        savestate_supported;
    wire [31:0] savestate_addr;
    wire [31:0] savestate_size;
    wire [31:0] savestate_maxloadsize;

    wire        savestate_start;
    wire        savestate_start_ack;
    wire        savestate_start_busy;
    wire        savestate_start_ok;
    wire        savestate_start_err;

    wire        savestate_load;
    wire        savestate_load_ack;
    wire        savestate_load_busy;
    wire        savestate_load_ok;
    wire        savestate_load_err;

    wire        osnotify_inmenu;

    // bridge target commands
    // synchronous to clk_74a
    reg         target_dataslot_read;
    reg         target_dataslot_write;
    reg         target_dataslot_getfile;    // require additional param/resp structs to be mapped
    reg         target_dataslot_openfile;   // require additional param/resp structs to be mapped

    wire        target_dataslot_ack;
    wire        target_dataslot_done;
    wire  [2:0] target_dataslot_err;

    reg  [15:0] target_dataslot_id;
    reg  [31:0] target_dataslot_slotoffset;
    reg  [31:0] target_dataslot_bridgeaddr;
    reg  [31:0] target_dataslot_length;

    wire [31:0] target_buffer_param_struct; // to be mapped/implemented when using some Target commands
    wire [31:0] target_buffer_resp_struct;  // to be mapped/implemented when using some Target commands

    // bridge data slot access
    // synchronous to clk_74a
    logic  [9:0] datatable_addr;
    logic        datatable_wren;
    logic [31:0] datatable_data;
    wire  [31:0] datatable_q;

    // Save slot index2 -> size entry2*2+1: the 128-byte EEPROM.
    // Stop writing once readback agrees, avoiding mixed-port read/write
    // collisions while the host reads the table. Restore a later host change.
    localparam [31:0] NV_BYTES = 32'h80;
    always_ff @(posedge clk_74a) begin
        if (datatable_q == NV_BYTES) datatable_wren <= 1'b0;
        else datatable_wren <= 1'b1;
        datatable_addr <= 10'd5;
        datatable_data <= NV_BYTES;
    end

    core_bridge_cmd icb
    (
        .clk                        ( clk_74a                    ),
        .reset_n                    ( reset_n                    ),

        .bridge_endian_little       ( bridge_endian_little       ),
        .bridge_addr                ( bridge_addr                ),
        .bridge_rd                  ( bridge_rd                  ),
        .bridge_rd_data             ( cmd_bridge_rd_data         ),
        .bridge_wr                  ( bridge_wr                  ),
        .bridge_wr_data             ( bridge_wr_data             ),

        .status_boot_done           ( status_boot_done           ),
        .status_setup_done          ( status_setup_done          ),
        .status_running             ( status_running             ),

        .dataslot_requestread       ( dataslot_requestread       ),
        .dataslot_requestread_id    ( dataslot_requestread_id    ),
        .dataslot_requestread_ack   ( dataslot_requestread_ack   ),
        .dataslot_requestread_ok    ( dataslot_requestread_ok    ),

        .dataslot_requestwrite      ( dataslot_requestwrite      ),
        .dataslot_requestwrite_id   ( dataslot_requestwrite_id   ),
        .dataslot_requestwrite_size ( dataslot_requestwrite_size ),
        .dataslot_requestwrite_ack  ( dataslot_requestwrite_ack  ),
        .dataslot_requestwrite_ok   ( dataslot_requestwrite_ok   ),

        .dataslot_update            ( dataslot_update            ),
        .dataslot_update_id         ( dataslot_update_id         ),
        .dataslot_update_size       ( dataslot_update_size       ),

        .dataslot_allcomplete       ( dataslot_allcomplete       ),

        .rtc_epoch_seconds          ( rtc_epoch_seconds          ),
        .rtc_date_bcd               ( rtc_date_bcd               ),
        .rtc_time_bcd               ( rtc_time_bcd               ),
        .rtc_valid                  ( rtc_valid                  ),

        .savestate_supported        ( savestate_supported        ),
        .savestate_addr             ( savestate_addr             ),
        .savestate_size             ( savestate_size             ),
        .savestate_maxloadsize      ( savestate_maxloadsize      ),

        .savestate_start            ( savestate_start            ),
        .savestate_start_ack        ( savestate_start_ack        ),
        .savestate_start_busy       ( savestate_start_busy       ),
        .savestate_start_ok         ( savestate_start_ok         ),
        .savestate_start_err        ( savestate_start_err        ),

        .savestate_load             ( savestate_load             ),
        .savestate_load_ack         ( savestate_load_ack         ),
        .savestate_load_busy        ( savestate_load_busy        ),
        .savestate_load_ok          ( savestate_load_ok          ),
        .savestate_load_err         ( savestate_load_err         ),

        .osnotify_inmenu            ( osnotify_inmenu            ),

        .target_dataslot_read       ( target_dataslot_read       ),
        .target_dataslot_write      ( target_dataslot_write      ),
        .target_dataslot_getfile    ( target_dataslot_getfile    ),
        .target_dataslot_openfile   ( target_dataslot_openfile   ),

        .target_dataslot_ack        ( target_dataslot_ack        ),
        .target_dataslot_done       ( target_dataslot_done       ),
        .target_dataslot_err        ( target_dataslot_err        ),

        .target_dataslot_id         ( target_dataslot_id         ),
        .target_dataslot_slotoffset ( target_dataslot_slotoffset ),
        .target_dataslot_bridgeaddr ( target_dataslot_bridgeaddr ),
        .target_dataslot_length     ( target_dataslot_length     ),

        .target_buffer_param_struct ( target_buffer_param_struct ),
        .target_buffer_resp_struct  ( target_buffer_resp_struct  ),

        .datatable_addr             ( datatable_addr             ),
        .datatable_wren             ( datatable_wren             ),
        .datatable_data             ( datatable_data             ),
        .datatable_q                ( datatable_q                )
    );

    //! END OF APF /////////////////////////////////////////////////////////////

    //! ////////////////////////////////////////////////////////////////////////
    //! @ System Modules
    //! ////////////////////////////////////////////////////////////////////////

    //! ------------------------------------------------------------------------
    //! APF Bridge Read Data
    //! ------------------------------------------------------------------------
    wire [31:0] int_bridge_rd_data;
    wire [31:0] nvm_bridge_rd_data_s;

    // The save slot (family data.json slot2, 128 bytes at 0x20000000, the same
    // arrangement the S.T.U.N. Runner core proved on the panel): its own
    // loader, since the platform's accepts only the ROM's address range, and
    // the unloader that answers the Pocket's read-back. The unloader delivers
    // its word in the bridge clock domain already.
    wire        nv_dl_download, nv_dl_wr, nv_dl_drained;
    wire  [6:0] nv_dl_addr;
    wire  [7:0] nv_dl_data;
    wire [15:0] nv_dl_index;
    data_io #(.MASK(4'h2), .AW(7), .DW(8), .DELAY(DIO_DELAY), .HOLD(DIO_HOLD)) pocket_nv_io
    (
        .clk_74a(clk_74a), .clk_memory(clk_sys),
        .dataslot_requestwrite(dataslot_requestwrite), .dataslot_requestwrite_id(dataslot_requestwrite_id),
        .dataslot_allcomplete(dataslot_allcomplete),
        .bridge_endian_little(bridge_endian_little), .bridge_addr(bridge_addr),
        .bridge_wr(bridge_wr), .bridge_wr_data(bridge_wr_data),
        .ioctl_download(nv_dl_download), .ioctl_index(nv_dl_index), .ioctl_wr(nv_dl_wr),
        .ioctl_drained(nv_dl_drained),
        .ioctl_addr(nv_dl_addr), .ioctl_data(nv_dl_data)
    );
    wire        nv_rd_en;
    wire  [6:0] nv_rd_addr;
    wire  [7:0] nv_rd_data;
    data_unloader #(.ADDRESS_MASK_UPPER_4(4'h2), .ADDRESS_SIZE(7), .READ_MEM_CLOCK_DELAY(4), .INPUT_WORD_SIZE(1)) pocket_nv_unload
    (
        .clk_74a(clk_74a), .clk_memory(clk_sys),
        .bridge_rd(bridge_rd), .bridge_endian_little(bridge_endian_little), .bridge_addr(bridge_addr),
        .bridge_rd_data(nvm_bridge_rd_data_s),
        .read_en(nv_rd_en), .read_addr(nv_rd_addr), .read_data(nv_rd_data)
    );

    // Saving is the core's doing, not the exit flush's: the Pocket only writes a
    // nonvolatile slot back onto a file it loaded, so a first save would never
    // be created. Whenever the game has written its EEPROM, two seconds after
    // the last write -- or at once when the Pocket menu opens -- the core
    // commands the APF to write slot2 from bridge address 0x20000000; the APF
    // reads that range through the unloader above and creates or updates
    // gaiapols.sav. One save also goes out five seconds after loading.
    wire        po_nv_dirty;                // toggles on every EEPROM write
    wire        nv_dirty_s;
    synch_3 sync_nvd(po_nv_dirty, nv_dirty_s, clk_74a);
    wire        inmenu_s;
    synch_3 sync_inmenu(osnotify_inmenu, inmenu_s, clk_74a);
    reg nv_loaded=1'b0; // first host allcomplete; never use this alone to run/save
    wire image_ready_bridge;
    synch_3 sync_image_ready(loaded_s && initial_test_done,image_ready_bridge,clk_74a);
    always_ff @(posedge clk_74a) begin
        target_dataslot_read<=1'b0;target_dataslot_getfile<=1'b0;target_dataslot_openfile<=1'b0;
        target_dataslot_id<=16'd2;target_dataslot_slotoffset<=32'd0;
        target_dataslot_bridgeaddr<=32'h20000000;target_dataslot_length<=NV_BYTES;
        if(dataslot_allcomplete)nv_loaded<=1'b1;
    end
    pregx_nv_save nv_save (
        .clk(clk_74a),.loaded(nv_loaded && image_ready_bridge),.run(reset_n),
        .dirty_toggle(nv_dirty_s),.inmenu(inmenu_s),.ack(target_dataslot_ack),
        .done(target_dataslot_done),.error(target_dataslot_err),.request(target_dataslot_write)
    );

    wire [31:0] ana_bridge_rd_data;
    always_comb begin
        casex(bridge_addr)
            32'h2xxxxxxx: begin bridge_rd_data <= nvm_bridge_rd_data_s; end // the save slot, every word of it
            32'hF0000000: begin bridge_rd_data <= int_bridge_rd_data;   end // Reset
            32'hF0000010: begin bridge_rd_data <= int_bridge_rd_data;   end // Service Mode Switch
            32'hF1000000: begin bridge_rd_data <= int_bridge_rd_data;   end // DIP Switches
            32'hF2000000: begin bridge_rd_data <= int_bridge_rd_data;   end // Modifiers
            32'hF3000000: begin bridge_rd_data <= int_bridge_rd_data;   end // A/V Filters
            32'hF4000000: begin bridge_rd_data <= int_bridge_rd_data;   end // Extra DIP Switches
            32'hF7xxxxxx: begin bridge_rd_data <= ana_bridge_rd_data;   end // Analogizer settings (menu)
            32'hF8xxxxxx: begin bridge_rd_data <= cmd_bridge_rd_data;   end // APF Bridge (Reserved)
            32'hFA000000: begin bridge_rd_data <= int_bridge_rd_data;   end // Status Low  [31:0]
            32'hFB000000: begin bridge_rd_data <= int_bridge_rd_data;   end // Status High [63:32]
            default:      begin bridge_rd_data <= 0;                    end
        endcase
    end

    //! ------------------------------------------------------------------------
    //! Pause Core (Analogue OS Menu/Module Request)
    //! ------------------------------------------------------------------------
    wire pause_core, pause_req;
    assign pause_req = 1'b0;
    pause_crtl core_pause
    (
        .clk_sys    ( clk_sys         ),
        .os_inmenu  ( osnotify_inmenu ),
        .pause_req  ( pause_req       ),
        .pause_core ( pause_core      )
    );

    //! ------------------------------------------------------------------------
    //! Interact: Dip Switches, Modifiers, Filters and Reset
    //! ------------------------------------------------------------------------
    wire  [7:0] dip_sw0, dip_sw1, dip_sw2, dip_sw3;
    wire  [7:0] ext_sw0, ext_sw1, ext_sw2, ext_sw3;
    wire  [7:0] mod_sw0, mod_sw1, mod_sw2, mod_sw3;
    wire  [3:0] scnl_sw, smask_sw, afilter_sw, vol_att;
    wire [63:0] status;
    wire        reset_sw, svc_sw, nvclear_sw;

    interact pocket_interact
    (
        // Clocks and Reset
        .clk_74a          ( clk_74a            ),
        .clk_sync         ( clk_sys            ),
        .reset_n          ( reset_n            ),
        // Pocket Bridge
        .bridge_addr      ( bridge_addr        ),
        .bridge_wr        ( bridge_wr          ),
        .bridge_wr_data   ( bridge_wr_data     ),
        .bridge_rd        ( bridge_rd          ),
        .bridge_rd_data   ( int_bridge_rd_data ),
        // Service Mode Switch
        .svc_sw           ( svc_sw             ),
        // DIP Switches
        .dip_sw0          ( dip_sw0            ),
        .dip_sw1          ( dip_sw1            ),
        .dip_sw2          ( dip_sw2            ),
        .dip_sw3          ( dip_sw3            ),
        // Extra DIP Switches
        .ext_sw0          ( ext_sw0            ),
        .ext_sw1          ( ext_sw1            ),
        .ext_sw2          ( ext_sw2            ),
        .ext_sw3          ( ext_sw3            ),
        // Modifiers
        .mod_sw0          ( mod_sw0            ),
        .mod_sw1          ( mod_sw1            ),
        .mod_sw2          ( mod_sw2            ),
        .mod_sw3          ( mod_sw3            ),
        // Status (Legacy Support)
        .status           ( status             ),
        // Filters Switches
        .scnl_sw          ( scnl_sw            ),
        .smask_sw         ( smask_sw           ),
        .afilter_sw       ( afilter_sw         ),
        .vol_att          ( vol_att            ),
        // Reset Switch
        .reset_sw         ( reset_sw           ),
        .nvclear_sw       ( nvclear_sw         )
    );

    //! ------------------------------------------------------------------------
    //! Audio
    //! ------------------------------------------------------------------------
    wire [AUDIO_DW-1:0] core_snd_l, core_snd_r; // Audio Mono/Left/Right

    audio_mixer #(.DW(AUDIO_DW),.STEREO(STEREO),.IIR(0)) pocket_audio_mixer
    (
        // Clocks and Reset
        .clk_74b    ( clk_74b    ),
        .reset      ( reset_sw   ),
        // Controls
        .afilter_sw ( afilter_sw ),
        .vol_att    ( vol_att    ),
        .mix        ( AUDIO_MIX  ),
        .pause_core ( pause_core ),
        // Audio From Core
        .is_signed  ( AUDIO_S    ),
        .core_l     ( core_snd_l ),
        .core_r     ( core_snd_r ),
        // I2S
        .audio_mclk ( audio_mclk ),
        .audio_lrck ( audio_lrck ),
        .audio_dac  ( audio_dac  )
    );

    //! ------------------------------------------------------------------------
    //! Video
    //! ------------------------------------------------------------------------
    wire       [2:0] video_preset;     // Video Preset Configuration
    wire [BPP_R-1:0] core_r;           // Video Red
    wire [BPP_G-1:0] core_g;           // Video Green
    wire [BPP_B-1:0] core_b;           // Video Blue
    wire             core_hs, core_hb; // Horizontal Sync/Blank
    wire             core_vs, core_vb; // Vertical Sync/Blank
    wire             core_de;          // Display Enable

    assign core_hb = 1'b0;
    assign core_vb = 1'b0;

    video_mixer #(.RW(BPP_R),.GW(BPP_G),.BW(BPP_B)) pocket_video_mixer
    (
        // Clocks
        .clk_74a                  ( clk_74a                  ),
        .clk_sys                  ( clk_sys                  ),
        .clk_vid                  ( clk_vid                  ),
        .clk_vid_90deg            ( clk_vid_90deg            ),
        // Input Controls
        .video_preset             ( video_preset             ),
        .scnl_sw                  ( scnl_sw                  ),
        .smask_sw                 ( smask_sw                 ),
        // Input Video from Core
        .core_r                   ( core_r                   ),
        .core_g                   ( core_g                   ),
        .core_b                   ( core_b                   ),
        .core_vs                  ( core_vs                  ),
        .core_hs                  ( core_hs                  ),
        .core_de                  ( core_de                  ),
        // Output to Display
        .video_rgb                ( video_rgb                ),
        .video_vs                 ( video_vs                 ),
        .video_hs                 ( video_hs                 ),
        .video_de                 ( video_de                 ),
        .video_rgb_clock          ( video_rgb_clock          ),
        .video_rgb_clock_90       ( video_rgb_clock_90       ),
        // Pocket Bridge Slots
        .dataslot_requestwrite    ( dataslot_requestwrite    ), // [i]
        .dataslot_requestwrite_id ( dataslot_requestwrite_id ), // [i]
        .dataslot_allcomplete     ( dataslot_allcomplete     ), // [i]
        // MPU -> FPGA (MPU Write to FPGA)
        // Pocket Bridge
        .bridge_endian_little     ( bridge_endian_little     ), // [i]
        .bridge_addr              ( bridge_addr              ), // [i]
        .bridge_wr                ( bridge_wr                ), // [i]
        .bridge_wr_data           ( bridge_wr_data           )  // [i]
    );

    //! ------------------------------------------------------------------------
    //! Data I/O
    //! ------------------------------------------------------------------------
    wire              ioctl_download, ioctl_drained;
    wire       [15:0] ioctl_index;
    wire              ioctl_wr;
    wire [DIO_AW-1:0] ioctl_addr;
    wire [DIO_DW-1:0] ioctl_data;

    data_io #(.MASK(DIO_MASK),.AW(DIO_AW),.DW(DIO_DW),.DELAY(DIO_DELAY),.HOLD(DIO_HOLD)) pocket_data_io
    (
        // Clocks and Reset
        .clk_74a                  ( clk_74a                  ),
        .clk_memory               ( clk_sys                  ),
        // Pocket Bridge Slots
        .dataslot_requestwrite    ( dataslot_requestwrite    ), // [i]
        .dataslot_requestwrite_id ( dataslot_requestwrite_id ), // [i]
        .dataslot_allcomplete     ( dataslot_allcomplete     ), // [i]
        // MPU -> FPGA (MPU Write to FPGA)
        // Pocket Bridge
        .bridge_endian_little     ( bridge_endian_little     ), // [i]
        .bridge_addr              ( bridge_addr              ), // [i]
        .bridge_wr                ( bridge_wr                ), // [i]
        .bridge_wr_data           ( bridge_wr_data           ), // [i]
        // Controller Interface
        .ioctl_download           ( ioctl_download           ),
        .ioctl_drained            ( ioctl_drained            ), // [o]
        .ioctl_index              ( ioctl_index              ), // [o]
        .ioctl_wr                 ( ioctl_wr                 ), // [o]
        .ioctl_addr               ( ioctl_addr               ), // [o]
        .ioctl_data               ( ioctl_data               )  // [o]
    );

    //! ------------------------------------------------------------------------
    //! Gamepad/Analog Stick
    //! ------------------------------------------------------------------------
    // Player 1
    // - DPAD
    wire       p1_up,     p1_down,   p1_left,   p1_right;
    wire       p1_btn_y,  p1_btn_x,  p1_btn_b,  p1_btn_a;
    wire       p1_btn_l1, p1_btn_l2, p1_btn_l3;
    wire       p1_btn_r1, p1_btn_r2, p1_btn_r3;
    wire       p1_select, p1_start;
    // - Analog
    wire       j1_up,     j1_down,   j1_left,   j1_right;
    wire [7:0] j1_lx,     j1_ly,     j1_rx,     j1_ry;
    // Player 2
    // - DPAD
    wire       p2_up,     p2_down,   p2_left,   p2_right;
    wire       p2_btn_y,  p2_btn_x,  p2_btn_b,  p2_btn_a;
    wire       p2_btn_l1, p2_btn_l2, p2_btn_l3;
    wire       p2_btn_r1, p2_btn_r2, p2_btn_r3;
    wire       p2_select, p2_start;
    // - Analog
    wire       j2_up,     j2_down,   j2_left,   j2_right;
    wire [7:0] j2_lx,     j2_ly,     j2_rx,     j2_ry;
    wire p3_up,p3_down,p3_left,p3_right;
    wire p3_btn_a,p3_btn_b,p3_btn_x,p3_btn_y,p3_btn_l1,p3_btn_r1,p3_select,p3_start;
    wire j3_up,j3_down,j3_left,j3_right;
    wire p4_up,p4_down,p4_left,p4_right;
    wire p4_btn_a,p4_btn_b,p4_btn_x,p4_btn_y,p4_btn_l1,p4_btn_r1,p4_select,p4_start;
    wire j4_up,j4_down,j4_left,j4_right;
    // Single Player or Alternate 2 Players for Arcade (unused: both players are wired)
    wire m_start1, m_start2;
    wire m_coin1,  m_coin2, m_coin;
    wire m_up,     m_down,  m_left, m_right;
    wire m_btn1,   m_btn2,  m_btn3, m_btn4;
    wire m_btn5,   m_btn6,  m_btn7, m_btn8;

    //! The controller words the game reads: the Pocket's, or with the
    //! Analogizer enabled, SNAC pads put in their place (pocket_analogizer.sv,
    //! below).  Use key1..key4 wherever a core would read cont1..4_key.
    wire [31:0] key1, key2, key3, key4;

    gamepad #(.JOY_PADS(JOY_PADS),.JOY_ALT(JOY_ALT)) pocket_gamepad
    (
        .clk_sys   ( clk_sys   ),
        // Pocket PAD Interface
        .cont1_key ( key1      ), .cont1_joy ( cont1_joy ),
        .cont2_key ( key2      ), .cont2_joy ( cont2_joy ),
        .cont3_key ( key3      ), .cont3_joy ( cont3_joy ),
        .cont4_key ( key4      ), .cont4_joy ( cont4_joy ),
        // Player 1
        .p1_up     ( p1_up     ), .p1_down   ( p1_down   ),
        .p1_left   ( p1_left   ), .p1_right  ( p1_right  ),
        .p1_y      ( p1_btn_y  ), .p1_x      ( p1_btn_x  ),
        .p1_b      ( p1_btn_b  ), .p1_a      ( p1_btn_a  ),
        .p1_l1     ( p1_btn_l1 ), .p1_r1     ( p1_btn_r1 ),
        .p1_l2     ( p1_btn_l2 ), .p1_r2     ( p1_btn_r2 ),
        .p1_l3     ( p1_btn_l3 ), .p1_r3     ( p1_btn_r3 ),
        .p1_se     ( p1_select ), .p1_st     ( p1_start  ),
        .j1_up     ( j1_up     ), .j1_down   ( j1_down   ),
        .j1_left   ( j1_left   ), .j1_right  ( j1_right  ),
        .j1_lx     ( j1_lx     ), .j1_ly     ( j1_ly     ),
        .j1_rx     ( j1_rx     ), .j1_ry     ( j1_ry     ),
        // Player 2
        .p2_up     ( p2_up     ), .p2_down   ( p2_down   ),
        .p2_left   ( p2_left   ), .p2_right  ( p2_right  ),
        .p2_y      ( p2_btn_y  ), .p2_x      ( p2_btn_x  ),
        .p2_b      ( p2_btn_b  ), .p2_a      ( p2_btn_a  ),
        .p2_l1     ( p2_btn_l1 ), .p2_r1     ( p2_btn_r1 ),
        .p2_l2     ( p2_btn_l2 ), .p2_r2     ( p2_btn_r2 ),
        .p2_l3     ( p2_btn_l3 ), .p2_r3     ( p2_btn_r3 ),
        .p2_se     ( p2_select ), .p2_st     ( p2_start  ),
        .j2_up     ( j2_up     ), .j2_down   ( j2_down   ),
        .j2_left   ( j2_left   ), .j2_right  ( j2_right  ),
        .j2_lx     ( j2_lx     ), .j2_ly     ( j2_ly     ),
        .j2_rx     ( j2_rx     ), .j2_ry     ( j2_ry     ),
        .p3_up(p3_up),
        .p3_down(p3_down),
        .p3_left(p3_left),
        .p3_right(p3_right),
        .p3_a(p3_btn_a),
        .p3_b(p3_btn_b),
        .p3_x(p3_btn_x),
        .p3_y(p3_btn_y),
        .p3_l1(p3_btn_l1),
        .p3_r1(p3_btn_r1),
        .p3_se(p3_select),
        .p3_st(p3_start),
        .j3_up(j3_up),
        .j3_down(j3_down),
        .j3_left(j3_left),
        .j3_right(j3_right),
        .p4_up(p4_up),
        .p4_down(p4_down),
        .p4_left(p4_left),
        .p4_right(p4_right),
        .p4_a(p4_btn_a),
        .p4_b(p4_btn_b),
        .p4_x(p4_btn_x),
        .p4_y(p4_btn_y),
        .p4_l1(p4_btn_l1),
        .p4_r1(p4_btn_r1),
        .p4_se(p4_select),
        .p4_st(p4_start),
        .j4_up(j4_up),
        .j4_down(j4_down),
        .j4_left(j4_left),
        .j4_right(j4_right),
        // Single Player or Alternate 2 Players for Arcade
        .m_coin    ( m_coin    ),                           // Coinage P1 or P2
        .m_up      ( m_up      ), .m_down    ( m_down    ), // Up/Down
        .m_left    ( m_left    ), .m_right   ( m_right   ), // Left/Right
        .m_btn1    ( m_btn1    ), .m_btn4    ( m_btn4    ), // Y/X
        .m_btn2    ( m_btn2    ), .m_btn3    ( m_btn3    ), // B/A
        .m_btn5    ( m_btn5    ), .m_btn6    ( m_btn6    ), // L1/R1
        .m_btn7    ( m_btn7    ), .m_btn8    ( m_btn8    ), // L2/R2
        .m_coin1   ( m_coin1   ), .m_coin2   ( m_coin2   ), // P1/P2 Coin
        .m_start1  ( m_start1  ), .m_start2  ( m_start2  )  // P1/P2 Start
    );

    //! ------------------------------------------------------------------------
    //! Clocks
    //! ------------------------------------------------------------------------
    wire pll_core_locked, pll_core_locked_s;
    wire clk_sys;       // Machine, renderers and memories: 96.0 MHz
    wire clk_vid;       // Video: 8.0 MHz dot clock, exactly clk_sys / 12, half a system cycle late
    wire clk_vid_90deg; // Video: 8.0 MHz @ 90deg (Pocket RGB clock pair)
    wire clk_sdram;     // SDRAM chip clock: 96.0 MHz, phase-shifted (see the SDC)
    wire clk_ana;       // Analogizer: 48.0 MHz, clk_sys / 2, in phase with it

    pregx_clock_tree core_pll
    (
        .refclk   ( clk_74a ),
        .mystic   ( mystic_profile ),
        .rst      ( 0       ),
        .outclk_0 ( clk_sys       ),
        .outclk_1 ( clk_vid       ),
        .outclk_2 ( clk_vid_90deg ),
        .outclk_3 ( clk_sdram     ),
        .outclk_4 ( clk_ana       ),
        .locked   ( pll_core_locked )
    );

    // Synchronize pll_core_locked into clk_74a domain before usage
    synch_3 sync_lck(pll_core_locked, pll_core_locked_s, clk_74a);

    //! ------------------------------------------------------------------------
    //! @ Gaiapolis (Konami, 1993)
    //! ------------------------------------------------------------------------
    wire reset_sw_s;
    synch_3 sync_rst(reset_sw, reset_sw_s, clk_sys);
    wire pll_locked_sys;
    synch_3 sync_lck2(pll_core_locked, pll_locked_sys, clk_sys);

    //! The memories initialise on the hardware reset; the machine is held
    //! until the SDRAM is ready and the host's first "all complete" has been
    //! seen (nv_loaded, sticky), and by the menu. Not on ioctl_download: the
    //! bridge clears all-complete on any later slot request -- the core's own
    //! save-back makes one five seconds in -- and the loader's download flag
    //! then stays up, which held the first Pocket build in reset for good.
    wire        mem_init  = ~pll_locked_sys;
    wire        mem_ready;
    wire host_loaded_s;
    synch_3 sync_loaded(nv_loaded, host_loaded_s, clk_sys);
    wire mystic_profile, rom_identified, rom_valid, rom_begin;
    // APF family game changes reload the complete RBF. Clock selection is made
    // once the original ROM prefix is known, while machine/video remain reset.
    logic [7:0] clock_settle = 8'd0;
    // Register the terminal decode before the high-fanout reset/blank gates.
    // Release takes256 stable clocks; abort/lock loss still clears immediately
    // on its sampled system edge, just as clearing the old counter did.
    (* preserve *) logic profile_clock_ready = 1'b0;
    always_ff @(posedge clk_sys) begin
        if (!pll_locked_sys || !rom_identified || rom_begin) begin
            clock_settle <= 8'd0;profile_clock_ready <= 1'b0;
        end else begin
            if (!(&clock_settle)) clock_settle <= clock_settle + 8'd1;
            profile_clock_ready <= &clock_settle;
        end
    end
    wire loaded_s = host_loaded_s && rom_valid && profile_clock_ready &&
                    ioctl_drained && nv_dl_drained && mem_ready;
    // Ordered end markers retire all host byte strobes before memory testing.
    // Only full RBF reloads are supported as family game switches.
    // the built-in memory test runs at the end of the load and again on
    // the menu's "Reset Core"; the core stays in reset until it is done
    wire        test_run, test_done, vram_ok;
    wire  [6:0] test_ok, test_stable;
    wire  [3:0] vram_bad;
    logic       loaded_d, rst_d, test_start, test_hold;
    always_ff @(posedge clk_sys) begin
        loaded_d   <= loaded_s; rst_d <= reset_sw_s;
        test_start <= (loaded_s && !loaded_d) || (loaded_s && !reset_sw_s && rst_d);
        if (test_start) test_hold <= 1'b1;
        else if (test_done) test_hold <= 1'b0;
    end
    // Prevent the one/two-cycle start-pulse pipeline from exposing a cold CPU
    // between image completion and the beginning of the initial memory test.
    logic initial_test_done = 1'b0;
    always_ff @(posedge clk_sys) begin
        if (!loaded_s || reset_sw_s || test_start) initial_test_done <= 1'b0;
        else if (test_done) initial_test_done <= 1'b1;
    end
    wire        ga_reset  = reset_sw_s | ~loaded_s | ~mem_ready | test_hold | test_run | ~initial_test_done;

    //! Family ROM slot1: exact original Gaia or compact Mystic memory image.
    wire        ioctl_isROM = ioctl_download && ioctl_index == 16'h1;
    wire        dl_we       = ioctl_isROM && ioctl_wr;
    wire [24:0] dl_addr     = ioctl_addr[24:0];
    wire  [7:0] dl_data     = ioctl_data;

    pregx_rom_profile rom_profile (
        .clk(clk_sys),.dl_we(dl_we),.dl_addr(dl_addr),.dl_data(dl_data),
        .mystic(mystic_profile),.identified(rom_identified),.valid(rom_valid),.begin_image(rom_begin)
    );

    //! Controls, active low as the board reads them (docs/hardware.md section 8):
    //! IN0_P1 bit0 L, 1 R, 2 U, 3 D, 4 B1, 5 B2, 6 B3, 7 Start1, 8 Coin1, 9 Coin2,
    //! 11 test switch, 12 Service1, 13 Service2. P2 the same low byte. IN1 bit 3
    //! test, bit 4 mono (0 = stereo), bit 5 flip off; bits 1:0 are the EEPROM;
    //! bit 2 is an unassigned input the game polls for 0 after the self-test.
    //! Pocket buttons: A/Y = button 1, B/X = button 2, R = button 3.
    wire [15:0] in0_p1;
    wire [7:0] in1, p2;
    wire [15:0] mystic_p12,mystic_p34;
    wire [7:0] mystic_in0;
    pregx_inputs cabinet (
        .mystic(mystic_profile),
        .p1_keys({p1_start,p1_select,p1_btn_r1,p1_btn_l1,p1_btn_y,p1_btn_x,p1_btn_b,p1_btn_a}),
        .p2_keys({p2_start,p2_select,p2_btn_r1,p2_btn_l1,p2_btn_y,p2_btn_x,p2_btn_b,p2_btn_a}),
        .p1_dirs({p1_down|j1_down,p1_up|j1_up,p1_right|j1_right,p1_left|j1_left}),
        .p2_dirs({p2_down|j2_down,p2_up|j2_up,p2_right|j2_right,p2_left|j2_left}),
        .p3_keys({p3_start,p3_select,p3_btn_r1,p3_btn_l1,p3_btn_y,p3_btn_x,p3_btn_b,p3_btn_a}),
        .p3_dirs({p3_down|j3_down,p3_up|j3_up,p3_right|j3_right,p3_left|j3_left}),
        .p4_keys({p4_start,p4_select,p4_btn_r1,p4_btn_l1,p4_btn_y,p4_btn_x,p4_btn_b,p4_btn_a}),
        .p4_dirs({p4_down|j4_down,p4_up|j4_up,p4_right|j4_right,p4_left|j4_left}),
        .test_manual(mod_sw1[0] | svc_sw),
        .test_select(mod_sw2[3:0]), .service_select(mod_sw2[7:4]),
        .dips(dip_sw0[4:0]), .in0_p1(in0_p1), .in1(in1), .p2(p2),
        .mystic_p12(mystic_p12),.mystic_p34(mystic_p34),.mystic_in0(mystic_in0)
    );

    //! Diagnostics from the modifier word: bit 4 SDRAM read capture alternate,
    //! bit 5 slow bursts (the S.T.U.N. Runner controller's switches).
    wire        ga_rd_late    = ~mod_sw0[4];
    wire        ga_burst_slow = mod_sw0[5];
    wire        ga_ps_slow    = mod_sw0[6];   // PSRAM reads captured two clocks later
    wire        ga_sram_slow  = mod_sw0[7];   // SRAM reads captured one clock later
    wire        ga_sram_slow_wr = mod_sw1[7]; // SRAM writes stretched

    // the core's memory ports
    wire        prog_req, prog_ack, tile_req, tile_ack, map_req, map_ack, spr_req, spr_ack;
    wire        blk_req, blk_wr, blk_ack; wire [15:0] blk_addr, blk_data; wire [5:0] blk_idx; wire [3:0] roz_lead;
    wire        snd_req, snd_ack, pcm_req, pcm_ack;
    wire [22:1] prog_addr; wire [18:0] tile_addr; wire [19:0] map_addr; wire [19:0] spr_addr;
    wire [17:0] snd_addr; wire [21:0] pcm_addr;
    wire [15:0] prog_q, map_q; wire [31:0] tile_q; wire [63:0] spr_q; wire [7:0] snd_q, pcm_q;
    wire        vram_req, vram_we, vram_ack; wire [15:0] vram_addr, vram_wdata, vram_q; wire [1:0] vram_be;

    // the EEPROM array port: the image's default, then the save file, then
    // the unloader's reads for saving
    wire        img_eep_we; wire [6:0] img_eep_addr; wire [7:0] img_eep_data;
    wire        nv_load_we  = nv_dl_download && nv_dl_index == 16'h2 && nv_dl_wr;
    wire        eep_we      = img_eep_we | nv_load_we;
    wire  [6:0] eep_addr    = img_eep_we ? img_eep_addr : nv_load_we ? nv_dl_addr : nv_rd_addr;
    wire  [7:0] eep_wdata   = img_eep_we ? img_eep_data : nv_dl_data;

    wire [6:0] memory_test_mask;
    wire [7:0] tile_fifth;
    wire [15:0] spr_fifth;
    gaia_mem u_mem (
        .mystic(mystic_profile), .test_mask(memory_test_mask), .tile_fifth(tile_fifth), .spr_fifth(spr_fifth),
        .clk(clk_sys), .clk_sdram(clk_sdram), .init(mem_init), .ready(mem_ready),
        .rd_late(ga_rd_late), .burst_slow(ga_burst_slow), .ps_slow(ga_ps_slow), .sram_slow(ga_sram_slow), .sram_slow_wr(ga_sram_slow_wr),
        .test_start(test_start), .test_run(test_run), .test_done(test_done), .test_ok(test_ok), .test_stable(test_stable),
        .vram_ok(vram_ok), .vram_bad(vram_bad),
        .dl_we(dl_we), .dl_addr(dl_addr), .dl_data(dl_data),
        .eep_we(img_eep_we), .eep_addr(img_eep_addr), .eep_data(img_eep_data),
        .prog_req(prog_req), .prog_addr(prog_addr), .prog_ack(prog_ack), .prog_q(prog_q),
        .tile_req(tile_req), .tile_addr(tile_addr), .tile_ack(tile_ack), .tile_q(tile_q),
        .map_req(map_req), .map_addr(map_addr), .map_ack(map_ack), .map_q(map_q),
        .blk_req(blk_req), .blk_addr(blk_addr), .blk_wr(blk_wr), .blk_idx(blk_idx), .blk_data(blk_data), .blk_ack(blk_ack), .roz_lead(roz_lead),
        .spr_req(spr_req), .spr_addr(spr_addr), .spr_ack(spr_ack), .spr_q(spr_q),
        .snd_req(snd_req), .snd_addr(snd_addr), .snd_ack(snd_ack), .snd_q(snd_q),
        .pcm_req(pcm_req), .pcm_addr(pcm_addr), .pcm_ack(pcm_ack), .pcm_q(pcm_q),
        .vram_req(vram_req), .vram_we(vram_we), .vram_addr(vram_addr), .vram_be(vram_be), .vram_wdata(vram_wdata),
        .vram_ack(vram_ack), .vram_q(vram_q),
        .dram_dq(dram_dq), .dram_a(dram_a), .dram_ba(dram_ba), .dram_dqm(dram_dqm),
        .dram_clk(dram_clk), .dram_cke(dram_cke), .dram_ras_n(dram_ras_n), .dram_cas_n(dram_cas_n), .dram_we_n(dram_we_n),
        .cram0_a(cram0_a), .cram0_dq(cram0_dq), .cram0_wait(cram0_wait), .cram0_clk(cram0_clk), .cram0_adv_n(cram0_adv_n),
        .cram0_cre(cram0_cre), .cram0_ce0_n(cram0_ce0_n), .cram0_ce1_n(cram0_ce1_n), .cram0_oe_n(cram0_oe_n),
        .cram0_we_n(cram0_we_n), .cram0_ub_n(cram0_ub_n), .cram0_lb_n(cram0_lb_n),
        .cram1_a(cram1_a), .cram1_dq(cram1_dq), .cram1_wait(cram1_wait), .cram1_clk(cram1_clk), .cram1_adv_n(cram1_adv_n),
        .cram1_cre(cram1_cre), .cram1_ce0_n(cram1_ce0_n), .cram1_ce1_n(cram1_ce1_n), .cram1_oe_n(cram1_oe_n),
        .cram1_we_n(cram1_we_n), .cram1_ub_n(cram1_ub_n), .cram1_lb_n(cram1_lb_n),
        .sram_a(sram_a), .sram_dq(sram_dq), .sram_oe_n(sram_oe_n), .sram_we_n(sram_we_n), .sram_ub_n(sram_ub_n), .sram_lb_n(sram_lb_n)
    );

    wire        ga_cen_pix, ga_hs, ga_vs, ga_de, ga_hb, ga_vb;
    wire [23:0] ga_rgb;
    wire [15:0] ga_snd_l, ga_snd_r;
    wire        ga_snd_valid;
    wire [23:0] dbg_addr; wire [15:0] dbg_data; wire [1:0] dbg_busstate; wire [9:0] dbg_objcount; wire [8:0] dbg_vcount;
    wire [15:0] dbg_zpc;
    wire        dbg_step, dbg_irq5, dbg_overrun, dbg_unsupported, dbg_shadow_overlap, dbg_zstep, dbg_zwait;
    wire  [2:0] dbg_overrun_src;

    // Separate opt-in diagnostic build; ordinary builds retain exact bypass.
`ifdef MYSTIC_INTRO_COMPAT
    localparam bit INTRO_COMPAT_BUILD=1'b1;
`else
    localparam bit INTRO_COMPAT_BUILD=1'b0;
`endif
    gaia_core #(.HEXDIR("../rtl/data"),.MYSTIC_INTRO_COMPAT(INTRO_COMPAT_BUILD)) ga (
        .mystic(mystic_profile), .mystic_p12(mystic_p12), .mystic_p34(mystic_p34), .mystic_in0(mystic_in0),
        .tile_fifth(tile_fifth), .spr_fifth(spr_fifth),
        .clk(clk_sys), .reset(ga_reset), .pause(pause_core), .pix_sync(pix_sync), .vid_reset(~pll_locked_sys | ~profile_clock_ready),
        .prog_req(prog_req), .prog_addr(prog_addr), .prog_ack(prog_ack), .prog_q(prog_q),
        .tile_req(tile_req), .tile_addr(tile_addr), .tile_ack(tile_ack), .tile_q(tile_q),
        .map_req(map_req), .map_addr(map_addr), .map_ack(map_ack), .map_q(map_q),
        .blk_req(blk_req), .blk_addr(blk_addr), .blk_wr(blk_wr), .blk_idx(blk_idx), .blk_data(blk_data), .blk_ack(blk_ack), .roz_lead(roz_lead),
        .spr_req(spr_req), .spr_addr(spr_addr), .spr_ack(spr_ack), .spr_q(spr_q),
        .vram_req(vram_req), .vram_we(vram_we), .vram_addr(vram_addr), .vram_be(vram_be), .vram_wdata(vram_wdata),
        .vram_ack(vram_ack), .vram_q(vram_q),
        .snd_rom_req(snd_req), .snd_rom_addr(snd_addr), .snd_rom_ack(snd_ack), .snd_rom_q(snd_q),
        .pcm_req(pcm_req), .pcm_addr(pcm_addr), .pcm_ack(pcm_ack), .pcm_q(pcm_q),
        .eep_ld_we(eep_we), .eep_ld_addr(eep_addr), .eep_ld_wdata(eep_wdata), .eep_ld_q(nv_rd_data), .eep_dirty(po_nv_dirty),
        .in0_p1(in0_p1), .in1(in1), .p2(p2),
        .cen_pix(ga_cen_pix), .rgb(ga_rgb), .hsync(ga_hs), .vsync(ga_vs), .de(ga_de), .hblank(ga_hb), .vblank(ga_vb),
        .snd_l(ga_snd_l), .snd_r(ga_snd_r), .snd_valid(ga_snd_valid),
        .dbg_addr(dbg_addr), .dbg_data(dbg_data), .dbg_busstate(dbg_busstate), .dbg_step(dbg_step), .dbg_irq5(dbg_irq5),
        .dbg_overrun(dbg_overrun), .dbg_overrun_src(dbg_overrun_src), .dbg_draw_objs(), .dbg_draw_rows(), .dbg_draw_cols(), .dbg_draw_pxw(), .dbg_spr_we(), .dbg_roz_en(), .dbg_rozctrl(), .dbg_rozclip(), .dbg_k55(), .dbg_unsupported(dbg_unsupported), .dbg_shadow_overlap(dbg_shadow_overlap),
        .dbg_objcount(dbg_objcount), .dbg_vcount(dbg_vcount), .dbg_zpc(dbg_zpc), .dbg_zstep(dbg_zstep), .dbg_zwait(dbg_zwait)
    );

    //! Preserve Gaia modes0/1 and Mystic modes2/3; Mystic Fill screen uses4.
    wire [1:0] aspect_sel = mod_sw0[2:1];
    assign video_preset = (mystic_profile && aspect_sel == 2'd2) ? 3'd4
                         : {1'b0,mystic_profile,(aspect_sel == 2'd1)};

    //! ------------------------------------------------------------------
    //! Diagnostic overlay (METHODOLOGY section 4), on the modifier word's bit
    //! 3 (the "Diagnostic overlay" menu check): the bottom twelve lines show
    //! three rows of 32 bit-squares, green = 1. The raster runs even while
    //! the machine is held in reset, so a black Pocket can still be read:
    //!   row 0  frame count[7:0] | pll locked, sdram ready, download, all-complete,
    //!          nv loaded, machine reset, IRQ5 pending, 68000 step seen |
    //!          Z80 step seen, snd_valid seen, in0_p1[13:8] | in1[7:0]
    //!   row 1  68000 bus address[23:0] | busstate[1:0] | step count[5:0]
    //!   row 2  the first words the memories returned: the 68000's reset PC
    //!          vector word (prog word 2, 0x0020 in the image) [31:16] |
    //!          the Z80's first ROM byte (0xF3) [15:8] | the tile ROM's first
    //!          byte (0x00) [7:0]
    //! ------------------------------------------------------------------
    wire        ovl_en = mod_sw0[3];
    logic [7:0] ovl_frames, ovl_resets, ovl_overruns, ovl_overruns_l;
    logic [2:0] ovl_ovsrc, ovl_ovsrc_l;
    logic       ovl_ovr_d;
    logic       ovl_vs_d, ovl_rst_d, ovl_seen_step, ovl_seen_zstep, ovl_seen_snd, ovl_unsup, ovl_shadow, ovl_unsup_l, ovl_shadow_l;
    logic       allc_s, nvl_s;
    synch_3 sync_allc(dataslot_allcomplete, allc_s, clk_sys);
    synch_3 sync_nvl(nv_loaded, nvl_s, clk_sys);
    always_ff @(posedge clk_sys) begin
        ovl_vs_d <= ga_vs; ovl_rst_d <= ga_reset;
        if (ga_reset && !ovl_rst_d) ovl_resets <= ovl_resets + 8'd1;
        if (ga_vs && !ovl_vs_d) begin
            ovl_frames <= ovl_frames + 8'd1;
            ovl_seen_step <= 1'b0; ovl_seen_zstep <= 1'b0; ovl_seen_snd <= 1'b0;
            ovl_overruns_l <= ovl_overruns; ovl_overruns <= 8'd0;     // lines that overran their render budget, per frame
            ovl_ovsrc_l <= ovl_ovsrc; ovl_ovsrc <= 3'd0;               // and which renderers, over the frame
            ovl_unsup_l <= ovl_unsup; ovl_unsup <= 1'b0; ovl_shadow_l <= ovl_shadow; ovl_shadow <= 1'b0;
        end
        ovl_ovr_d <= dbg_overrun;                                      // the flag holds for the line: count its edges
        if (dbg_overrun && !ovl_ovr_d && ovl_overruns != 8'hff) ovl_overruns <= ovl_overruns + 8'd1;
        if (dbg_overrun && !ovl_ovr_d) ovl_ovsrc <= ovl_ovsrc | dbg_overrun_src;
        if (dbg_unsupported)    ovl_unsup  <= 1'b1;                    // per frame (latched below): a renderer met a mode
        if (dbg_shadow_overlap) ovl_shadow <= 1'b1;                    // it does not do; a second shadow fell on a pixel
        if (dbg_step)  ovl_seen_step  <= 1'b1;
        if (dbg_zstep) ovl_seen_zstep <= 1'b1;
        if (ga_snd_valid && (ga_snd_l != 16'd0)) ovl_seen_snd <= 1'b1;
    end
    // Row 0: frame counter | pll, sdram ready, download, all-complete, save loaded, core reset, irq5, 68000 stepped
    //        | core resets seen | test done, test running, tile RAM ok, tile RAM bad words (4), Z80 stepped
    // Row 1: 68000 address (24) | region read back ok: prog, snd, tile, chr, map, pcm, spr | sound heard
    // Row 2: region read stable: prog, snd, tile, chr, map, pcm, spr, 0 | overrun lines last frame (8)
    //        | sprites in the list / 4 (8) | unsupported mode met, a second shadow on a pixel (last frame), 0, 0, 0,
    //        overran: tilemap, ROZ, sprites (last frame)
    // Unpopulated Mystic ROZ regions are excluded by the actual memory test mask.
    wire [6:0] ovl_test_ok=test_ok | ~memory_test_mask;
    wire [6:0] ovl_test_stable=test_stable | ~memory_test_mask;
    wire [95:0] ovl_status = {
        ovl_frames, pll_locked_sys, mem_ready, ioctl_download, allc_s, nvl_s, ga_reset, dbg_irq5, ovl_seen_step,
        ovl_resets, test_done, test_run, vram_ok, vram_bad, ovl_seen_zstep,
        dbg_addr, ovl_test_ok[0], ovl_test_ok[1], ovl_test_ok[2], ovl_test_ok[3], ovl_test_ok[4], ovl_test_ok[5], ovl_test_ok[6], ovl_seen_snd,
        ovl_test_stable[0], ovl_test_stable[1], ovl_test_stable[2], ovl_test_stable[3], ovl_test_stable[4], ovl_test_stable[5], ovl_test_stable[6], 1'b0,
        ovl_overruns_l, dbg_objcount[9:2], ovl_unsup_l, ovl_shadow_l, 3'd0, ovl_ovsrc_l
    };
    wire [7:0] ovl_r, ovl_g, ovl_b;
    dbg_overlay ovl (
        .clk(clk_sys), .cen_pix(ga_cen_pix), .enable(ovl_en), .de(ga_de), .vsync(ga_vs),
        .r_in(ga_rgb[23:16]), .g_in(ga_rgb[15:8]), .b_in(ga_rgb[7:0]),
        .status(ovl_status), .mystic(mystic_profile), .r_out(ovl_r), .g_out(ovl_g), .b_out(ovl_b)
    );

    //! ------------------------------------------------------------------
    //! Video: the core emits one pixel per 8 MHz enable in the 96 MHz domain
    //! and holds it for the 12 cycles; clk_vid is 8 MHz from the same PLL,
    //! half a system cycle after a system edge. The enable's phase is pinned
    //! to clk_vid: its edge, seen through two system-clock flops, restarts
    //! the core's divider (clk_enables.sv) so the colour stage updates two
    //! system clocks before the clk_vid edge that samples it here -- 26 ns
    //! of margin by construction, not by luck of the reset phase, and the
    //! SDC gives the analyser that launch edge (a multicycle from the start).
    //! ------------------------------------------------------------------
    reg       vt = 1'b0;                // toggles on clk_vid
    reg       vt_s, vt_d;
    always @(posedge clk_vid) vt <= ~vt;
    always @(posedge clk_sys) begin vt_s <= vt; vt_d <= vt_s; end
    wire      pix_sync = vt_s ^ vt_d;   // the clock after clk_vid's edge is seen
    reg [7:0] vr_q, vg_q, vb_q;
    reg       vhs_q, vvs_q, vde_q;
    always @(posedge clk_vid) begin
        vr_q  <= profile_clock_ready ? ovl_r : 8'd0;
        vg_q  <= profile_clock_ready ? ovl_g : 8'd0;
        vb_q  <= profile_clock_ready ? ovl_b : 8'd0;
        vhs_q <= ga_hs; vvs_q <= ga_vs; vde_q <= ga_de && profile_clock_ready;
    end
    //! "Analogizer: On, Pocket off" in the menu: the picture goes to the
    //! CRT only.  Syncs and DE keep running for the scaler.
    wire ana_pocket_off;
    reg  [1:0] poff_s = 2'b00;
    always @(posedge clk_vid) poff_s <= {poff_s[0], ana_pocket_off};
    assign core_r  = poff_s[1] ? 8'd0 : vr_q;
    assign core_g  = poff_s[1] ? 8'd0 : vg_q;
    assign core_b  = poff_s[1] ? 8'd0 : vb_q;
    assign core_hs = vhs_q;
    assign core_vs = vvs_q;
    assign core_de = vde_q;

    //! ------------------------------------------------------------------
    //! The Analogizer (target/pocket/pocket_analogizer.sv, docs/analogizer.md).
    //! It takes the same picture the Pocket gets -- bring-up panel included,
    //! so the panel can be read off a CRT -- at the board's own raster
    //! (512 x 264 dots at 8 MHz, 15.625 kHz / 59.19 Hz), unrotated: the
    //! cabinet's monitor stood on its side, and so must the CRT.  The colour
    //! changes one system clock before cen_8m and the syncs, DE and blanks
    //! one after it (clk_enables.sv), so the wrapper's sample two clocks
    //! after the enable pairs them as the Pocket's clk_vid sample does.
    //! Held idle until the game is loaded; set from the core's menu
    //! (interact.json, 0xF70000xx).  With the menu's "Analogizer" off, the
    //! default, the cartridge port stays as an unused one and key1..key4 are
    //! cont1..cont4_key.
    //! ------------------------------------------------------------------
    generate
        if(USE_ANALOGIZER == 1) begin : analogizer
            // no scandoubler (nor its HQ2x and VGA scanlines): their line
            // buffers are block RAM this design does not have (the release
            // uses 307 of 308).  RGBS, RGsB, YPbPr and Y/C remain.
            pocket_analogizer #(.CLK_HZ(48_000_000), .LINE_LEN(512), .USE_SD(0)) u_analogizer (
                .clk_74a(clk_74a), .clk(clk_ana), .rst(ga_reset),
                .clk_src(clk_sys), .src_pix_ce(ga_cen_pix),
                .src_rgb({ovl_r, ovl_g, ovl_b}),
                .src_hs(ga_hs), .src_vs(ga_vs), .src_hb(ga_hb), .src_vb(ga_vb),
                .bridge_addr(bridge_addr),
                .bridge_rd(bridge_rd), .bridge_rd_data(ana_bridge_rd_data),
                .bridge_wr(bridge_wr), .bridge_wr_data(bridge_wr_data),
                .cont1_key(cont1_key), .cont2_key(cont2_key),
                .cont3_key(cont3_key), .cont4_key(cont4_key),
                .key1(key1), .key2(key2), .key3(key3), .key4(key4),
                .ena(), .pocket_off(ana_pocket_off),
                .ps2_code_new(), .ps2_code(),
                .cart_tran_bank2(cart_tran_bank2), .cart_tran_bank2_dir(cart_tran_bank2_dir),
                .cart_tran_bank3(cart_tran_bank3), .cart_tran_bank3_dir(cart_tran_bank3_dir),
                .cart_tran_bank1(cart_tran_bank1), .cart_tran_bank1_dir(cart_tran_bank1_dir),
                .cart_tran_bank0(cart_tran_bank0), .cart_tran_bank0_dir(cart_tran_bank0_dir),
                .cart_tran_pin30(cart_tran_pin30), .cart_tran_pin30_dir(cart_tran_pin30_dir),
                .cart_pin30_pwroff_reset(cart_pin30_pwroff_reset),
                .cart_tran_pin31(cart_tran_pin31), .cart_tran_pin31_dir(cart_tran_pin31_dir)
            );
        end else begin : no_analogizer
            assign key1 = cont1_key; assign key2 = cont2_key;
            assign key3 = cont3_key; assign key4 = cont4_key;
            assign ana_bridge_rd_data = 32'h0;
            assign ana_pocket_off = 1'b0;
        end
    endgenerate

    //! ------------------------------------------------------------------
    //! Audio clock domain crossing (METHODOLOGY section 5.4): the sound
    //! board delivers a stereo sample every snd_valid (48 kHz) on clk_sys;
    //! hold it and hand it over to clk_74b with a toggle flag so the audio
    //! side never latches a torn sample.
    //! ------------------------------------------------------------------
    logic signed [15:0] snd_hold_l = 16'sd0, snd_hold_r = 16'sd0;
    logic               snd_tog  = 1'b0;
    always_ff @(posedge clk_sys) begin
        if (ga_snd_valid) begin
            snd_hold_l <= ga_snd_l;
            snd_hold_r <= ga_snd_r;
            snd_tog    <= ~snd_tog;
        end
    end
    logic        [2:0]  snd_tog_s = 3'd0;
    logic signed [15:0] snd_xfer_l = 16'sd0, snd_xfer_r = 16'sd0;
    always_ff @(posedge clk_74b) begin
        snd_tog_s <= {snd_tog_s[1:0], snd_tog};
        if (snd_tog_s[2] != snd_tog_s[1]) begin snd_xfer_l <= snd_hold_l; snd_xfer_r <= snd_hold_r; end
    end
    assign core_snd_l = snd_xfer_l;
    assign core_snd_r = snd_xfer_r;

endmodule
