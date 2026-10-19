// A GE backend that records: it wraps another backend, hands it every call
// unchanged, and writes the calls of some frames, the guest memory they read
// and the image each frame presented to a .gerec file (ge_record_format.hpp),
// for replaying them into any backend outside the game (ge_replay.cpp). It
// registers itself as the Metal backend does; task 095 moved it here from the
// framework's patch 0004-ge-backend-and-shell-seams, since its users are ours.
//
//   <prefix>_GE_BACKEND=record
//   <prefix>_GE_RECORD=<file>          the recording (nothing is recorded without it)
//   <prefix>_GE_RECORD_INNER=<name>    the backend that draws (default vulkan)
//   <prefix>_GE_RECORD_AT=<frame>      the first frame recorded (default 1)
//   <prefix>_GE_RECORD_FRAMES=<n>      how many frames (default 3)
//
// Frames are numbered as the inner backend counts them (frames_presented()
// once the frame has been shown), which is the number the HLE's
// "[render] frame N (D draws)" capture lines carry. A frame runs from one
// begin_frame() to the next; the image is taken with the inner backend's
// capture_frame() at the begin_frame() after the flip, once the shell has
// shown it. Each recorded frame prints a line of that same form, with the
// inner backend's own counters. The internal scale (the menu's Resolution row)
// is the inner backend's.
#include "ge_record_format.hpp"

#include "gpu/ge_backend.hpp"
#include "gpu/texture_decode.hpp"
#include "profile.hpp"

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <map>
#include <set>
#include <utility>

namespace pure::gerec {
namespace {

std::uint64_t env_number(const char *name, std::uint64_t fallback) {
    const char *text = portablekit::env(name);
    if (text == nullptr || *text == '\0') return fallback;
    return std::strtoull(text, nullptr, 10);
}

// FNV-1a over 8-byte words: whether a range changed since it was last written.
std::uint64_t content_hash(const std::uint8_t *data, std::size_t size) {
    std::uint64_t hash = 0xCBF29CE484222325ull;
    std::size_t at = 0u;
    for (; at + 8u <= size; at += 8u) {
        std::uint64_t word{};
        std::memcpy(&word, data + at, sizeof word);
        hash = (hash ^ word) * 0x100000001B3ull;
    }
    for (; at < size; ++at) hash = (hash ^ data[at]) * 0x100000001B3ull;
    return hash ^ size;
}

std::uint32_t target_bytes_per_pixel(std::uint32_t format) { return format == 3u ? 4u : 2u; }

// The bytes a recording keeps of a texture from its address: rows of the
// buffer width (or of the width, when that is wider), or the blocks of a DXT
// texture, across the same width. At least what the framework's
// texture_bytes() says decoding reads.
std::size_t recorded_texture_bytes(const TextureState &texture) {
    const std::uint32_t width = texture.width;
    const std::uint32_t height = texture.height;
    const std::uint32_t across = texture.buffer_width != 0u ? std::max(texture.buffer_width, width) : width;
    switch (texture.format) {
    case TextureFormat::Rgba5650:
    case TextureFormat::Rgba5551:
    case TextureFormat::Rgba4444:
    case TextureFormat::Clut16: return static_cast<std::size_t>(across) * 2u * height;
    case TextureFormat::Rgba8888:
    case TextureFormat::Clut32: return static_cast<std::size_t>(across) * 4u * height;
    case TextureFormat::Clut4: return static_cast<std::size_t>(across) / 2u * height;
    case TextureFormat::Clut8: return static_cast<std::size_t>(across) * height;
    case TextureFormat::Dxt1: return static_cast<std::size_t>((across + 3u) / 4u) * ((height + 3u) / 4u) * 8u;
    case TextureFormat::Dxt3:
    case TextureFormat::Dxt5: return static_cast<std::size_t>((across + 3u) / 4u) * ((height + 3u) / 4u) * 16u;
    }
    return 0u;
}

class RecordBackend final : public GeBackend {
public:
    RecordBackend(std::unique_ptr<GeBackend> inner, std::string inner_name)
        : inner_(std::move(inner)), inner_name_(std::move(inner_name)) {}
    ~RecordBackend() override { shutdown(); }

    bool needs_window() const noexcept override { return inner_->needs_window(); }

