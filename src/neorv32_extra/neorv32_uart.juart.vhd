-- ================================================================================ --
-- NEORV32 SoC - Universal Asynchronous Receiver and Transmitter (UART)             --
-- -------------------------------------------------------------------------------- --
-- The NEORV32 RISC-V Processor - https://github.com/stnolting/neorv32              --
-- Copyright (c) NEORV32 contributors.                                              --
-- Copyright (c) 2020 - 2026 Stephan Nolting. All rights reserved.                  --
-- Licensed under the BSD-3-Clause license, see LICENSE for details.                --
-- SPDX-License-Identifier: BSD-3-Clause                                            --
-- -------------------------------------------------------------------------------- --
-- Original content by Stephan Nolting.                                             --
-- Modified by Niklaus Leuenberger to use Altera JTAG UART (Atlantic) megafunction. --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32;
use neorv32.neorv32_package.all;

entity neorv32_uart is
  generic (
    UART_RX_FIFO : natural range 1 to 2**15; -- RX FIFO depth, has to be a power of two, min 1
    UART_TX_FIFO : natural range 1 to 2**15  -- TX FIFO depth, has to be a power of two, min 1
  );
  port (
    clk_i       : in  std_ulogic;                    -- global clock line
    rstn_i      : in  std_ulogic;                    -- global reset line, low-active, async
    bus_req_i   : in  bus_req_t;                     -- bus request
    bus_rsp_o   : out bus_rsp_t;                     -- bus response
    clkgen_i    : in  std_ulogic_vector(7 downto 0); -- prescaled clock enables
    uart_txd_o  : out std_ulogic;                    -- serial TX line
    uart_rxd_i  : in  std_ulogic;                    -- serial RX line
    uart_rtsn_o : out std_ulogic;                    -- ready to receive ("RTR"), low-active, optional
    uart_ctsn_i : in  std_ulogic;                    -- allowed to transmit, low-active, optional
    irq_o       : out std_ulogic                     -- interrupt
  );
end neorv32_uart;

architecture neorv32_uart_juart_rtl of neorv32_uart is

  component alt_jtag_atlantic is
    generic (
      SLD_AUTO_INSTANCE_INDEX : string  := "YES";
      INSTANCE_ID             : integer := 0;
      LOG2_RXFIFO_DEPTH       : integer;
      LOG2_TXFIFO_DEPTH       : integer;
    );
    port (
      clk   : in std_ulogic;
      rst_n : in std_ulogic;
      -- data from FPGA --
      r_dat : in std_ulogic_vector(7 downto 0);
      r_val : in std_ulogic;  -- valid
      r_ena : out std_ulogic; -- ready
      -- data to FPGA --
      t_dat   : out std_ulogic_vector(7 downto 0);
      t_dav   : in std_ulogic;  -- ready
      t_ena   : out std_ulogic; -- valid
      t_pause : out std_ulogic;
    );
  end component;

  -- control register bits --
  constant ctrl_en_c            : natural :=  0; -- r/w: UART enable
  constant ctrl_sim_en_c        : natural :=  1; -- r/w: simulation-mode enable
  constant ctrl_hwfc_en_c       : natural :=  2; -- r/w: enable RTS/CTS hardware flow-control
  constant ctrl_prsc0_c         : natural :=  3; -- r/w: baud prescaler, bit 0 (LSB)
  constant ctrl_prsc2_c         : natural :=  5; -- r/w: baud prescaler, bit 2 (MSB)
  constant ctrl_baud0_c         : natural :=  6; -- r/w: baud divisor, bit 0 (LSB)
  constant ctrl_baud9_c         : natural := 15; -- r/w: baud divisor, bit 9 (MSB)
  constant ctrl_rx_nempty_c     : natural := 16; -- r/-: RX FIFO not empty
  constant ctrl_rx_full_c       : natural := 17; -- r/-: RX FIFO full
  constant ctrl_tx_empty_c      : natural := 18; -- r/-: TX FIFO empty
  constant ctrl_tx_nfull_c      : natural := 19; -- r/-: TX FIFO not full
  constant ctrl_irq_rx_nempty_c : natural := 20; -- r/w: IRQ if RX FIFO not empty
  constant ctrl_irq_rx_full_c   : natural := 21; -- r/w: IRQ if RX FIFO full
  constant ctrl_irq_tx_empty_c  : natural := 22; -- r/w: IRQ if TX FIFO empty
  constant ctrl_irq_tx_nfull_c  : natural := 23; -- r/w: IRQ if TX FIFO not full
  --
  constant ctrl_rx_over_c       : natural := 30; -- r/-: RX FIFO overflow
  constant ctrl_tx_busy_c       : natural := 31; -- r/-: UART transmitter is busy and TX FIFO not empty

  -- data register bits --
  constant data_rtx_lsb_c     : natural :=  0; -- r/w: RX/TX data LSB
  constant data_rtx_msb_c     : natural :=  7; -- r/w: RX/TX data MSB
  constant data_rx_fifo_lsb_c : natural :=  8; -- r/-: log2(RX FIFO size) LSB
  constant data_rx_fifo_msb_c : natural := 11; -- r/-: log2(RX FIFO size) MSB
  constant data_tx_fifo_lsb_c : natural := 12; -- r/-: log2(TX FIFO size) LSB
  constant data_tx_fifo_msb_c : natural := 15; -- r/-: log2(TX FIFO size) MSB

  -- helpers --
  constant log2_rx_fifo_c : natural := index_size_f(UART_RX_FIFO);
  constant log2_tx_fifo_c : natural := index_size_f(UART_TX_FIFO);

  -- jtag atlantic interface --
  type atlantic_tx_t is record
    data         : std_ulogic_vector(7 downto 0);
    valid, ready : std_ulogic;
  end record;
  signal tx : atlantic_tx_t;

  type atlantic_rx_t is record
    data, data_ff          : std_ulogic_vector(7 downto 0);
    valid, valid_ff, ready : std_ulogic;
  end record;
  signal rx : atlantic_rx_t;

  type atlantic_host_t is record
    pause, had_contact, connected : std_ulogic;
    tout_counter                  : unsigned(13 downto 0);
  end record;
  signal host : atlantic_host_t;

  -- control register --
  type ctrl_t is record
    enable        : std_ulogic;
    sim_mode      : std_ulogic;
    hwfc_en       : std_ulogic;
    prsc          : std_ulogic_vector(2 downto 0);
    baud          : std_ulogic_vector(9 downto 0);
    irq_rx_nempty : std_ulogic;
    irq_rx_full   : std_ulogic;
    irq_tx_empty  : std_ulogic;
    irq_tx_nfull  : std_ulogic;
  end record;
  signal ctrl : ctrl_t;

