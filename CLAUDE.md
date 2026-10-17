# sky130-npu — agent instructions

Open-source canary block: a small INT8 neural-network accelerator with
banked SRAM on SkyWater sky130, designed and verified by AI agents.
**Digital.**

- **PDK**: SkyWater sky130 (open PDK, google/skywater-pdk), standard cells
  `sky130_fd_sc_hd`. Digital flow: cocotb + Icarus for simulation, Yosys for
  synthesis, OpenROAD for place-and-route and timing. Layout, DRC, and LVS
  through klayout-tools (`klt`).
- **The floorplan is the point, and the risk.** The block is SRAM-bound:
  several macros, wide buses between them and the array, and routing
  congestion around them. Decide bank count, port widths and placement
  together, early, and with a floorplan sketch rather than after RTL is
  done. Expect the tools to be weakest at macro placement and congestion,
  and file accordingly. A timing result through a macro is only as good as
  its Liberty view — record where the view came from.
- **Bit-exact or nothing.** The reference is an integer golden model,
  written once in this repo and committed. Every RTL result is compared to it
  bit for bit, including rounding and saturation in requantization. A
  "close enough" match is a failure.
- **Throughput honesty.** Peak MAC rate is a derived figure. Quote it only
  with the array utilization observed in simulation on a named workload, and
  only with the corner its clock came from. Never call a simulated or STA
  figure measured.
- **Scope discipline.** The SRAM macro is not designed here. Its source (the
  OpenRAM sky130 macros, the `sky130-sram-compiler` sibling, or standard-cell
  RAM) is an adopt-or-record decision under the fleet's reuse rule (a block
  is designed once), and whatever is imported is pinned in
  `reuse.lock.json`. No processor (the host is external), no floating
  point, no training.
- **This repo is master for the architecture.** `asap7-npu` is ported from
  this repo. The golden model, the RTL and the testbenches are designed here
  and stamped into the port, so keep array size a parameter and keep PDK
  specifics behind a clear seam.
- **Friction protocol (the canary's job)**: every time klayout-tools is
  awkward, missing a capability, or wrong for what you need, file an issue at
  `2AMLogic/klayout-tools` describing the tool gap generically — that tracker
  is scoped to the tool, so keep design-specific detail out of it and describe
  the gap, not the design.
- **Verification is the product**: no claim without a testbench. Recorded
  results are append-only evidence.
- Spec changes go through `spec/` with a decision record; agents do not relax
  the ratified spec to make results pass.
- **An 8 x 8 array at 50 MHz post-route is the target.** 4 x 4 at 25 MHz is
  the fallback and 16 x 16 at 100 MHz is a stretch. Do not let stretch-size
  requirements drive the architecture before the target closes.

<!-- BEGIN LOOM ORCHESTRATION -->
This repository uses [Loom](https://github.com/rjwalters/loom) for AI-powered development orchestration — see the Loom repository for the full guide (roles, labels, worktrees, configuration). When installed, Loom also writes a locally-substituted copy of that guide to `.loom/CLAUDE.md`.

Work is coordinated through `loom:` labels on issues and pull requests, and the same roles run either under `loom-daemon` or by hand in an attended session — daemon mode is optional. Create the labels once with `.loom/scripts/sync-labels.sh` (an install ships `.github/labels.yml` but does not create the labels on the forge). A pull request ready for review carries `loom:review-requested`; Judge reviews it and applies `loom:pr` (approved) or `loom:changes-requested`; Doctor fixes a `loom:changes-requested` pull request and returns it to `loom:review-requested`. Only a `loom:pr` pull request gets merged, and always via this repo's merge script (`.loom/scripts/merge-pr.sh`) — never a raw forge merge command such as `gh pr merge`. Full state machine: `.loom/docs/label-state-machine.md`.
<!-- END LOOM ORCHESTRATION -->
