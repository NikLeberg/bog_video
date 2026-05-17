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
  -- Stream link
  type st_t is record
    data  : std_ulogic_vector;
    valid : std_ulogic;
    last  : std_ulogic;
    ready : std_ulogic;
  end record;

  view st_source_v of st_t is
    data  : out;
    valid : out;
    last  : out;
    ready : in;
  end view;

  alias st_sink_v is st_source_v'converse;
end package;
