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

use work.st_pkg.all;

entity top is
  port (
    -- Global control --
    clk   : in std_ulogic; -- global clock, rising edge
    arstn : in std_ulogic; -- global reset, low-active, async
    -- LED matrix --
    led_matrix : out std_ulogic_vector((10*12)-1 downto 0) := (others => '0');
    -- UART ---
    rx : in std_ulogic;
    tx : out std_ulogic;
    -- I2C ---
    sda : inout std_ulogic;
    scl : inout std_ulogic;
    -- JTAG --
    altera_reserved_tck : in std_ulogic;
    altera_reserved_tms : in std_ulogic;
    altera_reserved_tdi : in std_ulogic;
    altera_reserved_tdo : out std_ulogic;
  );
end entity;

architecture rtl of top is

  component cycloneive_jtag
    generic (
      lpm_type : string := "cycloneive_jtag"
    );
    port (
      tms         : in std_ulogic := '0';
      tck         : in std_ulogic := '0';
      tdi         : in std_ulogic := '0';
      tdouser     : in std_ulogic := '0';
      tdo         : out std_ulogic;
      tmsutap     : out std_ulogic;
      tckutap     : out std_ulogic;
      tdiutap     : out std_ulogic;
      shiftuser   : out std_ulogic;
      clkdruser   : out std_ulogic;
      updateuser  : out std_ulogic;
      runidleuser : out std_ulogic;
      usr1user    : out std_ulogic;
    );
  end component;

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

  signal gpio_i, gpio_o : std_ulogic_vector(31 downto 0);
  signal sda_o, scl_o   : std_ulogic;

  signal user_tck, user_tdi, user_tdo, user_tms : std_logic;

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
      CLOCK_FREQUENCY  => 50_000_000,
      -- Boot Configuration --
      BOOT_MODE_SELECT => 0, -- 0 = bootloader, 2 = IMEM
      -- On-Chip Debugger (OCD) --
      OCD_EN           => true,
      -- Internal Instruction memory (IMEM) --
      IMEM_EN          => true,
      IMEM_SIZE        => 32*1024,
      -- Internal Data memory (DMEM) --
      DMEM_EN          => true,
      DMEM_SIZE        => 8*1024,
      -- General-Purpose Input/Output Controller (GPIO) --
      IO_GPIO_NUM      => 32,
      -- Universal Asynchronous Receiver/Transmitter (UART0/UART1) --
      IO_UART0_EN      => true,
      IO_UART0_RX_FIFO => 32,
      IO_UART0_TX_FIFO => 32,
      -- Two-Wire Interface (TWI Host, TWD Device) --
      IO_TWI_EN        => true,
      IO_TWI_FIFO      => 1
    )
    port map (
      -- Global control --
      clk_i       => clk,
      rstn_i      => not rst,
      -- JTAG on-chip debugger interface (available if OCD_EN = true) --
      jtag_tck_i  => user_tck,
      jtag_tdi_i  => user_tdi,
      jtag_tdo_o  => user_tdo,
      jtag_tms_i  => user_tms,
      -- GPIO (available if IO_GPIO_NUM > 0) --
      gpio_o      => gpio_o,
      gpio_i      => gpio_i,
      -- primary UART0 (available if IO_UART0_EN = true) --
      uart0_txd_o => tx,
      uart0_rxd_i => rx,
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

  -- Altera JTAG atom.
  jtag_inst : cycloneive_jtag
    port map (
      tms         => altera_reserved_tms,
      tck         => altera_reserved_tck,
      tdi         => altera_reserved_tdi,
      tdo         => altera_reserved_tdo,
      tdouser     => user_tdo,
      tmsutap     => user_tms,
      tckutap     => user_tck,
      tdiutap     => user_tdi,
      shiftuser   => open, -- don't care, dtm has it's own JTAG FSM
      clkdruser   => open,
      updateuser  => open,
      runidleuser => open,
      usr1user    => open
    );

  -- TODO: cycloneive_jtag and alt_jtag_atlantic can't be used at the same time.
  --       The first uses the raw JTAG registers, the other the SDL system.

  -- jtag_atlantic_inst : alt_jtag_atlantic
  --   generic map (
  --     INSTANCE_ID             => 0,
  --     LOG2_RXFIFO_DEPTH       => 4,
  --     LOG2_TXFIFO_DEPTH       => 4,
  --     SLD_AUTO_INSTANCE_INDEX => "YES"
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
