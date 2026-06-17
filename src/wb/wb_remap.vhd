-- =============================================================================
-- File:                    wb_remap.vhd
-- Entity:                  wb_remap
-- Author:                  Niklaus Leuenberger <@NikLeberg>
-- SPDX-License-Identifier: MIT
-- Description:             Remap wishbone request from one address to the next.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.wb_pkg.all;

entity wb_remap is
  generic (
    MEMORY_MAP_FROM : wb_map_t := (0 => (x"0000_0000", 1)); -- from what address
    MEMORY_MAP_TO   : wb_map_t := (0 => (x"f000_0000", 1)); -- to what address
  );
  port (
    -- Wishbone master interface --
    wb_orig_req  : in wb_req_t;  -- original request
    wb_remap_req : out wb_req_t; -- remapped request
  );
end entity;

architecture behav of wb_remap is
begin
  -- Check memory map configuration.
  assert MEMORY_MAP_FROM'length = MEMORY_MAP_TO'length
  report "Wishbone config error: Each from/to memory map must contain the same amount of entries."
    severity error;
  check_size_gen : for i in 0 to MEMORY_MAP_FROM'length-1 generate
    assert MEMORY_MAP_FROM(i).SIZE = MEMORY_MAP_to(i).SIZE
    report "Wishbone config error: Size of the 'from' memory map entry must be identical to the 'to' memory map."
      severity error;
  end generate check_size_gen;

  -- Decode addresses and remap on match.
  coarse_decode : process (wb_orig_req) is
    constant msb : natural := WB_ADDRESS_WIDTH-1; -- upper bound of address
    constant lsbs : integer_vector := wb_get_slave_address_ranges(MEMORY_MAP_FROM);
  begin
    -- As default: Assume that no remapping of address takes place.
    wb_remap_req <= wb_orig_req;

    -- Loop over all map entries and compare its most significant bits to
    -- the current requested address.
    for i in 0 to MEMORY_MAP_FROM'length-1 loop
      if wb_orig_req.adr(msb downto lsbs(i)) = MEMORY_MAP_FROM(i).BASE_ADDRESS(msb downto lsbs(i)) then
        -- we have a match, remap the address
        wb_remap_req.adr(msb downto lsbs(i)) <= MEMORY_MAP_TO(i).BASE_ADDRESS(msb downto lsbs(i));
        exit;
      end if;
    end loop;
  end process;

end architecture;
