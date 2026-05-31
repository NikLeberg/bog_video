-- =============================================================================
-- File:                    top.vhd
-- Entity:                  top
-- Author:                  Niklaus Leuenberger <@NikLeberg>
-- SPDX-License-Identifier: MIT
-- Description:             Toplevel entity. End goal is to stream image data
--                          from OV2640 camera through internal processing
--                          pipeline and push it then to a computer through
--                          JTAG.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.st_pkg.all;

entity top is
  port (
    -- Global control --
    clk   : in std_ulogic; -- global clock, rising edge
    arstn : in std_ulogic; -- global reset, low-active, async
    -- LED matrix --
    led_matrix : out std_ulogic_vector((10*12)-1 downto 0)
  );
end entity;

architecture rtl of top is

  component alt_jtag_atlantic is
    generic (
      INSTANCE_ID             : integer;
      LOG2_RXFIFO_DEPTH       : integer;
      LOG2_TXFIFO_DEPTH       : integer;
      SLD_AUTO_INSTANCE_INDEX : string;
    );
    port (
      clk   : in std_ulogic;
      rst_n : in std_ulogic;
      -- data from FPGA --
      r_dat : in std_ulogic_vector(7 downto 0);
      r_val : in std_ulogic;  -- valid
      r_ena : out std_ulogic; -- ready
      -- data to FPGA --
      t_dat : out std_ulogic_vector(7 downto 0);
      t_dav : in std_ulogic;  -- ready
      t_ena : out std_ulogic; -- valid
      t_pause : out std_ulogic;
    );
  end component;

  signal rst_ff : std_ulogic_vector(1 downto 0) := (others => '0');
  signal rst    : std_ulogic                    := '0';

  signal atlantic_fwd, skid_fwd, stuff_fwd : st_fwd_t(data(7 downto 0));
  signal atlantic_rev, skid_rev, stuff_rev : st_rev_t;

begin

  -- Synchronize reset.
  process (clk) is
  begin
    if rising_edge(clk) then
      rst_ff <= rst_ff(0) & not (arstn);
      rst    <= rst_ff(1);
    end if;
  end process;

  jtag_atlantic_inst : alt_jtag_atlantic
    generic map (
      INSTANCE_ID             => 0,
      LOG2_RXFIFO_DEPTH       => 4,
      LOG2_TXFIFO_DEPTH       => 4,
      SLD_AUTO_INSTANCE_INDEX => "YES"
    )
    port map (
      clk     => clk,
      rst_n   => not rst,
      -- data from FPGA --
      r_dat   => stuff_fwd.data,
      r_val   => stuff_fwd.valid,
      r_ena   => stuff_rev.ready,
      -- data to FPGA --
      t_dat   => atlantic_fwd.data,
      t_dav   => atlantic_rev.ready,
      t_ena   => atlantic_fwd.valid,
      t_pause => open
    );

  atlantic_fwd.last <= '0'; -- unused
  
  st_skid_inst : entity work.st_skid
    generic map (
      WIDTH  => 8,
      OUTREG => false
    )
    port map (
      clk    => clk,
      rst    => rst,
      us_fwd => atlantic_fwd,
      us_rev => atlantic_rev,
      ds_fwd => skid_fwd,
      ds_rev => skid_rev
    );

  st_stuff_inst : entity work.st_stuff
    generic map (
      WIDTH => 8
    )
    port map (
      clk    => clk,
      rst    => rst,
      us_fwd => skid_fwd,
      us_rev => skid_rev,
      ds_fwd => stuff_fwd,
      ds_rev => stuff_rev
    );

end architecture;
