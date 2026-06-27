-- =============================================================================
-- File:                    wb_sdram.vhd
-- Entity:                  wb_sdram
-- Author:                  Niklaus Leuenberger <@NikLeberg>
-- SPDX-License-Identifier: MIT
-- Description:             Wishbone wrapper for SDRAM controller of nullobject
--                          https://github.com/nullobject/sdram-fpga. Configured
--                          to work with the ISSI IS42VM16160K located on the
--                          Gecko4Education board. Datasheet:
--                          https://gecko-wiki.ti.bfh.ch/_media/gecko4education:is42vm16160k.pdf
--
-- Note:                    The Wishbone bus is organized with 32 bit addresses
--                          and byte resolution. The SDRAM has 256 Mbit of data
--                          with an address resolution of 24 bits that each
--                          address 16 bits of data. The SDRAM controller from
--                          nullobject abstracts this away to 32 bit data access
--                          by issuing a burst read/write of two addresses. This
--                          leaves 23 bits of address with a data resolution of
--                          32 bits.
--                          The 32 bit Wishbone address is split up like so:
--                           - first 7 bits: coarse SDRAM address
--                           - next 23 bits: fine SDRAM address
--                           - last  2 bits: ignored by address bus but used for
--                                           byte enable mask to read/write
--                                           individual bytes
--                          Supports: - 32 bit r/w on 4 byte boundaries
--                                    - 16 bit r/w on 2 byte boundaries
--                                    -  8 bit r/w on any byte address
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.wb_pkg.all;

entity wb_sdram is
  generic (
    CLOCK_FREQUENCY : natural := 50_000_000; -- clock frequency of clk in Hz
  );
  port (
    -- Global control --
    clk : in std_ulogic;
    rst : in std_ulogic;
    -- Wishbone slave interface --
    wb_req : in wb_req_t;
    wb_rsp : out wb_rsp_t;
    -- SDRAM --
    sdram_addr  : out unsigned(12 downto 0);
    sdram_ba    : out unsigned(1 downto 0);
    sdram_n_cas : out std_ulogic;
    sdram_cke   : out std_ulogic;
    sdram_n_cs  : out std_ulogic;
    sdram_d     : inout std_ulogic_vector(15 downto 0) := (others => 'X');
    sdram_dqm   : out std_ulogic_vector(1 downto 0);
    sdram_n_ras : out std_ulogic;
    sdram_n_we  : out std_ulogic;
    sdram_clk   : out std_ulogic;
  );
end entity;

architecture behav of wb_sdram is
  signal sdram_ack, sdram_valid : std_ulogic;
begin

  -- SDRAM Controller.
  sdram_inst : entity work.sdram
    generic map (
      -- clock frequency (in MHz)
      CLK_FREQ => (real(CLOCK_FREQUENCY) / 1000000.0),
      -- timing values (in nanoseconds)
      T_DESL => 100000.0, -- startup delay
      T_MRD  => 40.0,     -- mode register cycle time
      T_RC   => 60.0,     -- row cycle time
      T_RCD  => 22.5,     -- RAS to CAS delay
      T_RP   => 22.5,     -- precharge to activate delay
      T_WR   => 22.5,     -- write recovery time
      T_REFI => 7800.0    -- average refresh interval
    )
    port map (
      reset => rst,
      clk   => clk,
      -- Interconnect --
      addr    => unsigned(wb_req.adr(24 downto 2)), -- word address
      benable => wb_req.sel,  -- byte enable
      data    => wb_req.dat,  -- input data bus
      we      => wb_req.we,   -- asserted == write operation
      req     => wb_req.cyc,  -- asserted == operation will be performed
      ack     => sdram_ack,   -- asserted == request accepted
      valid   => sdram_valid, -- asserted == data from sdram valid
      q       => wb_rsp.dat,  -- output data bus
      -- SDRAM interface --
      sdram_a     => sdram_addr,
      sdram_ba    => sdram_ba,
      sdram_dq    => sdram_d,
      sdram_cke   => sdram_cke,
      sdram_cs_n  => sdram_n_cs,
      sdram_ras_n => sdram_n_ras,
      sdram_cas_n => sdram_n_cas,
      sdram_we_n  => sdram_n_we,
      sdram_dqml  => sdram_dqm(0),
      sdram_dqmh  => sdram_dqm(1)
    );

  -- SDRAM extra signals.
  sdram_clk  <= clk;

  -- Wishbone extra signals.
  wb_rsp.stl <= not sdram_ack;
  wb_rsp.ack <= '0'       when not wb_req.cyc else
                sdram_ack when wb_req.we      else
                sdram_valid;
  wb_rsp.err <= '0';

end architecture;
