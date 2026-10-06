// PURE_AUDIO_WAV=<file> (task 013): a WAV capture of what the game hands to sceAudio, for tools/wavstats.py.
//
// The profile wraps the bound sceAudio output calls (sceAudioOutputPannedBlocking, sceAudioOutputBlocking,
// sceAudioOutputPanned) and appends each buffer, converted to stereo 16-bit 44.1 kHz with the call's volumes applied
// the way the framework's sink applies them (min(volume, 0x8000), sample * gain >> 15), to <file>.ch<N>.wav for the
// channel and to the mixed <file> (the channels summed and clipped). The framework keeps each channel's format and
// sample count to itself, so the capture follows sceAudioChReserve, sceAudioSetChannelDataLen and
// sceAudioChangeChannelConfig as well: format bit 0x10 is mono (one sample per frame), and the frame count of an
// output call is the channel's current data length.
//
// Placement: every file is on the kernel's virtual clock, sample 0 at time 0. A buffer starts where the channel's
// previous one ended, or at the call's virtual time when the game submitted late (or the channel was idle), the way
// hle_media.cpp queues it; the gap is written as zeros. On time, consecutive buffers of a channel are contiguous, so
// within a channel this is call order. Every output lands at or after the current virtual time, so the mix is final
// up to it and written out as the clock passes. Silence the framework drops from the device while a load runs fast is
// kept here: the capture is what the game submitted, not what the device played.
//
// A gap of under two seconds on a channel that was playing is an underrun: it is logged as it happens
// (`[pure] audio capture: channel N underrun of F frames (M ms) at t=US`) and counted in the line printed at exit.
//
// The WAV headers are rewritten after every write and the files flushed, so a run the runner kills after its frame
// exit still leaves readable files.
#include "hle/hle_common.hpp"
#include "kernel/kernel.hpp"
#include "profile.hpp"

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdio>
#include <deque>
#include <iostream>
#include <mutex>
#include <string>
#include <vector>

namespace portablekit {
namespace {

constexpr std::uint64_t kRate = 44'100u;
constexpr std::size_t kChannelCount = 8u;   // sceAudio's channels, as hle_media.cpp has them
constexpr std::uint64_t kUnderrunFrames = 2u * kRate;

constexpr std::uint32_t kNidChReserve = 0x5EC81C55u;
constexpr std::uint32_t kNidSetChannelDataLen = 0xCB2E439Eu;
constexpr std::uint32_t kNidChangeChannelConfig = 0x95FD0C2Du;
constexpr std::uint32_t kNidOutputPannedBlocking = 0x13F592BCu;
constexpr std::uint32_t kNidOutputBlocking = 0x136CAF51u;
constexpr std::uint32_t kNidOutputPanned = 0xE2D56B2Du;

void put_le32(std::uint8_t *p, std::uint32_t v) {
    for (int i = 0; i < 4; ++i) p[i] = static_cast<std::uint8_t>(v >> (8 * i));
}

// A 44.1 kHz stereo 16-bit WAV that grows; the RIFF and data sizes are patched after each write.
class WavFile {
public:
    bool open(const std::string &path) {
        file_ = std::fopen(path.c_str(), "wb");
        if (file_ == nullptr) return false;
        std::uint8_t header[44] = {'R', 'I', 'F', 'F', 0, 0, 0, 0, 'W', 'A', 'V', 'E', 'f', 'm', 't', ' ',
                                   16, 0, 0, 0, 1, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                                   4, 0, 16, 0, 'd', 'a', 't', 'a', 0, 0, 0, 0};
        put_le32(header + 24, static_cast<std::uint32_t>(kRate));
        put_le32(header + 28, static_cast<std::uint32_t>(kRate * 4u));
        put_le32(header + 4, 36u);
        std::fwrite(header, 1, sizeof header, file_);
        std::fflush(file_);
        return true;
    }
    [[nodiscard]] bool is_open() const { return file_ != nullptr; }
    [[nodiscard]] std::uint64_t frames() const { return frames_; }
    void write(const std::int16_t *stereo, std::size_t count) {
        if (file_ == nullptr || count == 0u) return;
        std::fwrite(stereo, 4, count, file_);   // the host is little-endian, as the format is
        frames_ += count;
    }
    void write_zeros(std::uint64_t count) {
        static const std::array<std::int16_t, 2u * 4096u> zeros{};
        while (count > 0u) {
            const std::size_t n = static_cast<std::size_t>(std::min<std::uint64_t>(count, 4096u));
            write(zeros.data(), n);
            count -= n;
        }
    }
    void sync() {
        if (file_ == nullptr) return;
        const std::uint64_t bytes = std::min<std::uint64_t>(frames_ * 4u, 0xFFFFFFFFull - 36u);
        std::uint8_t size[4];
        put_le32(size, static_cast<std::uint32_t>(bytes + 36u));
        std::fseek(file_, 4, SEEK_SET);
        std::fwrite(size, 1, 4, file_);
        put_le32(size, static_cast<std::uint32_t>(bytes));
        std::fseek(file_, 40, SEEK_SET);
        std::fwrite(size, 1, 4, file_);
        std::fseek(file_, 0, SEEK_END);
        std::fflush(file_);
    }
    void close() {
        if (file_ == nullptr) return;
        sync();
        std::fclose(file_);
        file_ = nullptr;
    }

private:
    std::FILE *file_{};
    std::uint64_t frames_{};
};

struct Channel {
    std::uint32_t samples{};
    std::uint32_t format{};
    std::uint64_t end{};   // the frame after the channel's last one, on the virtual clock
    std::uint64_t underruns{};
    std::uint64_t underrun_frames{};
    WavFile wav;
};

class Capture {
public:
    explicit Capture(std::string path) : path_(std::move(path)) {
        if (!mix_.open(path_)) std::cout << "[pure] PURE_AUDIO_WAV: cannot write " << path_ << "\n";
        else std::cout << "[pure] audio capture: mix -> " << path_ << "\n";
    }
    ~Capture() { close(); }

