# spec

The ratified target specification and its decision records. Spec changes go
through a new decision record; nothing here is relaxed to make a result pass.

| File | Contents |
|---|---|
| [npu.md](npu.md) | The spec: parameters, arithmetic, golden-model interface, SRAM, host interface, corners, workloads, deferred rows, port seam |
| [floorplan-sketch.md](floorplan-sketch.md) | First floorplan sketch: banks, array, bus widths, SRAM area fraction (estimate), congestion note |
| [decisions/0001-dataflow.md](decisions/0001-dataflow.md) | Output-stationary dataflow, with the SRAM bandwidth arithmetic |
| [decisions/0002-sram-source.md](decisions/0002-sram-source.md) | SRAM macro source (adopt-or-record) |
