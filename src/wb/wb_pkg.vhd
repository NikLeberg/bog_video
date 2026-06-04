-- =============================================================================
-- File:                    wb_pkg.vhd
-- Package:                 wb_pkg
-- Author:                  Niklaus Leuenberger <@NikLeberg>
-- SPDX-License-Identifier: MIT
-- Description:             Package with type and function definitions for
--                          Wishbone interconnect.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.math_real.all;

package wb_pkg is
  constant WB_ADDRESS_WIDTH : natural := 32;          -- Width of address bus
  constant WB_DATA_WIDTH : natural := 32;             -- Width of data bus
  constant WB_NUM_BYTES : natural := WB_DATA_WIDTH/8; -- Number of bytes in data

  -- Intercon memory map entry type
  type wb_map_entry_t is record
    BASE_ADDRESS : std_ulogic_vector(WB_ADDRESS_WIDTH-1 downto 0); -- base address of slave address range
    SIZE : natural; -- size of slave address range in bytes
  end record;

  -- Intercon memory map type
  type wb_map_t is array (natural range <>) of wb_map_entry_t;

  -- Wishbone request type (aka master out, slave in)
  type wb_req_t is record
    adr : std_ulogic_vector(WB_ADDRESS_WIDTH-1 downto 0); -- address
    dat : std_ulogic_vector(WB_DATA_WIDTH-1 downto 0); -- write data
    we  : std_ulogic; -- read = '0' / write = '1'
    sel : std_ulogic_vector(WB_NUM_BYTES-1 downto 0); -- byte enable
    stb : std_ulogic; -- strobe
    cyc : std_ulogic; -- valid cycle
  end record;

  -- Wishbone response type (aka master in, slave out)
  type wb_rsp_t is record
    stl : std_ulogic; -- stall, slave busy
    ack : std_ulogic; -- transfer acknowledge
    err : std_ulogic; -- transfer error
    dat : std_ulogic_vector(WB_DATA_WIDTH-1 downto 0); -- read data
  end record;

  -- Wishbone interface array types
  type wb_req_arr_t is array (natural range <>) of wb_req_t;
  type wb_rsp_arr_t is array (natural range <>) of wb_rsp_t;

  -- Return ceiled log2 of integer numbers i.e. log2(32) = 5, log2(33) = 6.
  function log2(constant n : natural) return natural;

  -- Function to calculate the MSB bit position of the address that addresses
  -- the data inside the slave based on the data space given in the memory
  -- map. E.g. slave with 4 * 32 bits of data uses 16 addresses and as such
  -- func returns 4 LSB bits. Address WB_ADDRESS_WIDTH downto 4 addresses the
  -- slave itself and 3 downto 0 addresses individual memory in the slave. 
  function wb_get_slave_address_ranges (memory_map : wb_map_t) return integer_vector;

  -- Procedure to simulate read transaction on Wishbone bus. 
  procedure wb_sim_read32 (
    signal clk          : in std_ulogic;                                     -- global clock, rising edge
    signal wb_req       : out wb_req_t;                                      -- master out, slave in
    signal wb_rsp       : in wb_rsp_t;                                       -- slave out, master in
    constant address    : in std_ulogic_vector(WB_ADDRESS_WIDTH-1 downto 0); -- address to read from
    constant data       : in std_ulogic_vector(WB_DATA_WIDTH-1 downto 0);    -- expected data
    constant expect_err : in boolean := false;                               -- true: expect read to fail
  );

  -- Procedure to simulate write transaction on Wishbone bus. 
  procedure wb_sim_write32 (
    signal clk       : in std_ulogic;                                     -- global clock, rising edge
    signal wb_req    : out wb_req_t;                                      -- master out, slave in
    signal wb_rsp    : in wb_rsp_t;                                       -- slave out, master in
    constant address : in std_ulogic_vector(WB_ADDRESS_WIDTH-1 downto 0); -- address to write to
    constant data    : in std_ulogic_vector(WB_DATA_WIDTH-1 downto 0);    -- data to write
  );
end package;