    void reserve(std::uint32_t channel, std::uint32_t samples, std::uint32_t format) {
        std::lock_guard<std::mutex> guard(lock_);
        if (channel >= kChannelCount) return;
        channels_[channel].samples = samples;
        channels_[channel].format = format;
    }
    void set_samples(std::uint32_t channel, std::uint32_t samples) {
        std::lock_guard<std::mutex> guard(lock_);
        if (channel < kChannelCount) channels_[channel].samples = samples;
    }
    void set_format(std::uint32_t channel, std::uint32_t format) {
        std::lock_guard<std::mutex> guard(lock_);
        if (channel < kChannelCount) channels_[channel].format = format;
    }

    // One output call: `buffer` holds the channel's data length in frames, mono or stereo by its format.
    void output(Runtime &rt, std::uint32_t channel, std::uint32_t left, std::uint32_t right, std::uint32_t buffer,
                std::uint64_t now_us) {
        std::lock_guard<std::mutex> guard(lock_);
        if (channel >= kChannelCount || !mix_.is_open()) return;
        Channel &state = channels_[channel];
        const std::uint32_t frames = state.samples;
        if (buffer == 0u || frames == 0u) return;
        const bool mono = (state.format & 0x10u) != 0u;
        const std::size_t words = static_cast<std::size_t>(frames) * (mono ? 1u : 2u);

        if (!state.wav.is_open()) {
            const std::string name = path_ + ".ch" + std::to_string(channel) + ".wav";
            if (!state.wav.open(name)) {
                std::cout << "[pure] PURE_AUDIO_WAV: cannot write " << name << "\n";
                return;
            }
            std::cout << "[pure] audio capture: channel " << channel << " (" << frames << " frames, "
                      << (mono ? "mono" : "stereo") << ") from t=" << now_us << " -> " << name << "\n";
        }

        // Where the buffer plays: after the previous one, or now when it came late. A gap shorter than
        // kUnderrunFrames on a channel that was playing is an underrun (the device would play silence there) and
        // is logged; a longer one is the channel sitting idle.
        const std::uint64_t now = now_us * kRate / 1'000'000u;
        const std::uint64_t start = std::max(state.end, now);
        if (state.end != 0u && start > state.end && start - state.end < kUnderrunFrames) {
            ++state.underruns;
            state.underrun_frames += start - state.end;
            std::cout << "[pure] audio capture: channel " << channel << " underrun of " << (start - state.end)
                      << " frames (" << (start - state.end) * 1000u / kRate << " ms) at t=" << now_us << "\n";
        }
        state.wav.write_zeros(start - state.wav.frames());

        const std::int32_t gains[2] = {static_cast<std::int32_t>(std::min<std::uint32_t>(left, 0x8000u)),
                                       static_cast<std::int32_t>(std::min<std::uint32_t>(right, 0x8000u))};
        staging_.assign(static_cast<std::size_t>(frames) * 2u, 0);
        if (const std::uint8_t *source = rt.memory().raw_pointer(buffer, words * 2u)) {
            for (std::uint32_t frame = 0; frame < frames; ++frame) {
                for (std::uint32_t side = 0; side < 2u; ++side) {
                    const std::size_t index = mono ? frame : frame * 2u + side;
                    const auto sample = static_cast<std::int16_t>(source[index * 2u] | (source[index * 2u + 1u] << 8));
                    staging_[frame * 2u + side] = static_cast<std::int16_t>((sample * gains[side]) >> 15);
                }
            }
        }
        state.wav.write(staging_.data(), frames);
        state.wav.sync();
        state.end = start + frames;

        // Into the mix at the same place, then out with everything before now: nothing can land there any more.
        const std::uint64_t needed = (start + frames - mix_from_) * 2u;
        if (pending_.size() < needed) pending_.resize(needed, 0);
        const std::size_t offset = static_cast<std::size_t>(start - mix_from_) * 2u;
        for (std::size_t i = 0; i < staging_.size(); ++i) pending_[offset + i] += staging_[i];
        flush_mix(now);
    }

