# ==============================================================================
# Gaiapolis on the Pocket: timing constraints beyond the BSP's sys_constr.sdc.
# The 96 MHz system clock, its 8 MHz video pair and the shifted SDRAM clock
# all come from core_pll and are timed as one related group; the two 74.25 MHz
# inputs and the audio PLL are asynchronous to it.  The PLL's fifth output
# (general[4]) is the Analogizer's 48 MHz (clk_sys / 2, in phase), in the same
# group: the pixel hand-over into it (pocket_analogizer.sv) is a held register
# under a toggle, timed as the related-clock path it is.
# ==============================================================================
set_clock_groups -asynchronous \
 -group { bridge_spiclk } \
 -group { clk_74a } \
 -group { clk_74b } \
 -group { ic|core_pll|core_pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk \
          ic|core_pll|core_pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk \
          ic|core_pll|core_pll_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk \
          ic|core_pll|core_pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk \
          ic|core_pll|core_pll_inst|altera_pll_i|general[4].gpll~PLL_OUTPUT_COUNTER|divclk \
          ic|core_pll|core_pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk \
          ic|core_pll|core_pll_inst|altera_pll_i|general[6].gpll~PLL_OUTPUT_COUNTER|divclk } \
 -group { ic|pocket_audio_mixer|audio_pll|mf_audio_pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk \
          ic|pocket_audio_mixer|audio_pll|mf_audio_pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk }

# Runtime video frequency pair: Gaia8MHz or Mystic6MHz, selected together
# only while consumers are reset. Keep the 0/90 pair related within each mode.
set_clock_groups -logically_exclusive \
 -group { ic|core_pll|core_pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk \
          ic|core_pll|core_pll_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk } \
 -group { ic|core_pll|core_pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk \
          ic|core_pll|core_pll_inst|altera_pll_i|general[6].gpll~PLL_OUTPUT_COUNTER|divclk }