begin

  -- Bus Access -----------------------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  bus_access: process(rstn_i, clk_i)
  begin
    if (rstn_i = '0') then
      bus_rsp_o          <= rsp_terminate_c;
      ctrl.enable        <= '0';
      ctrl.sim_mode      <= '0';
      ctrl.hwfc_en       <= '0';
      ctrl.prsc          <= (others => '0');
      ctrl.baud          <= (others => '0');
      ctrl.irq_rx_nempty <= '0';
      ctrl.irq_rx_full   <= '0';
      ctrl.irq_tx_empty  <= '0';
      ctrl.irq_tx_nfull  <= '0';
    elsif rising_edge(clk_i) then
      -- bus handshake --
      bus_rsp_o.ack  <= bus_req_i.stb;
      bus_rsp_o.err  <= '0';
      bus_rsp_o.data <= (others => '0');
      -- bus access --
      if (bus_req_i.stb = '1') then
        if (bus_req_i.rw = '1') then -- write access
          if (bus_req_i.addr(2) = '0') then -- control register
            ctrl.enable        <= bus_req_i.data(ctrl_en_c);
            ctrl.sim_mode      <= bus_req_i.data(ctrl_sim_en_c) and bool_to_ulogic_f(is_simulation_c);
            ctrl.hwfc_en       <= bus_req_i.data(ctrl_hwfc_en_c);
            ctrl.prsc          <= bus_req_i.data(ctrl_prsc2_c downto ctrl_prsc0_c);
            ctrl.baud          <= bus_req_i.data(ctrl_baud9_c downto ctrl_baud0_c);
            ctrl.irq_rx_nempty <= bus_req_i.data(ctrl_irq_rx_nempty_c);
            ctrl.irq_rx_full   <= bus_req_i.data(ctrl_irq_rx_full_c);
            ctrl.irq_tx_empty  <= bus_req_i.data(ctrl_irq_tx_empty_c);
            ctrl.irq_tx_nfull  <= bus_req_i.data(ctrl_irq_tx_nfull_c);
          end if;
        else -- read access
          if (bus_req_i.addr(2) = '0') then -- control register
            bus_rsp_o.data(ctrl_en_c)                        <= ctrl.enable;
            bus_rsp_o.data(ctrl_sim_en_c)                    <= ctrl.sim_mode and bool_to_ulogic_f(is_simulation_c);
            bus_rsp_o.data(ctrl_hwfc_en_c)                   <= ctrl.hwfc_en;
            bus_rsp_o.data(ctrl_prsc2_c downto ctrl_prsc0_c) <= ctrl.prsc;
            bus_rsp_o.data(ctrl_baud9_c downto ctrl_baud0_c) <= ctrl.baud;
            bus_rsp_o.data(ctrl_rx_nempty_c)                 <= rx.valid_ff;
            bus_rsp_o.data(ctrl_rx_full_c)                   <= '0'; -- not supported
            bus_rsp_o.data(ctrl_tx_empty_c)                  <= tx.ready or not host.connected; -- force empty = 1 if unconnected
            bus_rsp_o.data(ctrl_tx_nfull_c)                  <= tx.ready or not host.connected; -- force nfull = 1 if unconnected
            bus_rsp_o.data(ctrl_irq_rx_nempty_c)             <= ctrl.irq_rx_nempty;
            bus_rsp_o.data(ctrl_irq_rx_full_c)               <= ctrl.irq_rx_full;
            bus_rsp_o.data(ctrl_irq_tx_empty_c)              <= ctrl.irq_tx_empty;
            bus_rsp_o.data(ctrl_irq_tx_nfull_c)              <= ctrl.irq_tx_nfull;
            bus_rsp_o.data(ctrl_rx_over_c)                   <= '0'; -- not possible SW buffers it
            bus_rsp_o.data(ctrl_tx_busy_c)                   <= (not tx.ready) and host.connected; -- force busy = 0 if unconnected
          else -- data register
            bus_rsp_o.data(data_rtx_msb_c     downto data_rtx_lsb_c)     <= rx.data_ff;
            bus_rsp_o.data(data_rx_fifo_msb_c downto data_rx_fifo_lsb_c) <= std_ulogic_vector(to_unsigned(log2_rx_fifo_c, 4));
            bus_rsp_o.data(data_tx_fifo_msb_c downto data_tx_fifo_lsb_c) <= std_ulogic_vector(to_unsigned(log2_tx_fifo_c, 4));
          end if;
        end if;
      end if;
    end if;
  end process bus_access;

  -- JUART Instance -------------------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  jtag_atlantic_inst : alt_jtag_atlantic
    generic map (
      SLD_AUTO_INSTANCE_INDEX => "YES",
      INSTANCE_ID             => 0,
      LOG2_RXFIFO_DEPTH       => log2_rx_fifo_c,
      LOG2_TXFIFO_DEPTH       => log2_tx_fifo_c
    )
    port map (
      clk     => clk_i,
      rst_n   => rstn_i,
      -- data from FPGA --
      r_dat   => tx.data,
      r_val   => tx.valid,
      r_ena   => tx.ready,
      -- data to FPGA --
      t_dat   => rx.data,
      t_dav   => rx.ready,
      t_ena   => rx.valid,
      t_pause => host.pause
    );

  tx.data  <= bus_req_i.data(data_rtx_msb_c downto data_rtx_lsb_c);
  tx.valid <= host.connected when (bus_req_i.stb = '1') and (bus_req_i.rw = '1') and (bus_req_i.addr(2) = '1') else '0';

  rx_stash: process(rstn_i, clk_i)
  begin
    if (rstn_i = '0') then
      rx.valid_ff <= '0';
    elsif rising_edge(clk_i) then
      if (rx.valid_ff = '0') then
        if (rx.valid = '1') then
          rx.valid_ff <= '1';
          rx.data_ff  <= rx.data;
        end if;
      else
        if (bus_req_i.stb = '1') and (bus_req_i.rw = '0') and (bus_req_i.addr(2) = '1') then
          rx.valid_ff <= '0';
        end if;
      end if;
    end if;
  end process rx_stash;

  rx.ready <= not rx.valid_ff and not rx.valid;

  host_tout: process(rstn_i, clk_i)
  begin
    if (rstn_i = '0') then
      host.had_contact  <= '0';
      host.tout_counter <= (others => '0');
    elsif rising_edge(clk_i) then
      if (host.pause = '1') then
        host.had_contact  <= '1';
        host.tout_counter <= (others => '0');
      elsif (host.had_contact = '1') and (host.tout_counter(13) = '0') then
        if (clkgen_i(clk_div4096_c) = '1') then
          host.tout_counter <= host.tout_counter + 1;
        end if;
      end if;
    end if;
  end process host_tout;

  -- timeout the host if it never had any connection or the counter overflowed
  host.connected <= host.had_contact and not host.tout_counter(13);


  -- Interrupt Generator --------------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  irq_gen: process(rstn_i, clk_i)
  begin
    if (rstn_i = '0') then
      irq_o <= '0';
    elsif rising_edge(clk_i) then
      irq_o <= ctrl.enable and (
               (ctrl.irq_tx_empty  and (tx.ready or not host.connected)) or -- TX FIFO empty
               (ctrl.irq_tx_nfull  and (tx.ready or not host.connected)) or -- TX FIFO not full
               (ctrl.irq_rx_nempty and rx.valid_ff));                       -- RX FIFO not empty
    end if;
  end process irq_gen;

  -- IDLE unused IO pins
  uart_txd_o  <= '1';
  uart_rtsn_o <= '1';

end neorv32_uart_juart_rtl;
