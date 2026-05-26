-- =============================================================================
-- File:                    st_skid.vhd
-- Entity:                  st_skid
-- Author:                  Niklaus Leuenberger <@NikLeberg>
-- SPDX-License-Identifier: MIT
-- Description:             Skid buffer for pipelined streaming interfaces.
--                          Buffers in-flight streaming packets while downstream
--                          de-asserts ready.
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
    us_fwd : in st_fwd_t(data(WIDTH-1 downto 0));
    us_rev : out st_rev_t;
    ds_fwd : out st_fwd_t(data(WIDTH-1 downto 0));
    ds_rev : in st_rev_t
  );
end entity;

architecture rtl of st_skid is
  signal skid_data  : st_fwd_t(data(WIDTH-1 downto 0));
  signal skid_valid : std_ulogic := '0';
begin

  process (clk, rst) is
  begin
    if rst then
      skid_valid <= '0';
    elsif rising_edge(clk) then
      if us_fwd.valid and us_rev.ready and ds_fwd.valid and (not ds_rev.ready) then
        skid_valid <= '1';
      elsif ds_rev.ready then
        skid_valid <= '0';
      end if;
    end if;
  end process;

  process (clk) is
  begin
    if rising_edge(clk) then
      if us_rev.ready then
        skid_data <= us_fwd;
      end if;
    end if;
  end process;

  us_rev.ready <= not skid_valid;
  ds_fwd.valid <= us_fwd.valid or skid_valid;
  ds_fwd.data  <= skid_data.data when skid_valid else us_fwd.data;
  ds_fwd.last  <= skid_data.last when skid_valid else us_fwd.last;

end architecture;
