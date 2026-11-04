# openfpga-VIC20

VIC20_MiSTer ported to the Analogue Pocket. How the core is built: [docs/architecture.md](docs/architecture.md).
User-facing docs: [README.md](README.md), [INSTALL.md](INSTALL.md).

## Tests

- `make -C sim`: unit benches (Icarus, nvc), a few minutes.
- No full-system simulation yet: openfpga-C64's `sim/system` (Verilator + GHDL) is the model for one.

## Release flow

A release is a tag plus a GitHub release carrying the bitstream built from that tag. The installers
(`install.sh`, `install.ps1`) download `defgenx.VIC20.zip` from the release with the highest `vX.Y.Z`
tag, pre-releases included. A tag with no release is never installed.

1. Run the test benches; they must pass.
2. Bump `version` (and `date_release`, `YYYY-MM-DD`) in `dist/Cores/defgenx.VIC20/core.json`.
3. `./build.sh`: Quartus in Docker (about 30 minutes), then it packages `defgenx.VIC20.zip` and checks
   the definition JSON. Check that `src/fpga/output_files/ap_core.sta.summary` has no negative slack.
4. Commit the sources together with what the build changed: `dist/Cores/defgenx.VIC20/vic20.rbf_r`,
   `src/fpga/apf/build_id.mif` and `core.json`. Push `main`.
5. Tag that commit `vX.Y.Z` (annotated), matching `core.json`, and push the tag. The bitstream at a
   tag must be built from the sources at that tag. Never tag a commit whose `vic20.rbf_r` is older.
6. `gh release create vX.Y.Z --prerelease --title "VIC-20 vX.Y.Z (pre-release) — <summary>" --notes-file <notes>`
   with the assets `defgenx.VIC20.zip install.sh install.ps1 install.bat`. Notes: one line saying what has
   been tested on hardware, "What's new since <previous release>", and the "Updating" paragraph
   (run the installer, answer **a**).
7. Check that `gh release view vX.Y.Z` lists the four assets.

Releases stay `--prerelease` until the core is confirmed on hardware. Publishing anywhere else, such as
a list of Pocket cores, is not part of this flow; ask first.

Commits use the author email `alexandre@delvecch.io` (set in this clone's git config).
