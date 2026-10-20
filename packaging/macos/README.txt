Wipeout Pure for macOS (Apple Silicon)
======================================

This is pure-recomp: the PSP game Wipeout Pure (2005), its code recompiled
ahead of time into a native program for Apple Silicon Macs, drawn with
Metal. It is not an emulator. The program is a translation of the game's
executable code into native code; it holds none of the game's data: no
graphics, no music, no tracks, no keys. You play it from your own disc image.

Needs: a Mac with Apple Silicon (M1 or newer), macOS @MINIMUM_SYSTEM_VERSION@ or newer, and a
disc image (.iso) dumped from your own copy of Wipeout Pure, US Greatest Hits
edition (UCUS-98612, version 2.00). The setup refuses other releases and
regions.


Install
-------

Drag "Wipeout Pure" into Applications (or any folder). This build is signed
ad hoc and not notarized by Apple, so the first time you open it macOS says
it cannot verify the developer and offers only Done or Move to Trash. Choose
Done, then open System Settings > Privacy & Security, scroll down to the
message about Wipeout Pure and click "Open Anyway". Or, from Terminal:

    xattr -dr com.apple.quarantine "/Applications/Wipeout Pure.app"


First start: setup
------------------

The first start shows the setup screens. Choose your disc image; the setup
checks that it is the right disc and edition, then asks whether to copy it
into the app's data folder (about 250 MB, and the image can then be moved or
deleted) or to use it where it is. It prepares the game's executable from
the image, and the game starts. Later starts go straight to the game. To set
up again (another image, or a moved one), start it from Terminal with
--install:

    "/Applications/Wipeout Pure.app/Contents/MacOS/Wipeout Pure" --install
    "/Applications/Wipeout Pure.app/Contents/MacOS/Wipeout Pure" --install /path/to/image.iso [--in-place]

The first opens the setup screens; the second sets up from that image
without them (copying it, or using it where it is with --in-place) and exits.


Where things live
-----------------

Everything the app writes is in one folder:

    ~/Library/Application Support/pure-recomp/PureNative/

    EBOOT.ELF      the executable prepared from your disc image
    disc.iso       the copy of your disc image (absent if you use it in place)
    settings.ini   the setup's choice and every setting of the Esc menu
    ms0/           the memory stick: your saves are in ms0/PSP/SAVEDATA/

Back up ms0/ to keep your saves. Deleting the app and that folder removes
everything.


Controls
--------

A gamepad works as a PSP pad (positional: Cross is the bottom button on a
PlayStation pad, A on an Xbox pad; the left stick steers). The keyboard:

    Wipeout Pure                PSP button    Key
    --------------------------  ------------  ------------------------------
    Steer                       stick         A and D (W and S: up, down)
    Accelerate; confirm         Cross         Space
    Airbrake left               L             Q
    Airbrake right              R             Left Shift
    Use pickup                  Square        E
    Absorb pickup               Circle        F, or the right mouse button
    Reverse camera; back        Triangle      the left mouse button
    PRESS START; skip a movie   Start         Enter or Tab
    Menu cursor                 D-pad         the arrow keys
    The app's menu              -             Esc (L3+R3 on a gamepad)

The mouse buttons count while the window holds the pointer; Esc frees it.
Every key can be rebound in the Esc menu (Controls), and there is a classic
keyboard-only layout at the end of that tab.


Licence
-------

pure-recomp is free software under the GNU General Public License, version 2
or later. Its source code is at https://github.com/erreib/pure-recomp, at
the tag of this version (0.1.0 is v0.1.0; Finder's Get Info shows the
version), or for a build between releases at the commit named after the
version number. It is built on PortableKit (MIT) and ships SDL3, FFmpeg
(LGPL, dynamically linked), the Vulkan loader, MoltenVK, Dear ImGui and
Zstandard's decoder under their own licences:
Wipeout Pure.app/Contents/Resources/licenses/. Wipeout
Pure is a trademark of its owners, who have nothing to do with this program.
