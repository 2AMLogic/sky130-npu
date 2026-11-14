"""Corner-attempt config for sky130_sram_4kbyte_1rw1r_32x1024_8 (issue #153).

Same shape and the same four overrides as gen_4kb_1rw1r_32x1024.py, which
produced the pinned TT view, plus exactly one corner override. This config
exists to answer spec gaps G1 (ss_100C_1v60) and G2 (ff_n40C_1v95): can the
pinned OpenRAM toolchain emit Liberty at those PVT points at all?

  use_specified_corners  the one addition. OpenRAM characterizes exactly this
                         list and nothing else: compiler/characterizer/lib.py:107
                         tests it before any corner generation, so the whole
                         generated-corner block is skipped.

TT stays first in the list on purpose. The run then re-derives the
already-pinned TT view in the same job, which is the baseline the corner
numbers are compared against before anything is pinned. A corner .lib whose
tables equal TT's would be a renamed copy, not a corner view.

Why not the other routes:
  nominal_corner_only = False      compiler/globals.py:534 reads
                                   tech.spice["fet_models"], which the sky130
                                   tech does not define (it has
                                   "fet_libraries") -> KeyError. And even
                                   patched, lib.py:119-130 varies one PVT axis
                                   at a time about nominal, so SS/FF would come
                                   out at nominal 1.8 V / 25 C, not at the
                                   spec's points.
  only_use_config_corners = True   lib.py:110-117 never binds nom_corner, which
                                   lib.py:132 then dereferences ->
                                   UnboundLocalError. Its cross product would
                                   also be up to 27 corners, not 3.

nominal_corner_only is left at the pinned config's True. With
use_specified_corners set it is not consulted for the corner list, and leaving
it True keeps set_default_corner() on its single-element path so the
unconditional min()/max() calls at lib.py:94-99 stay well defined.

Delay model is unchanged: OpenRAM's analytical (Elmore) default. An analytical
view is NOT a SPICE-characterized one.
"""
import os

__file__ = os.environ["SRAM_MACRO_CONFIG"]
exec(open(__file__).read())

use_nix = False
check_lvsdrc = False
output_path = os.environ["SRAM_OUT_DIR"]
output_name = "sky130_sram_4kbyte_1rw1r_32x1024_8"

# The PVT points of spec/npu.md section 7, in OpenRAM's (process, volts, degC)
# form. Chosen to match the std-cell corners by PVT, not by file name:
#   ("TT", 1.8,  25)  <-> tt_025C_1v80   (baseline; already pinned)
#   ("SS", 1.60, 100) <-> ss_100C_1v60   (gap G1, setup signoff)
#   ("FF", 1.95, -40) <-> ff_n40C_1v95   (gap G2, hold signoff)
use_specified_corners = [("TT", 1.8, 25), ("SS", 1.60, 100), ("FF", 1.95, -40)]
