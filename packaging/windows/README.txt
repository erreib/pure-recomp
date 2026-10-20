Wipeout Pure for Windows (x64)
==============================

This is pure-recomp: the PSP game Wipeout Pure (2005), its code recompiled
ahead of time into a native Windows program, drawn with Vulkan. It is not an
emulator. The program is a translation of the game's executable code into
native code; it holds none of the game's data: no graphics, no music, no
tracks, no keys. You play it from your own disc image.

Needs: 64-bit Windows 10 or 11, a graphics card with a Vulkan driver
(any current NVIDIA, AMD or Intel driver has one), and a disc image (.iso)
dumped from your own copy of Wipeout Pure, US Greatest Hits edition
(UCUS-98612, version 2.00). The setup refuses other releases and regions.


Install
-------

Unpack the zip anywhere (for example into your Documents folder) and keep
the files of the "Wipeout Pure" folder together: the program loads the DLLs
beside it. Nothing is installed into Windows. This build is not signed, so
the first time you start it Windows SmartScreen may say it protected your PC;
choose "More info", then "Run anyway".


First start: setup
------------------

Double-click "Wipeout Pure.exe". The first start shows the setup screens.
Choose your disc image; the setup checks that it is the right disc and
edition, then asks whether to copy it into the program's data folder (about
250 MB, and the image can then be moved or deleted) or to use it where it
is. It prepares the game's executable from the image, and the game starts.
Later starts go straight to the game. To set up again (another image, or a
moved one), start it from a command prompt with --install:

    "Wipeout Pure.exe" --install
    "Wipeout Pure.exe" --install C:\path\to\image.iso [--in-place]

The first opens the setup screens; the second sets up from that image
without them (copying it, or using it where it is with --in-place) and exits.
The program opens no console window of its own, so a command prompt shows
none of its messages; its exit code says whether the setup worked.


Where things live
-----------------

Everything the program writes is in one folder:

    %APPDATA%\pure-recomp\PureNative\
    (C:\Users\<you>\AppData\Roaming\pure-recomp\PureNative\)

    EBOOT.ELF            the executable prepared from your disc image
    disc.iso             the copy of your disc image (absent if you use it
                         in place)
    settings.ini         the setup's choice and every setting of the Esc menu
    ms0\                 the memory stick: your saves are in ms0\PSP\SAVEDATA\
    pipeline_cache.bin   Vulkan's shader cache, so later starts are smoother

Back up ms0\ to keep your saves. Deleting the program's folder and that one
removes everything.


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
    The program's menu          -             Esc (L3+R3 on a gamepad)

The mouse buttons count while the window holds the pointer; Esc frees it.
Every key can be rebound in the Esc menu (Controls), and there is a classic
keyboard-only layout at the end of that tab.


Licence
-------

pure-recomp is free software under the GNU General Public License, version 2
or later: LICENSE.txt. It is built on PortableKit (MIT) and ships SDL3 and
FFmpeg (LGPL, dynamically linked: the DLLs beside the program, which you may
replace) and contains Dear ImGui and Zstandard's decoder, each under its own
licence: licenses\, with
THIRD_PARTY_NOTICES.md. Its source code is at
https://github.com/erreib/pure-recomp, at the commit BUILDINFO.txt names
(a release's tag, v0.1.0 for 0.1.0, is on that commit). Wipeout Pure is a
trademark of its owners, who have nothing to do with this program.
