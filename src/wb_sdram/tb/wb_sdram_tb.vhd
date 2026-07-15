-- =============================================================================
-- File:                    wb_sdram_tb.vhd
-- Entity:                  wb_sdram_tb
-- Author:                  Niklaus Leuenberger <@NikLeberg>
-- SPDX-License-Identifier: MIT
-- Description:             Testbench for Wishbone SDRAM wrapper.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.wb_pkg.all;

entity wb_sdram_tb is
end entity;

architecture bench of wb_sdram_tb is
  constant CLK_FREQ   : real := 50.0e6;
  constant CLK_PERIOD : delay_length := 1 sec / CLK_FREQ;
  signal   clk, rst   : std_ulogic := '1';
  signal   done       : std_ulogic := '0';

  signal dut_req : wb_req_t;
  signal dut_rsp : wb_rsp_t;

  signal dut_addr         : unsigned(12 downto 0);
  signal dut_ba           : unsigned( 1 downto 0);
  signal dut_d_i, dut_d_o : std_ulogic_vector(15 downto 0);
  signal dut_dqm          : std_ulogic_vector( 1 downto 0);
  signal dut_n_cas, dut_cke, dut_n_cs, dut_n_ras, dut_n_we, dut_clk, dut_d_oe : std_ulogic;

begin

  clk <= '0' when done else not clk after CLK_PERIOD/2;
  rst <= '1', '0' after 2*CLK_PERIOD;

  dut : entity work.wb_sdram
    generic map (
      CLOCK_FREQUENCY => natural(CLK_FREQ)
    )
    port map (
      clk         => clk,
      rst         => rst,
      wb_req      => dut_req,
      wb_rsp      => dut_rsp,
      sdram_addr  => dut_addr,
      sdram_ba    => dut_ba,
      sdram_n_cas => dut_n_cas,
      sdram_cke   => dut_cke,
      sdram_n_cs  => dut_n_cs,
      sdram_d_oe  => dut_d_oe,
      sdram_d_o   => dut_d_o,
      sdram_d_i   => dut_d_i,
      sdram_dqm   => dut_dqm,
      sdram_n_ras => dut_n_ras,
      sdram_n_we  => dut_n_we,
      sdram_clk   => dut_clk
    );

  dut_d_i <= std_logic_vector(unsigned(dut_d_o) + 1) when rising_edge(clk);

  test : process is
  begin
    wait until rst = '0';
    wait until rising_edge(clk);

    wb_sim_write32(clk, dut_req, dut_rsp, x"0000_0000", x"dead_beef");
    wb_sim_read32(clk, dut_req, dut_rsp, x"0000_0004", x"baad_f00d");

    wait until rising_edge(clk);

    done <= '1';
    wait;
  end process;

end architecture;
