-- =============================================================================
-- File:                    top.vhd
-- Entity:                  top
-- Author:                  Niklaus Leuenberger <@NikLeberg>
-- SPDX-License-Identifier: MIT
-- Description:             Toplevel entity. Simple test of accessing data with
--                          Altera JTAG atom.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity top is
  port (
    -- Global control --
    clk   : in std_ulogic; -- global clock, rising edge
    arstn : in std_ulogic; -- global reset, low-active, async
    -- JTAG --
    altera_reserved_tck : in std_ulogic;
    altera_reserved_tms : in std_ulogic;
    altera_reserved_tdi : in std_ulogic;
    altera_reserved_tdo : out std_ulogic
  );
end entity;

architecture rtl of top is

  component cycloneive_jtag
    generic (
      lpm_type : string := "cycloneive_jtag"
    );
    port (
      tms         : in std_logic := '0';
      tck         : in std_logic := '0';
      tdi         : in std_logic := '0';
      tdoutap     : in std_logic := '0';
      tdouser     : in std_logic := '0';
      tdo         : out std_logic;
      tmsutap     : out std_logic;
      tckutap     : out std_logic;
      tdiutap     : out std_logic;
      shiftuser   : out std_logic;
      clkdruser   : out std_logic;
      updateuser  : out std_logic;
      runidleuser : out std_logic;
      usr1user    : out std_logic
    );
  end component;

  signal rst_ff : std_ulogic_vector(1 downto 0) := (others => '0');
  signal rst    : std_ulogic                    := '0';

  type jtag_t is record
    tck, tms, tdo ,tdi : std_ulogic;
  end record;
  signal jtag : jtag_t;

begin

  -- Synchronize reset.
  process (clk) is
  begin
    if rising_edge(clk) then
      rst_ff <= rst_ff(0) & not (arstn);
      rst    <= rst_ff(1);
    end if;
  end process;

  -- Altera Cyclone IV JTAG atom --
  jtag_inst : cycloneive_jtag
    port map(
      tms         => altera_reserved_tms,
      tck         => altera_reserved_tck,
      tdi         => altera_reserved_tdi,
      tdo         => altera_reserved_tdo,
      tdouser     => jtag.tdo,
      tmsutap     => jtag.tms,
      tckutap     => jtag.tck,
      tdiutap     => jtag.tdi,
      shiftuser   => open, -- don't care, dtm has it's own JTAG FSM
      clkdruser   => open,
      updateuser  => open,
      runidleuser => open,
      usr1user    => open
    );

end architecture;
