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

library neorv32;
use neorv32.neorv32_package.all;

use work.alt_pkg.all;
use work.wb_pkg.all;
use work.st_pkg.all;

entity top is
  port (
    -- Global control --
    clk   : in std_ulogic; -- global clock, rising edge
    arstn : in std_ulogic; -- global reset, low-active, async
    -- Buttons --
    sw0n, sw1n, sw2n, sw3n, sw4n, sw5n : in std_ulogic;
    -- LED matrix --
    led_matrix : out std_ulogic_vector((10*12)-1 downto 0) := (others => '0');
    -- UART ---
    rx : in std_ulogic;
    tx : out std_ulogic;
    -- I2C ---
    sda : inout std_ulogic;
    scl : inout std_ulogic;
    -- DIP switches --
    dip0n, dip1n : in std_ulogic_vector(7 downto 0);
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
    -- SPI flash --
    flash_n_cs       : out std_ulogic;
    flash_n_hold_io3 : out std_ulogic := '1'; -- hold, unused
    flash_sck        : out std_ulogic;
    flash_mosi_io0   : out std_ulogic;
    flash_miso_io1   : in std_ulogic;
    flash_n_wp_io2   : out std_ulogic := '1'; -- write protect, unused
  );
end entity;

architecture rtl of top is

  constant CLOCK_FREQUENCY : natural := 50_000_000;

  -- When we implement the JTAG OCD, then boot into bootloader (0). Otherwise
  -- directly boot into internal (small) IMEM (2) (not the external SDRAM).
  constant IMPLEMENT_OCD : boolean := true;
  constant BOOT_MODE : natural := sel_natural_f(IMPLEMENT_OCD, 0, 2);

  signal rst_ff : std_ulogic_vector(1 downto 0) := (others => '0');
  signal rst    : std_ulogic                    := '0';

  signal gpio_i, gpio_o : std_ulogic_vector(31 downto 0);
  signal sda_o, scl_o   : std_ulogic;

  -- XBUS memory map:
  -- 0x00000000 \ 16 MB => SDRAM IMEM
  -- 0x00ffffff /
  -- ----------
  -- 0x01000000 \ 16 MB => SDRAM DMEM
  -- 0x01ffffff /
  -- ----------
  -- 0x80000000 \ 16 MB => SDRAM DMEM (mirror)
  -- 0x80ffffff /

  -- 32 MB SDRAM is split into 16 MB IMEM and 16 MB DMEM. Make upper portion
  -- accessible at default address 0x80000000.
  constant WB_MEMORY_REMAP_FROM : wb_map_t := (
    0 => (x"8000_0000", 16*1024*1024) -- DMEM as accessed by NEORV32, 16 MB
  );
  constant WB_MEMORY_REMAP_TO : wb_map_t := (
    0 => (x"0100_0000", 16*1024*1024) -- physical DMEM address, 16 MB
  );

  constant WB_N_SLAVES_MUX   : natural := 1;
  constant WB_MEMORY_MAP_MUX : wb_map_t := (
    0 => (x"0000_0000", 32*1024*1024) -- SDRAM, 32 MB
  );
  signal wb_core_req, wb_remap_req, wb_sdram_req : wb_req_t;
  signal wb_core_rsp, wb_remap_rsp, wb_sdram_rsp : wb_rsp_t;

  signal spi_n_cs : std_ulogic_vector(7 downto 0);

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

  -- NEORV32 softcore.
  neorv32_inst : entity neorv32.neorv32_top
    generic map (
      -- General --
      CLOCK_FREQUENCY   => CLOCK_FREQUENCY,
      -- Boot Configuration --
      BOOT_MODE_SELECT  => BOOT_MODE,
      -- On-Chip Debugger (OCD) --
      OCD_EN            => IMPLEMENT_OCD,
      -- Internal Instruction memory (IMEM) --
      IMEM_EN           => not IMPLEMENT_OCD,
      IMEM_SIZE         => 16*1024, -- must use internal IMEM for BOOT_MODE=2
      -- Internal Data memory (DMEM) --
      DMEM_EN           => false,
      -- CPU Caches --
      ICACHE_EN         => true,
      ICACHE_NUM_BLOCKS => 32,
      DCACHE_EN         => true,
      DCACHE_NUM_BLOCKS => 128,
      CACHE_BLOCK_SIZE  => 64,
      CACHE_BURSTS_EN   => false, -- TODO: not supported by SDRAM
      -- External Bus Interface (XBUS) --
      XBUS_EN           => true,
      XBUS_TIMEOUT      => 8192, -- must be sufficient for SDRAM init
      -- General-Purpose Input/Output Controller (GPIO) --
      IO_GPIO_NUM       => 32,
      -- RISC-V Core-Local Interruptor (CLINT) --
      IO_CLINT_EN       => IMPLEMENT_OCD, -- bootloader uses CLINT timer
      -- Universal Asynchronous Receiver/Transmitter (UART0/UART1) --
      IO_UART0_EN       => true,
      IO_UART0_RX_FIFO  => 32,
      IO_UART0_TX_FIFO  => 32,
      -- Serial Peripheral Interface (SPI Host, SDI Device) --
      IO_SPI_EN         => true,
      IO_SPI_FIFO       => 8,
      -- Two-Wire Interface (TWI Host, TWD Device) --
      IO_TWI_EN         => true,
      IO_TWI_FIFO       => 1
    )
    port map (
      -- Global control --
      clk_i       => clk,
      rstn_i      => not rst,
      -- JTAG on-chip debugger interface (available if OCD_EN = true) --
      --  => ports unconnected, actual signals come from SLD node
      -- External bus interface (available if XBUS_EN = true) --
      xbus_cyc_o  => wb_core_req.cyc,
      xbus_stb_o  => wb_core_req.stb,
      xbus_adr_o  => wb_core_req.adr,
      xbus_dat_o  => wb_core_req.dat,
      xbus_cti_o  => open,
      xbus_tag_o  => open,
      xbus_we_o   => wb_core_req.we,
      xbus_sel_o  => wb_core_req.sel,
      xbus_dat_i  => wb_core_rsp.dat,
      xbus_ack_i  => wb_core_rsp.ack,
      xbus_err_i  => wb_core_rsp.err,
      -- GPIO (available if IO_GPIO_NUM > 0) --
      gpio_o      => gpio_o,
      gpio_i      => gpio_i,
      -- primary UART0 (available if IO_UART0_EN = true) --
      --  => ports unconnected, actual signals come from alt_jtag_atlantic
      -- SPI (available if IO_SPI_EN = true) --
      spi_clk_o   => flash_sck,
      spi_dat_o   => flash_mosi_io0,
      spi_dat_i   => flash_miso_io1,
      spi_csn_o   => spi_n_cs,
      -- TWI (available if IO_TWI_EN = true) --
      twi_sda_i   => sda,
      twi_sda_o   => sda_o,
      twi_scl_i   => scl,
      twi_scl_o   => scl_o
    );

  -- Tristate I2C driver.
  sda <= '0' when (sda_o = '0') else 'Z';
  scl <= '0' when (scl_o = '0') else 'Z';

  gpio_i <= (others => '0');

  led_matrix( 7 downto  0) <= gpio_o( 7 downto  0);
  led_matrix(19 downto 12) <= gpio_o(15 downto  8);
  led_matrix(31 downto 24) <= gpio_o(23 downto 16);
  led_matrix(43 downto 36) <= gpio_o(31 downto 24);

  flash_n_cs <= spi_n_cs(0);

  -- Wishbone memory subsystem.
  wb_remap_inst : entity work.wb_remap
    generic map (
      MEMORY_MAP_FROM => WB_MEMORY_REMAP_FROM,
      MEMORY_MAP_TO   => WB_MEMORY_REMAP_TO
    )
    port map (
      -- Wishbone master interface --
      wb_orig_req  => wb_core_req,
      wb_remap_req => wb_remap_req
    );

  wb_core_rsp <= wb_remap_rsp;

  wb_mux_inst : entity work.wb_mux
    generic map (
      -- General --
      N_SLAVES   => WB_N_SLAVES_MUX,
      MEMORY_MAP => WB_MEMORY_MAP_MUX
    )
    port map (
      -- Wishbone master interface --
      wb_req_i => wb_remap_req,
      wb_rsp_o => wb_remap_rsp,
      -- Wishbone slave interface(s) --
      wb_req_o(0) => wb_sdram_req,
      wb_rsp_i(0) => wb_sdram_rsp
    );

  wb_sdram_inst : entity work.wb_sdram
    generic map (
      CLOCK_FREQUENCY => CLOCK_FREQUENCY
    )
    port map (
      -- Global control --
      clk => clk,
      rst => rst,
      -- Wishbone slave interface --
      wb_req => wb_sdram_req,
      wb_rsp => wb_sdram_rsp,
      -- SDRAM --
      sdram_addr  => sdram_addr,
      sdram_ba    => sdram_ba,
      sdram_n_cas => sdram_n_cas,
      sdram_cke   => sdram_cke,
      sdram_n_cs  => sdram_n_cs,
      sdram_d     => sdram_d,
      sdram_dqm   => sdram_dqm,
      sdram_n_ras => sdram_n_ras,
      sdram_n_we  => sdram_n_we,
      sdram_clk   => sdram_clk
    );

  -- TODO: cycloneive_jtag and alt_jtag_atlantic can't be used at the same time.
  --       The first uses the raw JTAG registers, the other the SLD system.

  -- jtag_atlantic_inst : alt_jtag_atlantic
  --   generic map (
  --     SLD_AUTO_INSTANCE_INDEX => "YES",
  --     INSTANCE_ID             => 0,
  --     LOG2_RXFIFO_DEPTH       => 4,
  --     LOG2_TXFIFO_DEPTH       => 4
  --   )
  --   port map (
  --     clk     => clk,
  --     rst_n   => not rst,
  --     -- data from FPGA --
  --     r_dat   => stuff_fwd.data,
  --     r_val   => stuff_fwd.valid,
  --     r_ena   => stuff_rev.ready,
  --     -- data to FPGA --
  --     t_dat   => atlantic_fwd.data,
  --     t_dav   => atlantic_rev.ready,
  --     t_ena   => atlantic_fwd.valid,
  --     t_pause => open
  --   );

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