    void close() {
        std::lock_guard<std::mutex> guard(lock_);
        if (!mix_.is_open()) return;
        flush_mix(mix_from_ + pending_.size() / 2u);
        std::cout << "[pure] audio capture: mix " << mix_.frames() * 1000u / kRate << " ms";
        for (std::size_t n = 0; n < kChannelCount; ++n) {
            const Channel &c = channels_[n];
            if (c.wav.is_open())
                std::cout << "; channel " << n << " " << c.underruns << " underrun(s), " << c.underrun_frames << " frames";
        }
        std::cout << "\n";
        mix_.close();
        for (Channel &c : channels_) c.wav.close();
    }

private:
    void flush_mix(std::uint64_t until) {
        if (until <= mix_from_) return;
        std::uint64_t count = until - mix_from_;
        const std::size_t have = std::min<std::size_t>(static_cast<std::size_t>(count), pending_.size() / 2u);
        out_.resize(have * 2u);
        for (std::size_t i = 0; i < have * 2u; ++i) out_[i] = static_cast<std::int16_t>(std::clamp(pending_[i], -32768, 32767));
        mix_.write(out_.data(), have);
        pending_.erase(pending_.begin(), pending_.begin() + static_cast<std::ptrdiff_t>(have * 2u));
        mix_.write_zeros(count - have);   // nobody wrote there: silence
        mix_from_ = until;
        mix_.sync();
    }

    std::mutex lock_;
    std::string path_;
    WavFile mix_;
    std::array<Channel, kChannelCount> channels_{};
    std::deque<std::int32_t> pending_;   // the mix from mix_from_ on, stereo, not yet final
    std::uint64_t mix_from_{};
    std::vector<std::int16_t> staging_;
    std::vector<std::int16_t> out_;
};

Capture *capture() {
    static Capture *instance = [] () -> Capture * {
        const char *path = env("AUDIO_WAV");
        if (path == nullptr || *path == '\0') return nullptr;
        static Capture c{path};
        std::atexit([] { c.close(); });
        return &c;
    }();
    return instance;
}

} // namespace

// Called from register_pure_hle, after the framework bound its sceAudio handlers.
void register_audio_capture(HleRegistrar &hle) {
    if (capture() == nullptr) return;
    const std::string lib = "sceAudio";
    const auto wrap = [&hle, &lib](std::uint32_t nid, auto &&around) {
        HleFunction original = hle.bound_function(lib, nid);
        if (!original) {
            std::cout << "[pure] PURE_AUDIO_WAV: nothing bound for sceAudio:0x" << std::hex << nid << std::dec << "\n";
            return;
        }
        hle.bind(lib, nid, [original, around](Runtime &rt, AllegrexContext &ctx) { around(original, rt, ctx); });
    };

    // sceAudioChReserve(channel or -1, samples, format) -> the channel.
    wrap(kNidChReserve, [](const HleFunction &original, Runtime &rt, AllegrexContext &ctx) {
        const std::uint32_t samples = arg(ctx, 1), format = arg(ctx, 2);
        original(rt, ctx);
        const std::uint32_t channel = ctx.gpr[2];
        if (channel < kChannelCount) capture()->reserve(channel, samples, format);
    });
    // sceAudioSetChannelDataLen(channel, samples), sceAudioChangeChannelConfig(channel, format).
    wrap(kNidSetChannelDataLen, [](const HleFunction &original, Runtime &rt, AllegrexContext &ctx) {
        const std::uint32_t channel = arg(ctx, 0), samples = arg(ctx, 1);
        original(rt, ctx);
        if (ctx.gpr[2] == 0u) capture()->set_samples(channel, samples);
    });
    wrap(kNidChangeChannelConfig, [](const HleFunction &original, Runtime &rt, AllegrexContext &ctx) {
        const std::uint32_t channel = arg(ctx, 0), format = arg(ctx, 1);
        original(rt, ctx);
        if (ctx.gpr[2] == 0u) capture()->set_format(channel, format);
    });
    // The outputs: (channel, left, right, buffer) panned, (channel, volume, buffer) otherwise. The buffer is read
    // before the original runs; a blocking call may switch threads.
    const auto panned = [](const HleFunction &original, Runtime &rt, AllegrexContext &ctx) {
        capture()->output(rt, arg(ctx, 0), arg(ctx, 1), arg(ctx, 2), arg(ctx, 3), kernel().now_us());
        original(rt, ctx);
    };
    wrap(kNidOutputPannedBlocking, panned);
    wrap(kNidOutputPanned, panned);
    wrap(kNidOutputBlocking, [](const HleFunction &original, Runtime &rt, AllegrexContext &ctx) {
        capture()->output(rt, arg(ctx, 0), arg(ctx, 1), arg(ctx, 1), arg(ctx, 2), kernel().now_us());
        original(rt, ctx);
    });
}

} // namespace portablekit
