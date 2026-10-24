//------------------------------------------------------------------------------
// SPDX-License-Identifier: MIT
// SPDX-FileType: SOURCE
// SPDX-FileCopyrightText: (c) 2023, OpenGateware authors and contributors
//------------------------------------------------------------------------------
//
// Generic Data I/O for APF bridge
//
// Copyright (c) 2023, Marcus Andrade <marcus@opengateware.org>
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

`default_nettype none
`timescale 1ns/1ps

module data_io
    #(
         parameter MASK  =  0,  //! Upper 4 bits of address
         parameter AW    = 27,  //! Address Width
         parameter DW    =  8,  //! Data Width (8 or 16 bits)
         parameter DELAY =  4,  //! Number of clock cycles to delay each write output
         parameter HOLD  =  1   //! Number of clock cycles to hold the ioctl_wr signal high
     ) (
         input  logic          clk_74a,
         input  logic          clk_memory,
         // Pocket Bridge Slots
         input  logic          dataslot_requestwrite,
         input  logic   [15:0] dataslot_requestwrite_id,
         input  logic          dataslot_allcomplete,
         // Pocket Bridge
         input  logic          bridge_endian_little,
         input  logic   [31:0] bridge_addr,
         input  logic          bridge_wr,
         input  logic   [31:0] bridge_wr_data,
         // MPU <-> FPGA
         output logic          ioctl_download,     // FIFO stream active until ordered completion
         output logic   [15:0] ioctl_index,        // slot index used to upload the file
         output logic          ioctl_drained, // ordered completion retired in memory clock
         output logic          ioctl_wr,
         output logic [AW-1:0] ioctl_addr,
         output logic [DW-1:0] ioctl_data
     );

    //! ------------------------------------------------------------------------
    //! Per-transfer slot belongs to each byte, not an independently synced
    //! global index. Full family switches still reconfigure the FPGA.
    logic [15:0] active_slot = 16'd0;
    always_ff @(posedge clk_74a) if (dataslot_requestwrite)
        active_slot <= dataslot_requestwrite_id;

    //! ------------------------------------------------------------------------
    //! MPU -> FPGA Download
    //! ------------------------------------------------------------------------
    localparam WORD_SIZE = DW == 16 ? 2 : 1;

    data_loader #(
        .ADDRESS_MASK_UPPER_4      ( MASK                 ),
        .WRITE_MEM_CLOCK_DELAY     ( DELAY                ),
        .WRITE_MEM_EN_CYCLE_LENGTH ( HOLD                 ),
        .ADDRESS_SIZE              ( AW                   ),
        .OUTPUT_WORD_SIZE          ( WORD_SIZE            )
    ) data_loader_in (
        .clk_74a                   ( clk_74a              ),
        .clk_memory                ( clk_memory           ),

        .bridge_wr                 ( bridge_wr            ),
        .bridge_endian_little      ( bridge_endian_little ),
        .bridge_addr               ( bridge_addr          ),
        .bridge_wr_data            ( bridge_wr_data       ),
        .bridge_slot               ( dataslot_requestwrite ? dataslot_requestwrite_id : active_slot ),
        .bridge_complete           ( dataslot_allcomplete  ),
        .write_slot                ( ioctl_index          ),
        .write_drained             ( ioctl_drained        ),
        .write_active              ( ioctl_download       ),

        .write_en                  ( ioctl_wr             ),
        .write_addr                ( ioctl_addr           ),
        .write_data                ( ioctl_data           )
    );

endmodule