package body wb_pkg is
  function log2(constant n : natural) return natural is
  begin
    return natural(ceil(log2(real(n))));
  end log2;

  function wb_get_slave_address_ranges (memory_map : wb_map_t) return integer_vector is
    variable address_ranges : integer_vector(memory_map'length-1 downto 0);
  begin
    for i in memory_map'length-1 downto 0 loop
      address_ranges(i) := log2(memory_map(i).SIZE);
    end loop;
    return address_ranges;
  end function;

  procedure wb_sim_read32 (
    signal clk          : in std_ulogic;                                     -- global clock, rising edge
    signal wb_req       : out wb_req_t;                                      -- master out, slave in
    signal wb_rsp       : in wb_rsp_t;                                       -- slave out, master in
    constant address    : in std_ulogic_vector(WB_ADDRESS_WIDTH-1 downto 0); -- address to read from
    constant data       : in std_ulogic_vector(WB_DATA_WIDTH-1 downto 0);    -- expected data
    constant expect_err : in boolean := false;                               -- true: expect read to fail
  ) is
  begin
    assert WB_DATA_WIDTH >= 32
    report "Wishbone sim parameter error: Can't read 32 bit data word on architecture with only " & natural'image(WB_DATA_WIDTH) & " bits."
      severity error;
    assert address(1 downto 0) = "00"
    report "Wishbone sim parameter error: Can't read unaligned 32 bit data word."
      severity error;

    -- sync to rising edge of clock
    wait until rising_edge(clk);

    -- set wishbone bus signals
    wb_req.we  <= '0';
    wb_req.adr <= address;
    wb_req.dat <= (others => 'X'); -- no data to send
    wb_req.sel(3 downto 0) <= (others => '1'); -- full word, 32 bits
    wb_req.sel(WB_NUM_BYTES-1 downto 4) <= (others => '0');

    -- start transaction
    wb_req.cyc <= '1';
    wb_req.stb <= '1';
    loop
      wait until rising_edge(clk);
      exit when not wb_rsp.stl;
    end loop;
    wb_req.stb <= '0';

    -- wait for ack or err
    while wb_rsp.ack nor wb_rsp.err loop
      wait until rising_edge(clk);
    end loop;

    -- end transaction
    wb_req.cyc <= '0';

    -- check response
    assert (wb_rsp.err = '0' or expect_err)
    report "Wishbone sim read failure: Slave did respond with ERR."
      severity failure;
    assert (wb_rsp.err = '1' or not expect_err)
    report "Wishbone sim read failure: Slave did NOT respond with ERR."
      severity failure;
    assert (wb_rsp.ack = '1' or expect_err)
    report "Wishbone sim read failure: Slave did not ACK."
      severity failure;
    assert wb_rsp.dat = data
    report "Wishbone sim read failure: Slave did send unexpected data."
      severity failure;
  end procedure;

  procedure wb_sim_write32 (
    signal clk       : in std_ulogic;                                     -- global clock, rising edge
    signal wb_req    : out wb_req_t;                                      -- master out, slave in
    signal wb_rsp    : in wb_rsp_t;                                       -- slave out, master in
    constant address : in std_ulogic_vector(WB_ADDRESS_WIDTH-1 downto 0); -- address to write to
    constant data    : in std_ulogic_vector(WB_DATA_WIDTH-1 downto 0)     -- data to write
  ) is
  begin
    assert WB_DATA_WIDTH >= 32
    report "Wishbone sim parameter error: Can't read 32 bit data word on architecture with only " & natural'image(WB_DATA_WIDTH) & " bits."
      severity error;
    assert address(1 downto 0) = "00"
    report "Wishbone sim parameter error: Can't write unaligned 32 bit data word."
      severity error;

    -- sync to rising edge of clock
    wait until rising_edge(clk);

    -- set wishbone bus signals
    wb_req.we <= '1';
    wb_req.adr <= address;
    wb_req.dat <= data;
    wb_req.sel(3 downto 0) <= (others => '1'); -- full word, 32 bits
    wb_req.sel(WB_NUM_BYTES-1 downto 4) <= (others => '0');

    -- start transaction
    wb_req.cyc <= '1';
    wb_req.stb <= '1';
    loop
      wait until rising_edge(clk);
      exit when not wb_rsp.stl;
    end loop;
    wb_req.stb <= '0';

    -- wait for ack or err
    while wb_rsp.ack nor wb_rsp.err loop
      wait until rising_edge(clk);
    end loop;

    -- end transaction
    wb_req.cyc <= '0';

    -- check response
    assert wb_rsp.err = '0'
    report "Wishbone sim write failure: Slave did respond with ERR."
      severity failure;
    assert wb_rsp.ack = '1'
    report "Wishbone sim write failure: Slave did not ACK."
      severity failure;
  end procedure;
end package body;
