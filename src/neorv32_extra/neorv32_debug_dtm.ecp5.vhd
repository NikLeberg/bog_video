-- ================================================================================ --
-- NEORV32 OCD - RISC-V-Compatible Debug Transport Module (DTM)                     --
-- -------------------------------------------------------------------------------- --
-- Compatible to RISC-V debug spec. versions 0.13 and 1.0.                          --
-- -------------------------------------------------------------------------------- --
-- The NEORV32 RISC-V Processor - https://github.com/stnolting/neorv32              --
-- Copyright (c) NEORV32 contributors.                                              --
-- Copyright (c) 2020 - 2026 Stephan Nolting. All rights reserved.                  --
-- Licensed under the BSD-3-Clause license, see LICENSE for details.                --
-- SPDX-License-Identifier: BSD-3-Clause                                            --
-- -------------------------------------------------------------------------------- --
-- Original content by Stephan Nolting.                                             --
-- Modified by Niklaus Leuenberger to support Lattice ECP5 FPGA JTAGG atom.         --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;

library neorv32;
use neorv32.neorv32_package.all;

entity neorv32_debug_dtm is
  generic (
    IDCODE_VERSION : std_ulogic_vector(3 downto 0);  -- version
    IDCODE_PARTID  : std_ulogic_vector(15 downto 0); -- part number
    IDCODE_MANID   : std_ulogic_vector(10 downto 0)  -- manufacturer id
  );
  port (
    -- global control --
    clk_i      : in  std_ulogic; -- global clock line
    rstn_i     : in  std_ulogic; -- global reset line, low-active
    -- JTAG connection (unused) --
    jtag_tck_i : in  std_ulogic;        -- serial clock
    jtag_tdi_i : in  std_ulogic;        -- serial data input
    jtag_tdo_o : out std_ulogic := '0'; -- serial data output
    jtag_tms_i : in  std_ulogic;        -- mode select
    -- debug module interface (DMI) --
    dmi_req_o  : out dmi_req_t;  -- request
    dmi_rsp_i  : in  dmi_rsp_t   -- response
  );
end neorv32_debug_dtm;

architecture neorv32_debug_dtm_ecp5_rtl of neorv32_debug_dtm is

  -- TAP data registers, adapted for Lattice ECP5 ER1 and ER2 addresses --
  -- OpenOCD needs to be informed of these addresses:
  -- > riscv set_ir dtmcs 0x32
  -- > riscv set_ir dmi 0x38
  constant addr_dtmcs_c : std_ulogic_vector(7 downto 0) := "00110010"; -- ER1 0x32
  constant addr_dmi_c   : std_ulogic_vector(7 downto 0) := "00111000"; -- ER2 0x38
  --
  constant size_dtmcs_c : natural := 32;
  constant size_dmi_c   : natural := 7+32+2; -- 7-bit address + 32-bit data + 2-bit operation/status

  -- ECP5 JTAGG atom.
  component JTAGG
    generic (
      ER1 : string := "ENABLED";
      ER2 : string := "ENABLED"
    );
    port (
      JSHIFT  : out std_ulogic; -- TAP state shift-DR
      JUPDATE : out std_ulogic; -- TAP state update-DR
      JRSTN   : out std_ulogic; -- TAP state test-logic-reset
      JRTI1   : out std_ulogic; -- ER1 active: TAP state run-test/idle
      JRTI2   : out std_ulogic; -- ER2 active: TAP state run-test/idle
      JCE1    : out std_ulogic; -- ER1 active: TAP state capture-DR or shift-DR
      JCE2    : out std_ulogic; -- ER2 active: TAP state capture-DR or shift-DR
      JTCK    : out std_ulogic; -- normal JTAG TCK
      JTDI    : out std_ulogic; -- normal JTAG TDI
      JTDO1   : in  std_ulogic; -- ER1 active: JTAG TDO
      JTDO2   : in  std_ulogic  -- ER2 active: JTAG TDO
    );
  end component;

  -- ECP5 JTAGG interface --
  signal tck, trstn, tdi, shift, shift_dly, update : std_ulogic;
  signal rti_dtmcs, ce_dtmcs, tdo_dtmcs            : std_ulogic;
  signal rti_dmi, ce_dmi, tdo_dmi                  : std_ulogic;

  -- TAP registers --
  signal dreg_dtmcs : std_ulogic_vector(size_dtmcs_c-1 downto 0);
  signal dreg_dmi   : std_ulogic_vector(size_dmi_c-1 downto 0);
  signal dreg_dtmcs_sel, dreg_dmi_sel : std_ulogic;

  -- CDC flags --
  signal dtmcs_toggle, dtmcs_update, dmi_toggle, dmi_update : std_ulogic;
  signal dtmcs_toggle_ff, dmi_toggle_ff : std_ulogic_vector(2 downto 0);

  -- misc --
  signal dmihardreset, dmireset : std_ulogic;

  -- debug module interface controller --
  signal dmi : dmi_req_t;
  signal busy, err, dmi_rsp_write : std_ulogic;