    bool initialize(const BackendConfig &config, std::string &error) override {
        if (!inner_->initialize(config, error)) return false;
        initialized_ = true;
        const char *path = portablekit::env("GE_RECORD");
        at_ = std::max<std::uint64_t>(env_number("GE_RECORD_AT", 1u), 1u);
        frames_wanted_ = std::max<std::uint64_t>(env_number("GE_RECORD_FRAMES", 3u), 1u);
        if (path == nullptr || *path == '\0') {
            std::cout << "[gerec] " << portablekit::env_name("GE_RECORD") << " names no file: " << inner_name_
                      << " draws, nothing is recorded\n";
            phase_ = Phase::Done;
            return true;
        }
        path_ = path;
        std::cout << "[gerec] recording frames " << at_ << "-" << (at_ + frames_wanted_ - 1u) << " drawn by "
                  << inner_name_ << " to " << path_ << "\n";
        return true;
    }

    void shutdown() override {
        if (!initialized_) return;
        initialized_ = false;
        if (phase_ == Phase::Recording) {
            std::cout << "[gerec] the run ended while recording\n";
            finish();
        }
        inner_->shutdown();
    }

    void begin_frame() override {
        boundary();
        inner_->begin_frame();
    }

    void begin_display_list() override {
        record(Kind::DisplayList, {});
        inner_->begin_display_list();
    }

    bool gpu_decode() const override { return inner_->gpu_decode(); }
    bool check_gpu_decode() const override { return inner_->check_gpu_decode(); }

    void submit(const DrawCall &call, const GuestMemory &memory) override {
        if (phase_ == Phase::Recording) {
            note_vram(memory);
            if (call.texture.enabled) {
                record_memory(memory, call.texture.address, recorded_texture_bytes(call.texture));
                // The mip levels after the first, when the minification filter
                // samples them (bit 2): each from its own address, at its own
                // size and row length, with level 0's format.
                if ((call.texture.min_filter & 4u) != 0u) {
                    const std::uint32_t levels = std::min<std::uint32_t>(call.texture.level_count, 8u);
                    for (std::uint32_t n = 1u; n < levels; ++n) {
                        const TextureLevel &level = call.texture.levels[n - 1u];
                        TextureState texels = call.texture;
                        texels.address = level.address;
                        texels.buffer_width = level.buffer_width;
                        texels.width = level.width;
                        texels.height = level.height;
                        record_memory(memory, level.address, recorded_texture_bytes(texels));
                    }
                }
                if (indexed(call.texture.format))
                    record_memory(memory, call.texture.clut_address, 512u * (call.texture.clut_format == 3u ? 4u : 2u));
            }
            record_target_words(memory, call.target);
            Writer writer;
            writer.put(call);
            record(Kind::Draw, writer.bytes);
            ++frame_draws_;
        }
        inner_->submit(call, memory);
    }

    void block_transfer(const BlockTransfer &transfer, GuestMemory &memory) override {
        if (phase_ == Phase::Recording) {
            note_vram(memory);
            Writer writer;
            writer.put(transfer);
            record(Kind::Transfer, writer.bytes);
        }
        inner_->block_transfer(transfer, memory);
        // The source rows as the shell's copy will read them, after the read-back.
        if (phase_ == Phase::Recording && transfer.height != 0u && transfer.width != 0u) {
            const std::uint32_t bpp = transfer.bytes_per_pixel;
            const std::uint32_t first =
                transfer.source + (transfer.source_y * transfer.source_stride + transfer.source_x) * bpp;
            const std::size_t span =
                (static_cast<std::size_t>(transfer.height - 1u) * transfer.source_stride + transfer.width) * bpp;
            record_memory(memory, first, span);
        }
    }

    void write_back_frame(GuestMemory &memory) override {
        record(Kind::WriteBackFrame, {});
        inner_->write_back_frame(memory);
    }

    void read_back_framebuffer(std::uint32_t address, GuestMemory &memory) override {
        if (phase_ == Phase::Recording) {
            Writer writer;
            writer.u32(address);
            record(Kind::ReadBack, writer.bytes);
        }
        inner_->read_back_framebuffer(address, memory);
    }

    bool write_back_depth(std::uint32_t color_address, std::uint32_t depth_address, std::uint32_t depth_stride,
                          GuestMemory &memory, const char *why) override {
        const bool wrote = inner_->write_back_depth(color_address, depth_address, depth_stride, memory, why);
        if (phase_ == Phase::Recording) {
            Writer writer;
            writer.u32(color_address), writer.u32(depth_address), writer.u32(depth_stride), writer.flag(wrote);
            writer.string(why != nullptr ? why : "");
            record(Kind::WriteBackDepth, writer.bytes);
        }
        return wrote;
    }

