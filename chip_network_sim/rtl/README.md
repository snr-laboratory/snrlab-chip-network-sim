# User-Provided RTL

RTLswarm does not distribute a production RTL design. Place each local RTL
variant under this directory using a layout such as:

```text
rtl/
  <variant>/
    src/
      <SystemVerilog sources>
```

Then update the RTL source path, source-file list, top module, and chip build
target in [`../CMakeLists.txt`](../CMakeLists.txt) to match that design. The
integration procedure is described in
[`../doc/integrate_rtl_mode.md`](../doc/integrate_rtl_mode.md).

The repository ignores RTL subdirectories so local or third-party designs are
not accidentally committed. This README remains tracked so a fresh checkout
still contains the expected `rtl/` integration point.

Optional internal visibility belongs to a simulator-side Verilator control
file rather than to debug ports added to the RTL. Start with
[`../sim_core/config/example_debug_public.vlt`](../sim_core/config/example_debug_public.vlt)
and follow [`../doc/internal_inspection_mode.md`](../doc/internal_inspection_mode.md).
