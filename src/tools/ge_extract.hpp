#pragma once

// ge_replay's --extract mode (task 101): one recorded frame's draws written out as a scene, for the substitution
// work (3D crowds, skies) to start from the game's own geometry and textures. ge_replay.cpp replays the recording
// into a null lane up to the frame and hands this every Draw of it, in order, with the lane's guest memory as the
// draw saw it (the Memory records before the draw applied); finish() then writes
//
//   DIR/frame.obj, DIR/frame.mtl   one `o draw_NNNN_<key>` per transformed draw (NNNN its number in the frame, from
//                                  1 as --cut counts), vertices in world space (the world matrix applied, the view
//                                  left out), `usemtl <key>`, the MTL mapping each key to textures/<key>.png
//   DIR/textures/<key>.png         every texture the frame binds, through the framework's TextureDumper keyed as the
//                                  HD pack keys (xxh64, ignoreAddress, ignoreMipmap)
//   DIR/frame.json                 the frame, its view and projection, the distinct view matrices, and per draw its
//                                  key, primitive, counts, texture, world-space bounds, blend, tests and a billboard
//                                  guess
//
// With `keys` only the draws whose key is listed go into frame.obj; the JSON and the textures stay the whole frame's.
#include "gpu/ge_state.hpp"

#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <memory>
#include <string>
#include <vector>

namespace pure::extract {

class FrameExtract {
public:
    FrameExtract(std::filesystem::path out, std::uint32_t frame, std::vector<std::string> keys);
    ~FrameExtract();
    FrameExtract(const FrameExtract &) = delete;
    FrameExtract &operator=(const FrameExtract &) = delete;

    // Makes DIR and DIR/textures; false with `error` set when it cannot.
    bool open(std::string &error);
    // The frame's next Draw: `record` is its record number (gerec_dump.py's listing).
    void draw(std::size_t record, const portablekit::gpu::DrawCall &call, const psprecomp::GuestMemory &memory);
    // Writes the OBJ, MTL and JSON once every texture is written; false with `error` set when a file cannot be.
    // `summary` gets one line for the log.
    bool finish(std::string &summary, std::string &error);

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace pure::extract
