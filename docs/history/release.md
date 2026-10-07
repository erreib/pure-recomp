# The macOS app: the record (task 029, 2026-10-06)

What docs/release.md recorded of task 029's first runs, moved here by task 053 (2026-10-07). The app as it is stays in
[docs/release.md](../release.md).

## The setup before 16718e6 (task 029, 2026-10-06)

Fixed the same day by 16718e6 (the profile names the plain `BOOT.BIN`): the setup finishes, and `tools/bundle.sh
--check` runs it. What task 029 found before the fix:

**The setup cannot finish yet (2026-10-06, task 029).** It copies the image, then fails with "The prepared executable
does not match the supported one" and leaves only `disc.iso.part`. The framework's installer prepares the executable
from the profile's `executable_path_on_disc`, `PSP_GAME/SYSDIR/EBOOT.BIN`, which on this disc is encrypted (`~PSP`,
SHA-256 `02287685...`, the profile's `encrypted_executable_sha256`), and decrypts it with the profile's key for tag
0x08000000, which `src/profile/pure_profile.cpp` leaves empty ("not filled in yet"), so the result never matches
`executable_sha256`. The disc also carries the plain executable, `PSP_GAME/SYSDIR/BOOT.BIN` (`\x7FELF`, SHA-256
`9033e4dd...` = `executable_sha256`, what `tools/setup_game.sh` puts in `game/EBOOT.ELF` and the corpus is generated
from). Either change to the profile fixes it: `executable_path_on_disc = "PSP_GAME/SYSDIR/BOOT.BIN"` (the installer
then takes the plain file as it is: `inspect` accepts a plain executable whose SHA-256 the profile knows, and
`prepare_executable` returns a plain ELF unchanged; no key involved), or the tag key in `decryption_key`. Until then
the app shows its setup screen on first start (the picture task 029 captured through `open`), and a data directory
laid out as the installer would leave it plays (below).

## A hand-made installation (task 029, 2026-10-06)

Task 029 checked the rest of the path with such a directory made by hand, as `--install IMAGE --in-place` leaves it
(`out/029/standin/data`: `EBOOT.ELF` a link to `game/EBOOT.ELF`, `settings.ini` with `disc_image=` the image's
path; nothing copied): the bundled executable with only `PURE_DATA_DIR` and the frontend route's variables played it
in the Metal shell and backend to frame 2200 (`Executable: .../out/029/standin/data/EBOOT.ELF`), the title shot
0.000237 from `ref/title.png` (the suite's Metal value is 0.0002); `open "Wipeout Pure.app"` with the same `--env`
did the same (0.000237); and with `PURE_SHELL=vulkan PURE_GE_BACKEND=vulkan` the bundled loader found the bundle's
MoltenVK manifest and MoltenVK 1.4.2 drew the language screen 0.054 from `ref/frontend.png` (the Vulkan value 0.054).
