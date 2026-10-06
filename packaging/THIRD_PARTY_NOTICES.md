# Third-party notices

Wipeout Pure.app is pure-recomp, a native macOS build of the PSP game Wipeout Pure made by static recompilation. The
program is a combination of pure-recomp's own code, the PortableKit framework and the third-party software listed
here, each under its own licence. The combination is distributed under the GNU General Public License, version 2 or
later. The licence texts are in the same directory as this file: `Wipeout Pure.app/Contents/Resources/licenses/`.

The app contains no game, no game assets and no keys. You provide the disc image of the game you own; what the
first-run setup makes from it (the prepared executable, and the copy of the image unless you chose to use it where it
is) stays in the app's data directory on your computer and is for your own use only. Wipeout Pure is a trademark of
its owners; pure-recomp is not affiliated with them.

## pure-recomp

The game profile, the Metal graphics backend and window, the tools around them, and the changes to PortableKit kept
as a numbered patch series. GNU General Public License, version 2 or later: `Wipeout Pure-LICENSE.txt`. The source is
the pure-recomp repository at the commit in the app's version (Finder's Get Info, or `CFBundleGetInfoString` in
`Contents/Info.plist`).

## Compiled into the program

### PortableKit

The PSP recompilation framework and its host layer (the PSP operating system, graphics, audio, input, the installer
and the in-game menu). Commit `8b0c3fedd1d908dc2d171f8257c5c3d9af8886aa` of <https://github.com/TeamGDB/PortableKit>,
with pure-recomp's patch series applied. MIT License: `PortableKit-LICENSE.txt`.

### Dear ImGui 1.92.9b

The in-game menu and the setup screens, including the Metal renderer backend (`imgui_impl_metal.mm` and
`imgui_impl_metal.h` of the 1.92.9b release, unmodified, in pure-recomp's `third_party/imgui_metal/`) that the Metal
window draws the menu with. Copyright (c) 2014-2026 Omar Cornut. MIT License: `DearImGui-LICENSE.txt`.
<https://github.com/ocornut/imgui>

### tiny-AES-c

AES for the first-run setup and for save data. Commit `23856752fbd139da0b8ca6e471a13d5bcc99a08d`, released into the
public domain under the Unlicense: `tiny-AES-c-UNLICENSE.txt`. <https://github.com/kokke/tiny-AES-c>

### stb_truetype 1.26

Draws the menu's text. Copyright (c) 2017 Sean Barrett. Used under the public-domain dedication it offers as an
alternative to the MIT License:

> This is free and unencumbered software released into the public domain. Anyone is free to copy, modify, publish,
> use, compile, sell, or distribute this software, either in source code form or as a compiled binary, for any
> purpose, commercial or non-commercial, and by any means.

<https://github.com/nothings/stb>

### stb_image 2.30 and stb_image_write 1.16

Read and write PNG images (texture packs). Copyright (c) 2017 Sean Barrett. Used under the same public-domain
dedication as stb_truetype above. <https://github.com/nothings/stb>

### xxHash 0.8.3

Hashes textures for texture packs. Copyright (c) 2012-2021 Yann Collet. BSD 2-Clause License: `xxHash-LICENSE.txt`.
<https://github.com/Cyan4973/xxHash>

## Shipped as separate libraries

These are dynamically linked shared libraries in `Wipeout Pure.app/Contents/Frameworks/`. They are unmodified builds
of the upstream releases below. You may replace them with your own builds of the same or a compatible version; sign
the app again afterwards (`codesign --force --deep --sign - "Wipeout Pure.app"`), since it is signed ad hoc as a
whole.

### SDL3 3.4.16

Window, input and audio output. Copyright (C) 1997-2026 Sam Lantinga. zlib License: `SDL3-LICENSE.txt`. Built for
macOS 13 and Apple Silicon.

- Library: `libSDL3.0.dylib`
- Source: <https://github.com/libsdl-org/SDL/releases/download/release-3.4.16/SDL3-3.4.16.tar.gz> (SHA-256
  `7322236cd12090c3eb40b9728be4d49c76f66ad17d04369584d4ecad5cf77c68`)

