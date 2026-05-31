-- =============================================================================
-- File:                    wb_mux.vhd
-- Entity:                  wb_mux
-- Author:                  Niklaus Leuenberger <@NikLeberg>
-- SPDX-License-Identifier: MIT
-- Description:             Wishbone interconnect for single master multi slave
--                          bus topology. One to many, implemented with muxes.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

use work.wb_pkg.all;

entity wb_mux is
  generic (
    -- General --
    N_SLAVES   : natural;  -- number of connected slaves
    MEMORY_MAP : wb_map_t; -- memory map of address space
  );
  port (
    -- Wishbone master interface --
    wb_req_i : in wb_req_t;
    wb_rsp_o : out wb_rsp_t;
    -- Wishbone slave interface(s) --
    wb_req_o : out wb_req_arr_t(N_SLAVES-1 downto 0);
    wb_rsp_i : in wb_rsp_arr_t(N_SLAVES-1 downto 0);
  );
end entity wb_mux;

architecture behav of wb_mux is
  constant address_ranges : integer_vector := wb_get_slave_address_ranges(MEMORY_MAP);

  -- Number of the slave selected according to the address. Valid range
  -- 0 ... N_SLAVES-1, a value of N_SLAVE indicates an invalid bus address
  -- and will auto terminate with error.
  signal slave_select : natural range N_SLAVES downto 0 := N_SLAVES;

  constant auto_terminate : wb_rsp_t := (ack => '0', err => '1', dat => (others => '0'));
begin
  -- Check wishbone configuration.
  assert WB_ADDRESS_WIDTH mod 8 = 0
  report "Wishbone config error: Width of address bus needs to be a multiple of 8."
    severity error;
  assert WB_DATA_WIDTH mod 8 = 0
  report "Wishbone config error: Width of data bus needs to be a multiple of 8."
    severity error;
  assert N_SLAVES = MEMORY_MAP'length
  report "Wishbone config error: Number of slaves does not match with memory map definition."
    severity error;

  -- Coarse decode address of slaves.
  coarse_decode : process (wb_req_i) is
    constant msb_adr : natural := WB_ADDRESS_WIDTH-1; -- upper bound of address
    variable lsb_adr : natural := 0; -- lower bound of address, depends on slave
  begin
    -- Default to an invalid index, this allows to auto terminate if no
    -- slave could be selected based on the address.
    slave_select <= N_SLAVES;
    -- Loop over all slaves and check the MSB of the address with their
    -- entry in the memory map.
    for i in N_SLAVES-1 downto 0 loop
      lsb_adr := address_ranges(i); -- lower bound of address
      if wb_req_i.adr(msb_adr downto lsb_adr) = MEMORY_MAP(i).BASE_ADDRESS(msb_adr downto lsb_adr) then
        slave_select <= i;
      end if;
    end loop;
  end process;

  -- Connect the master to the selected slave.
  slave_mux : process (wb_req_i, wb_rsp_i, slave_select) is
  begin
    -- Master -> Slave mux
    for i in N_SLAVES-1 downto 0 loop
      -- All shared master signals get assigned to each slave.
      wb_req_o(i) <= wb_req_i;
      -- The strobe signal gets only assigned to the selected slave.
      if i /= slave_select then
        wb_req_o(i).stb <= '0';
      end if;
    end loop;

    -- Slave -> Master mux
    if slave_select /= N_SLAVES then
      wb_rsp_o <= wb_rsp_i(slave_select);
    else
      -- Auto terminate with error when address is not covered in the
      -- memory map.
      wb_rsp_o <= auto_terminate;
    end if;
  end process;

end architecture;
