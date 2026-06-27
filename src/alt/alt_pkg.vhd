-- =============================================================================
-- File:                    alt_pkg.vhd
-- Package:                 alt_pkg
-- Author:                  Niklaus Leuenberger <@NikLeberg>
-- SPDX-License-Identifier: MIT
-- Description:             Collection of Altera FPGA specific black boxes.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

package alt_pkg is

  -- Altera Cycline IVE JTAG primitive.
  -- See: https://tomverbeure.github.io/2021/10/30/Intel-JTAG-Primitive.html
  component cycloneive_jtag
    generic (
      lpm_type : string := "cycloneive_jtag";
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

  -- (Undocumented) Altera megafunction that lets you send/receive arbitraty
  -- data through JTAG via the SLD system.
  -- See: https://tomverbeure.github.io/2021/05/08/Write-Your-Own-C-and-Python-Clients-for-Intel-JTAG-UART-with-libjtag_atlantic.html
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

  -- Virtual JTAG Interface (VJI) megafunction.
  -- Ports marked optional are for debugging purposes only.
  component sld_virtual_jtag
    generic (
      lpm_hint                : string  := "UNUSED";
      lpm_type                : string  := "sld_virtual_jtag";
      sld_auto_instance_index : string  := "YES";
      sld_instance_index      : natural := 0;
      sld_ir_width            : natural := 1;
      sld_sim_action          : string  := "UNUSED";
      sld_sim_n_scan          : natural := 0;
      sld_sim_total_length    : natural := 0;
    );
    port (
      ir_in              : out std_ulogic_vector(SLD_IR_WIDTH-1 downto 0);
      ir_out             : in  std_ulogic_vector(SLD_IR_WIDTH-1 downto 0);
      jtag_state_cdr     : out std_ulogic; -- optional
      jtag_state_cir     : out std_ulogic; -- optional
      jtag_state_e1dr    : out std_ulogic; -- optional
      jtag_state_e1ir    : out std_ulogic; -- optional
      jtag_state_e2dr    : out std_ulogic; -- optional
      jtag_state_e2ir    : out std_ulogic; -- optional
      jtag_state_pdr     : out std_ulogic; -- optional
      jtag_state_pir     : out std_ulogic; -- optional
      jtag_state_rti     : out std_ulogic; -- optional
      jtag_state_sdr     : out std_ulogic; -- optional
      jtag_state_sdrs    : out std_ulogic; -- optional
      jtag_state_sir     : out std_ulogic; -- optional
      jtag_state_sirs    : out std_ulogic; -- optional
      jtag_state_tlr     : out std_ulogic; -- optional
      jtag_state_udr     : out std_ulogic; -- optional
      jtag_state_uir     : out std_ulogic; -- optional
      tck                : out std_ulogic;
      tdi                : out std_ulogic;
      tdo                : in  std_ulogic;
      tms                : out std_ulogic; -- optional
      virtual_state_cdr  : out std_ulogic;
      virtual_state_cir  : out std_ulogic;
      virtual_state_e1dr : out std_ulogic;
      virtual_state_e2dr : out std_ulogic;
      virtual_state_pdr  : out std_ulogic;
      virtual_state_sdr  : out std_ulogic;
      virtual_state_udr  : out std_ulogic;
      virtual_state_uir  : out std_ulogic;
    );
  end component;

end package;