### FFmpeg 7.1.5

Decodes the game's ATRAC3 and ATRAC3plus audio and its H.264 movies. FFmpeg is licensed under the GNU Lesser General
Public License, version 2.1 or later: `FFmpeg-COPYING.LGPLv2.1.txt`, with the source and configuration also noted in
`FFmpeg-SOURCE.txt`. It is dynamically linked: the two libraries are separate files in the bundle, which you may
replace as above. This build contains only FFmpeg's LGPL parts and nothing non-free. <https://ffmpeg.org/>

- Libraries: `libavcodec.61.dylib` and `libavutil.59.dylib`
- Source: <https://ffmpeg.org/releases/ffmpeg-7.1.5.tar.xz> (SHA-256
  `de668509caf9e35e3cd162473441fdb29538c6d96ed080292b3cf9e6fc5d558f`), not modified
- Configured with:

  ```text
  ./configure --prefix=<prefix> --enable-shared --disable-static --disable-programs --disable-doc --disable-avdevice --disable-avformat --disable-avfilter --disable-swscale --disable-swresample --disable-network --disable-autodetect --disable-everything --enable-decoder=atrac3,atrac3p,h264 --disable-x86asm --disable-debug
  ```

- Also with `--install-name-dir=@rpath`, which only sets where the libraries expect each other.
- Built by the build itself, `cmake/FFmpeg.cmake` in PortableKit, which pins the version, checksum and configuration
  above.

**Source.** The exact FFmpeg source archive above is published beside every pure-recomp build that contains it (the
packer puts it in the same `dist/` directory as the app's archive). For at least three years after a build is
distributed, that source is also available on request from whoever gave you the build, at no more than the cost of
providing it.

### Vulkan loader 1.4.357

Finds and loads the Vulkan driver, MoltenVK, for the Vulkan path (`PURE_SHELL=vulkan PURE_GE_BACKEND=vulkan`); the
default Metal path loads it but uses no Vulkan driver. Copyright (c) 2015-2026 The Khronos Group Inc., Valve
Corporation and LunarG, Inc. Apache License 2.0: `Vulkan-Loader-LICENSE.txt`. Built for macOS 13 and Apple Silicon,
with its Vulkan-Headers of the same tag.

- Library: `libvulkan.1.dylib`
- Source: <https://github.com/KhronosGroup/Vulkan-Loader/archive/refs/tags/vulkan-sdk-1.4.357.0.tar.gz> (SHA-256
  `54f2537df22313768da0317dda2abdaaab7711b4081c48c869a79db343d0ae70`)

### MoltenVK 1.4.2

Vulkan on Apple's Metal, for the Vulkan path only. Copyright (c) 2015-2026 The Brenwill Workshop Ltd. Apache License
2.0: `MoltenVK-LICENSE.txt`. The Khronos release build; only its Apple Silicon (arm64) part is kept.

- Library: `libMoltenVK.dylib`, with its driver manifest in `Wipeout Pure.app/Contents/Resources/vulkan/icd.d/`
- Release: <https://github.com/KhronosGroup/MoltenVK/releases/download/v1.4.2/MoltenVK-macos.tar> (SHA-256
  `f95765a6229cb7b915990a2890ce12ebe36a730b021545d3d52ae69ce4c4024e`); source:
  <https://github.com/KhronosGroup/MoltenVK/tree/v1.4.2>

## Font

### Noto Sans CJK JP (Noto CJK Sans 2.004)

A fallback for Japanese text in the menu: `Wipeout Pure.app/Contents/Resources/fonts/NotoSansCJKjp-Regular.otf`.
Copyright 2014-2021 Adobe (<http://www.adobe.com/>), with Reserved Font Name 'Source'. SIL Open Font License, version
1.1: `NotoSansCJK-OFL.txt`. <https://github.com/notofonts/noto-cjk>
