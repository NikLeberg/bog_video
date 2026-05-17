-- =============================================================================
-- File:                    st_skid.vhd
-- Entity:                  st_skid
-- Author:                  Niklaus Leuenberger <@NikLeberg>
-- SPDX-License-Identifier: MIT
-- Description:             Skid buffer for pipelined streaming interfaces.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.st_pkg.all;

entity st_skid is
  generic (
    WIDTH  : natural := 8;
    OUTREG : boolean := false -- register output source
  );
  port (
    clk, rst : in std_ulogic;
    sink     : view st_sink_v   of st_t(data(WIDTH-1 downto 0));
    source   : view st_source_v of st_t(data(WIDTH-1 downto 0))
  );
end entity;

architecture rtl of st_skid is
  signal skid_data  : std_ulogic_vector(WIDTH-1 downto 0) := (others => '0');
  signal skid_last  : std_ulogic := '0';
  signal skid_valid : std_ulogic := '0';
begin

  process (clk, rst) is
  begin
    if rst then
      skid_valid <= '0';
    elsif rising_edge(clk) then
      if sink.valid and sink.ready and source.valid and (not source.ready) then
        skid_valid <= '1';
      elsif source.ready then
        skid_valid <= '0';
      end if;
    end if;
  end process;

  process (clk) is
  begin
    if rising_edge(clk) then
      if sink.ready then
        skid_data <= sink.data;
        skid_last <= sink.last;
      end if;
    end if;
  end process;

  sink.ready   <= not skid_valid;
  source.valid <= sink.valid or skid_valid;
  source.data  <= skid_data when skid_valid else sink.data;
  source.last  <= skid_last when skid_valid else sink.last;

end architecture;
