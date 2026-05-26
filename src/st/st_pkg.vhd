-- =============================================================================
-- File:                    st_pkg.vhd
-- Package:                 st_pkg
-- Author:                  Niklaus Leuenberger <@NikLeberg>
-- SPDX-License-Identifier: MIT
-- Description:             Package of streaming types and primitives.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package st_pkg is

  -- Forward: From upstream source to downstream sink.
  type st_fwd_t is record
    data  : std_ulogic_vector;
    valid : std_ulogic; -- 1 = valid beat
    last  : std_ulogic; -- 1 = last beat of a multi beat packet, optional
  end record;

  -- Reverse: From downstream sink to upstream source.
  type st_rev_t is record
    ready : std_ulogic; -- 1 = sink is ready to accept data
  end record;

end package;