begin

  -- JTAG Primitive -------------------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  jtagg_inst : JTAGG
    generic map (
      ER1 => "ENABLED",
      ER2 => "ENABLED"
    )
    port map (
      JSHIFT  => shift,
      JUPDATE => update,
      JRSTN   => trstn,
      JRTI1   => rti_dtmcs,
      JRTI2   => rti_dmi,
      JCE1    => ce_dtmcs,
      JCE2    => ce_dmi,
      JTCK    => tck,
      JTDI    => tdi,
      JTDO1   => tdo_dtmcs,
      JTDO2   => tdo_dmi
    );


  -- Tap Register Access --------------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  reg_access: process(trstn, tck)
  begin
    -- Using JTAGG with netxpnr and project trellis is a bit crooked. Some sources suggest this
    -- is due to missing hold timing constraints in trellis. Others claim that the JTAGG itself
    -- is weird to use because it internally registers TDI on rising TCK but also TDO on a
    -- falling TCK. Sources:
    -- https://github.com/Wren6991/Hazard3/blob/stable/hdl/debug/dtm/hazard3_ecp5_jtag_dtm.v
    -- https://github.com/OpenPOWERFoundation/microwatt/blob/master/dmi_dtm_ecp5.vhdl
    -- https://github.com/tomverbeure/ecp5_jtag/blob/main/colorlight_i5/README.md
    -- Maybe it is also just all of the above. What seems to reliably work is to sample the
    -- inputs delayed by a half TCK i.e. on the negative edge. And then shift one additional
    -- time after shift has actually gone low again to workaround the JTAGG internal TDI flop. 
    if (trstn = '0') then
      dreg_dtmcs     <= (others => '0');
      dreg_dmi       <= (others => '0');
      dreg_dtmcs_sel <= '0';
      dreg_dmi_sel   <= '0';
    elsif falling_edge(tck) then
      -- register select --
      if (rti_dtmcs = '1') then
        dreg_dtmcs_sel <= '1';
        dreg_dmi_sel   <= '0';
      elsif (rti_dmi = '1') then
        dreg_dtmcs_sel <= '0';
        dreg_dmi_sel   <= '1';
      end if;
      -- extend shift by one clock --
      shift_dly <= shift;
      -- dtmcs register input --
      if (dreg_dtmcs_sel = '1') then
        if (ce_dtmcs = '1') and (shift = '0') then -- capture
          dreg_dtmcs <= x"00000071";
        elsif (shift = '1') or (shift_dly = '1') then -- shift
          dreg_dtmcs <= tdi & dreg_dtmcs(dreg_dtmcs'left downto 1);
        end if;
      end if;
      -- dmi register input --
      if (dreg_dmi_sel = '1') then
        if (ce_dmi = '1') and (shift = '0') then -- capture
          -- Even though this is from clk_i domain, it is save to capture: All
          -- dmi accesses are ack-ed after 2 clks and then held stable. With
          -- f_tck <= f_clk this is always safe.
          dreg_dmi <= dmi.addr & dmi.data & err & err;
        elsif (shift = '1') or (shift_dly = '1') then -- shift
          dreg_dmi <= tdi & dreg_dmi(dreg_dmi'left downto 1);
        end if;
      end if;
    end if;
  end process reg_access;

  -- data register output --
  tdo_dtmcs <= dreg_dtmcs(0);
  tdo_dmi   <= dreg_dmi(0);

  -- dtmcs CDC --
  dtmcs_toggle    <= dtmcs_toggle xor (update and dreg_dtmcs_sel) when falling_edge(tck);
  dtmcs_toggle_ff <= dtmcs_toggle_ff(1 downto 0) & dtmcs_toggle   when rising_edge(clk_i);
  dtmcs_update    <= dtmcs_toggle_ff(2) xor dtmcs_toggle_ff(1);

  -- reset control --
  dtmcs_reset: process(rstn_i, clk_i)
  begin
    if (rstn_i = '0') then
      dmihardreset <= '0';
      dmireset     <= '0';
    elsif rising_edge(clk_i) then
      if (dtmcs_update = '1') then
        dmihardreset <= dreg_dtmcs(17);
        dmireset     <= dreg_dtmcs(16);
      end if;
    end if;
  end process dtmcs_reset;

  -- dmi request CDC ---
  dmi_toggle    <= dmi_toggle xor (update and dreg_dmi_sel)   when falling_edge(tck);
  dmi_toggle_ff <= dmi_toggle_ff(1 downto 0) & dmi_toggle when rising_edge(clk_i);
  dmi_update    <= dmi_toggle_ff(2) xor dmi_toggle_ff(1);


  -- Debug Module Interface -----------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  dmi_controller: process(rstn_i, clk_i)
  begin
    if (rstn_i = '0') then
      err  <= '0';
      busy <= '0';
      dmi  <= dmi_req_terminate_c;
    elsif rising_edge(clk_i) then
      -- sticky error: access attempt while DMI is busy --
      if (dmireset = '1') or (dmihardreset = '1') then
        err <= '0';
      elsif (dmi_update = '1') and (busy = '1') then
        err <= '1';
      end if;
      -- interface arbiter --
      dmi.op <= dmi_req_nop_c; -- default
      if (busy = '0') then -- idle: waiting for new request
        if (dmi_update = '1') then
          dmi.addr <= dreg_dmi(40 downto 34);
          dmi.data <= dreg_dmi(33 downto 2);
          dmi.op   <= dreg_dmi(1 downto 0);
          busy     <= or_reduce_f(dreg_dmi(1 downto 0));
        end if;
      elsif (dmi_rsp_i.ack = '1') or (dmihardreset = '1') then -- busy: wait for access termination
        dmi.data <= dmi_rsp_i.data;
        busy     <= '0';
      end if;
    end if;
  end process dmi_controller;

  -- DMI output --
  dmi_req_o <= dmi;


end neorv32_debug_dtm_ecp5_rtl;
