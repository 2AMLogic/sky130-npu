"""Environment probe for flow/sram/setup.sh: 16 words x 32 bits, 1rw1r.

Same shape as the pinned VLSIDA configs and the same sky130_sram_common.py
(exec'd from the pinned sky130_sram_macros checkout, path in SRAM_COMMON_PY),
with characterization, DRC/LVS and the SPICE-heavy steps off so it runs in
minutes. It proves OpenRAM gets past bitcell creation. It is not a macro the
design uses.
"""

import os

word_size = 32
num_words = 16
write_size = 8
num_rw_ports = 1
num_r_ports = 1
num_w_ports = 0
ports_human = '1rw1r'
human_byte_size = "probe"

exec(open(os.environ["SRAM_COMMON_PY"]).read())

# Overrides after the common config (which sets check_lvsdrc = True).
check_lvsdrc = False
analytical_delay = True
use_nix = False  # OpenRAM defaults to a Nix bootstrap; this flow uses a venv
output_name = "probe_sram_{word_size}x{num_words}_{ports_human}".format(**locals())
output_path = os.environ["SRAM_OUT_DIR"]
