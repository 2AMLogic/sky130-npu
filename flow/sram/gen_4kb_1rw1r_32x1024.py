"""Generate sky130_sram_4kbyte_1rw1r_32x1024_8 from the pinned VLSIDA config.

Runs the pinned config (path in SRAM_MACRO_CONFIG) unchanged, then applies the
only overrides this flow needs. Every override is listed in the PR and the lock.
  use_nix        = False  OpenRAM defaults to a Nix bootstrap; this flow uses a venv.
  check_lvsdrc   = False  magic and netgen are not installed on the worker.
  output_path             an out-of-repo directory (SRAM_OUT_DIR).
  output_name    = ...4kbyte_...  the pinned config formats human_byte_size as "4kbytes", so
                          it would emit module/MACRO sky130_sram_4kbytes_...; the wrapper,
                          black box, stand-in and synth records all use ..._4kbyte_....
                          The name is the only thing this changes.
Corners are NOT touched: the pinned config sets nominal_corner_only = True, so
only a TT Liberty comes out. Delay model is OpenRAM's default (analytical).
"""
import os

__file__ = os.environ["SRAM_MACRO_CONFIG"]
exec(open(__file__).read())

use_nix = False
check_lvsdrc = False
output_path = os.environ["SRAM_OUT_DIR"]
output_name = "sky130_sram_4kbyte_1rw1r_32x1024_8"