    void upload_frame(std::uint32_t display_address, const std::uint8_t *pixels, std::uint32_t width,
                      std::uint32_t height, std::uint32_t stride) override {
        if (phase_ == Phase::Recording && pixels != nullptr && stride >= width) {
            Writer writer;
            writer.u32(display_address), writer.u32(width), writer.u32(height);
            for (std::uint32_t row = 0; row < height; ++row)
                writer.raw(pixels + static_cast<std::size_t>(row) * stride * 4u, static_cast<std::size_t>(width) * 4u);
            record(Kind::Upload, writer.bytes);
        }
        inner_->upload_frame(display_address, pixels, width, height, stride);
    }

    PresentedImage present_image(std::uint32_t display_address) override {
        const PresentedImage image = inner_->present_image(display_address);
        display_address_ = display_address;
        presented_ = image;
        return image;
    }

    bool capture_frame(const std::string &path) override { return inner_->capture_frame(path); }
    std::uint64_t draws_submitted() const noexcept override { return inner_->draws_submitted(); }
    std::uint64_t frames_presented() const noexcept override { return inner_->frames_presented(); }
    bool supports_internal_scale() const noexcept override { return inner_->supports_internal_scale(); }
    void set_internal_scale(std::uint32_t setting) override { inner_->set_internal_scale(setting); }
    std::array<std::uint32_t, 2> target_size() const noexcept override { return inner_->target_size(); }

private:
    enum class Phase : std::uint8_t { Waiting, Recording, Done };

    // Between two frames: the one just shown ends the recording's frame, and
    // the next one may be the first to record.
    void boundary() {
        const std::uint64_t shown = inner_->frames_presented();
        if (phase_ == Phase::Recording && shown > frame_number_) {
            frame_end(shown);
            if (shown + 1u >= at_ + frames_wanted_) finish();
        }
        if (phase_ == Phase::Waiting && shown + 1u >= at_) start(shown);
    }

    void start(std::uint64_t shown) {
        file_.open(path_, std::ios::binary | std::ios::trunc);
        if (!file_) {
            std::cerr << "[gerec] cannot write " << path_ << "; nothing is recorded\n";
            phase_ = Phase::Done;
            return;
        }
        file_.write(gerec::kMagic, sizeof gerec::kMagic);
        const std::uint32_t version = gerec::kVersion;
        file_.write(reinterpret_cast<const char *>(&version), sizeof version);
        phase_ = Phase::Recording;
        frame_number_ = shown;
        records_ = 0u;
        frames_recorded_ = 0u;
        recorded_.clear();
        vram_written_ = false;
        Writer writer;
        writer.u32(static_cast<std::uint32_t>(shown + 1u));
        writer.u32(static_cast<std::uint32_t>(frames_wanted_));
        writer.string(inner_name_);
        writer.string(portablekit::game().env_prefix);
        writer.u64(inner_->frames_presented());
        writer.u64(inner_->draws_submitted());
        record(Kind::Begin, writer.bytes);
        begin_recorded_frame();
        std::cout << "[gerec] recording from frame " << (shown + 1u) << "\n";
    }

    void begin_recorded_frame() {
        frame_draws_ = 0u;
        frame_records_ = 0u;
        targets_seen_.clear();
    }

    void frame_end(std::uint64_t shown) {
        // The image the shell showed, as the inner backend captures it.
        std::vector<std::uint8_t> image;
        const std::string capture = path_ + ".capture.bmp";
        if (inner_->capture_frame(capture)) {
            std::ifstream in(capture, std::ios::binary);
            image.assign(std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>());
        }
        std::error_code ignored;
        std::filesystem::remove(capture, ignored);
        const std::uint32_t frame_records = frame_records_;
        Writer writer;
        writer.u32(static_cast<std::uint32_t>(shown));
        writer.u32(display_address_);
        writer.u64(inner_->frames_presented());
        writer.u64(inner_->draws_submitted());
        writer.u32(frame_draws_);
        writer.u32(frame_records);
        writer.u8(static_cast<std::uint8_t>(presented_.api));
        writer.u32(presented_.width);
        writer.u32(presented_.height);
        writer.u32(static_cast<std::uint32_t>(image.size()));
        writer.raw(image.data(), image.size());
        record(Kind::FrameEnd, writer.bytes);
        std::cout << "[render] frame " << inner_->frames_presented() << " (" << inner_->draws_submitted()
                  << " draws) recorded: " << frame_draws_ << " draws, " << frame_records << " records, image "
                  << (image.empty() ? std::string("missing") : std::to_string(image.size()) + " bytes") << "\n";
        ++frames_recorded_;
        frame_number_ = shown;
        begin_recorded_frame();
    }