# SDRAM: the chip is clocked by the phase-shifted PLL output (the S.T.U.N.
# Runner core's proven arrangement, same controller). With the Analogizer
# (2026-10) the fit moved and the data inputs missed setup by 0.254 ns at
# slow 0C, with 0.98 ns of capture hold and 3 ns of output margin spare, so
# the shift is three steps earlier: 6.12 ns. Before that it was 6.51 ns
# (50 eighths of the 960 MHz VCO period; legal values are multiples of
# 130.2 ps), 0.26 ns later than there: it was 6.90 while the address
# registers sat in core logic, and with them in the IO cells (3 ns of slack)
# the data inputs, which missed the cold corner by 14 ps, get 0.39 ns back.
create_generated_clock -name dram_clk -source \
    [get_pins {ic|core_pll|core_pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] \
    [get_ports {dram_clk}]
set_input_delay -max -clock dram_clk 7.0 [get_ports {dram_dq[*]}]
set_input_delay -min -clock dram_clk 2.5 [get_ports {dram_dq[*]}]
set SDRAM_OUT [get_ports {dram_a[*] dram_ba[*] dram_cke dram_dqm[*] dram_dq[*] dram_ras_n dram_cas_n dram_we_n}]
set_output_delay -max -clock dram_clk  2.0 $SDRAM_OUT
set_output_delay -min -clock dram_clk -1.0 $SDRAM_OUT
set_multicycle_path -setup 2 -from [get_clocks {dram_clk}] -to [get_registers {*|sdram_ctrl:*|dq_in[*]}]
# last changes only at a grant, with the next grant after the service states.
# any_req_q and all ordinary per-clock registers keep their single-cycle check.
set SD_GRANT [get_registers {*|sdram_ctrl:*|cur[*] *|sdram_ctrl:*|last[*]}]
set_multicycle_path -setup 3 -from [get_registers {*|sdram_ctrl:*|last[*]}] -to $SD_GRANT
set_multicycle_path -hold  2 -from [get_registers {*|sdram_ctrl:*|last[*]}] -to $SD_GRANT

# LOCAL pre-GX: related sys/video/Analogizer paths are single-cycle here.
# Original VID_OUT and ANA_PIX blanket exceptions also included per-clock
# debug status and enable controls. Any future exception must identify its
# actual pixel-held launch registers; no exception is inferred from the sink.

# PSRAM: an asynchronous interface driven by a state machine that holds every
# pin for whole system cycles with tens of nanoseconds of margin
# (target/pocket/psram.sv), so the pins are not timed against a clock.
set_false_path -to   [get_ports {cram0_* cram1_*}]
set_false_path -from [get_ports {cram0_dq[*] cram1_dq[*] cram0_wait cram1_wait}]

# TG68K: the kernel steps on a clock enable, at most one step every 4 cycles
set_multicycle_path -setup 4 -from [get_registers {*|TG68KdotC_Kernel:*|*}] -to [get_registers {*|TG68KdotC_Kernel:*|*}]
set_multicycle_path -hold  3 -from [get_registers {*|TG68KdotC_Kernel:*|*}] -to [get_registers {*|TG68KdotC_Kernel:*|*}]

# SRAM: the same treatment -- registered pins held for whole cycles, a read
# sampled three cycles after the address (target/pocket/gaia_mem.sv sram_port)
set_false_path -to   [get_ports {sram_*}]
set_false_path -from [get_ports {sram_dq[*]}]

# The scan-out pipeline -- the line-buffer reads, the K055555 priority
# encoder, the palette read and the RGB stage -- re-evaluates once per 8 MHz
# pixel, twelve clocks apart, and its registers latch only at fixed phases
# inside the pixel (k055555_mixer.sv: the address at phase 5, the colour at
# 9), so a path really has those clocks. Registers that clock every cycle
# must never be given a multicycle on that reasoning alone: the first
# Pocket build did and showed noise.
# LOCAL pre-GX: the original wildcard also relaxed the per-clock phase counter
# and s1->s2 stage. Check this whole pipeline at one clock until any narrower
# exception is justified by the actual launch/capture sequence. pal_rd_q is
# an unconditional read and its original register filter was also empty.
# Explicit phase-2 launch -> phase-5 address/flags capture, three system clocks.
# The phase counter, stage-2 flags and color arithmetic are not in either set.
set PIX_SNAPSHOT [get_registers {*|k055555_mixer:*|p_*}]
set PIX_ENCODE [get_registers {*|k055555_mixer:*|pal_addr* *|k055555_mixer:*|s1_*}]
set_multicycle_path -setup 3 -from $PIX_SNAPSHOT -to $PIX_ENCODE
set_multicycle_path -hold  2 -from $PIX_SNAPSHOT -to $PIX_ENCODE

# TG68K to the board: the kernel's address, data and bus-state outputs settle
# after a clkena step and are sampled only after gaia_main's three-clock gap
# (step_gap), so the decode and the block-RAM write ports have three cycles
# (keepers, not registers: the kernel's register file and the board's RAMs
# are M10K cells, which get_registers does not match)
set_multicycle_path -setup 3 -from [get_keepers {*|TG68KdotC_Kernel:*|*}] -to [get_keepers {*|gaia_main:*|*}]
set_multicycle_path -hold  2 -from [get_keepers {*|TG68KdotC_Kernel:*|*}] -to [get_keepers {*|gaia_main:*|*}]

# LOCAL pre-GX: Z80/SND handshake delays do not justify blanket exceptions.
# Strobe delay FFs and ROM ack/data/IRQ can change on any system cycle.
# Keep these paths single-cycle; add only source-bound exceptions if needed.

# TV80 core FF -> core FF: all six sequential core processes and the register
# bank process update only on cen/ClkEn; ALU/microcode are combinational.
# Actual clk_enables resynchronization has >=9 clocks between consumed CENs;
# use only two here, not the nominal /12. No CPU-board, CEN, IRQ or wait path
# is relaxed. Source/fixture review: docs/TV80_TIMING_REVIEW.md.
set TV80_GATED [get_registers {core_top:ic|gaia_core:ga|gaia_sound:u_snd|tv80s_cen:u_cpu|tv80_core:i_tv80_core|*}]
set_multicycle_path -setup 2 -from $TV80_GATED -to $TV80_GATED
set_multicycle_path -hold  1 -from $TV80_GATED -to $TV80_GATED