    void finish() {
        Writer writer;
        writer.u32(frames_recorded_);
        writer.u64(records_);
        record(Kind::End, writer.bytes);
        file_.close();
        phase_ = Phase::Done;
        std::cout << "[gerec] saved " << frames_recorded_ << " frames, " << records_ << " records to " << path_;
        if (missed_ranges_ != 0u)
            std::cout << " (" << missed_ranges_ << " inputs not in one run of guest memory were left out)";
        std::cout << "\n" << std::flush;
    }

    void record(Kind kind, const std::vector<std::uint8_t> &payload) {
        if (phase_ != Phase::Recording) return;
        const std::uint8_t tag = static_cast<std::uint8_t>(kind);
        const auto size = static_cast<std::uint32_t>(payload.size());
        file_.write(reinterpret_cast<const char *>(&tag), 1);
        file_.write(reinterpret_cast<const char *>(&size), sizeof size);
        if (size != 0u) file_.write(reinterpret_cast<const char *>(payload.data()), size);
        ++records_;
        ++frame_records_;
    }

    // Guest memory a call is about to read, unless the recording already holds
    // these bytes for this range.
    void record_memory(const GuestMemory &memory, std::uint32_t address, std::size_t size) {
        if (size == 0u) return;
        const std::uint8_t *bytes = memory.raw_pointer(address, size);
        if (bytes == nullptr) {
            ++missed_ranges_;
            return;
        }
        const std::uint64_t hash = content_hash(bytes, size);
        const auto key = std::make_pair(GuestMemory::canonical(address), static_cast<std::uint32_t>(size));
        const auto found = recorded_.find(key);
        if (found != recorded_.end() && found->second == hash) return;
        recorded_[key] = hash;
        Writer writer;
        writer.u32(address);
        writer.u32(static_cast<std::uint32_t>(size));
        writer.raw(bytes, size);
        record(Kind::Memory, writer.bytes);
    }

    // The whole of VRAM, once, at the first call of the recording that reads memory.
    void note_vram(const GuestMemory &memory) {
        if (vram_written_) return;
        vram_written_ = true;
        record_memory(memory, GuestMemory::kVramPhysicalBase, GuestMemory::kVramSize);
    }

    // At a target's first draw in a frame: the guest words a backend compares
    // when the target is later sampled as a texture.
    void record_target_words(const GuestMemory &memory, const RenderTarget &target) {
        if (!targets_seen_.insert(target.color_address).second) return;
        const std::uint32_t bytes = target.color_stride * kScreenHeight * target_bytes_per_pixel(target.color_format);
        if (!memory.contains(target.color_address, bytes)) return;
        constexpr std::uint32_t kStep = 256u;
        Writer writer;
        writer.u32(target.color_address);
        writer.u32(kStep);
        const std::uint32_t count = (bytes - 4u) / kStep + 1u;
        writer.u32(count);
        for (std::uint32_t i = 0; i < count; ++i) writer.u32(memory.load32(target.color_address + i * kStep));
        record(Kind::Words, writer.bytes);
    }

    std::unique_ptr<GeBackend> inner_;
    std::string inner_name_;
    bool initialized_{};
    std::string path_;
    std::uint64_t at_{1u};
    std::uint64_t frames_wanted_{3u};
    Phase phase_{Phase::Waiting};
    std::ofstream file_;
    // frames_presented() of the inner backend at the start of the frame being recorded.
    std::uint64_t frame_number_{};
    std::uint32_t frames_recorded_{};
    std::uint64_t records_{};
    std::uint32_t frame_records_{};
    std::uint32_t frame_draws_{};
    std::uint32_t display_address_{};
    PresentedImage presented_{};
    bool vram_written_{};
    std::uint64_t missed_ranges_{};
    std::map<std::pair<std::uint32_t, std::uint32_t>, std::uint64_t> recorded_;
    std::set<std::uint32_t> targets_seen_;
};

std::unique_ptr<GeBackend> make_record_backend() {
    const char *named = portablekit::env("GE_RECORD_INNER");
    std::string inner_name = named != nullptr && *named != '\0' ? named : "vulkan";
    if (inner_name == "record") {
        std::cerr << "[gerec] the record backend cannot record itself; recording vulkan\n";
        inner_name = "vulkan";
    }
    std::unique_ptr<GeBackend> inner = make_backend(inner_name);
    if (!inner) {
        std::cerr << "[gerec] " << portablekit::env_name("GE_RECORD_INNER") << "=" << inner_name
                  << ": there is no such backend\n";
        return nullptr;
    }
    return std::unique_ptr<GeBackend>(new RecordBackend(std::move(inner), inner_name));
}

const BackendRegistration registration("record", "records another backend's calls to a .gerec file",
                                       make_record_backend);

} // namespace
} // namespace pure::gerec
