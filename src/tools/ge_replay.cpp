// ge_replay (task 022): the other half of the A/B method of docs/ge-backend.md. A .gerec file (the record
// backend, format in src/tools/ge_record_format.hpp) holds the calls the shell made on a GE backend,
// with the guest memory each call read and the image each frame presented. This feeds those calls, in their order, to
// any registered backend outside the game and compares what it presents with the recorded images, or two backends
// with each other, and can bisect a frame to the first draw whose pictures differ.
//
//   PureNative --replay FILE.gerec [--backend NAME] [--out DIR] [--compare] [--tol T] [--max-frac F]
//                                  [--frames A[-B]] [--cut N] [--a NAME --b NAME [--first-diff]] [--quiet]
//
// It lives in the game's executable because the host layer is compiled into it and nowhere else (there is no host
// library to link a tool against). The comparison is tools/imgdiff.py's, so the numbers agree with it.
#include "ge_replay.hpp"

#include "../gpu/ge_names.hpp"
#include "../helpers.hpp"
#include "ge_record_format.hpp"

#include "gpu/ge_backend.hpp"
#include "gpu/ge_state.hpp"
#include "profile.hpp"
#include "settings/settings.hpp"
#if defined(PORTABLEKIT_HAS_RENDERER)
#include "gpu/vulkan_renderer.hpp"
#endif

#if defined(_WIN32)
#include <process.h>        // _getpid; only getpid is used from unistd.h (task 054)
#define getpid _getpid
#else
#include <unistd.h>
#endif

#include <algorithm>
#include <array>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <memory>
#include <optional>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace pure::replay {
namespace {

namespace gpu = portablekit::gpu;
namespace gerec = pure::gerec;
using gerec::Kind;
using psprecomp::GuestMemory;
using Clock = std::chrono::steady_clock;

// The game's memory as the profile declares it (32 MiB of RAM for Wipeout Pure; VRAM is part of every GuestMemory).
std::uint32_t guest_bytes() {
    const std::uint32_t declared = portablekit::game().guest_ram_bytes;
    return declared != 0u ? declared : 32u * 1024u * 1024u;
}

// A file that is not a recording, or one whose records do not parse.
struct BadFile : std::runtime_error {
    using std::runtime_error::runtime_error;
};

double ms_since(Clock::time_point start) {
    return std::chrono::duration<double, std::milli>(Clock::now() - start).count();
}

// ---- Pictures: tools/imgdiff.py's comparison --------------------------------------------------------------------

struct Image {
    std::uint32_t width{};
    std::uint32_t height{};
    std::vector<std::uint8_t> rgb;  // rows top first, R G B
};

// tools/png.py's read_bmp: 24-bit and 32-bit uncompressed, or 32-bit bitfields with byte-aligned masks; alpha dropped.
bool decode_bmp(const std::uint8_t *data, std::size_t size, Image &out, std::string &error) {
    if (size < 54u || data[0] != 'B' || data[1] != 'M') {
        error = "not a BMP file";
        return false;
    }
    const auto u16 = [&](std::size_t at) {
        std::uint16_t value{};
        std::memcpy(&value, data + at, sizeof value);
        return value;
    };
    const auto u32 = [&](std::size_t at) {
        std::uint32_t value{};
        std::memcpy(&value, data + at, sizeof value);
        return value;
    };
    const std::uint32_t offset = u32(10u);
    const std::uint32_t header_size = u32(14u);
    const auto width = static_cast<std::int32_t>(u32(18u));
    const auto signed_height = static_cast<std::int32_t>(u32(22u));
    const std::uint16_t bits = u16(28u);
    const std::uint32_t compression = u32(30u);
    if (header_size < 40u) {
        error = "BMP core header not supported";
        return false;
    }
    std::array<std::uint32_t, 3> order{2u, 1u, 0u};  // stored B, G, R
    if ((bits == 24u || bits == 32u) && compression == 0u) {
    } else if (bits == 32u && (compression == 3u || compression == 6u) && size >= 66u) {
        for (std::uint32_t k = 0; k < 3u; ++k) {
            const std::uint32_t mask = u32(54u + 4u * k);
            bool found = false;
            for (std::uint32_t byte = 0; byte < 4u; ++byte) {
                if (mask == 0xFFu << (8u * byte)) {
                    order[k] = byte;
                    found = true;
                }
            }
            if (!found) {
                error = "BMP channel mask " + hex(mask) + " is not byte-aligned";
                return false;
            }
        }
    } else {
        error = "unsupported BMP (bits " + std::to_string(bits) + ", compression " + std::to_string(compression) + ")";
        return false;
    }
    const bool top_down = signed_height < 0;
    const std::uint32_t height = static_cast<std::uint32_t>(top_down ? -static_cast<std::int64_t>(signed_height)
                                                                     : signed_height);
    if (width <= 0 || height == 0u) {
        error = "BMP without pixels";
        return false;
    }
    const std::size_t step = bits / 8u;
    const std::size_t stride = (static_cast<std::size_t>(width) * bits + 31u) / 32u * 4u;
    const std::size_t row_bytes = static_cast<std::size_t>(width) * step;
    if (offset + stride * (height - 1u) + row_bytes > size) {
        error = "BMP pixel data is truncated";
        return false;
    }
    out.width = static_cast<std::uint32_t>(width);
    out.height = height;
    out.rgb.resize(static_cast<std::size_t>(out.width) * height * 3u);
    for (std::uint32_t y = 0; y < height; ++y) {
        const std::uint8_t *row = data + offset + (top_down ? y : height - 1u - y) * stride;
        std::uint8_t *to = out.rgb.data() + static_cast<std::size_t>(y) * out.width * 3u;
        for (std::uint32_t x = 0; x < out.width; ++x)
            for (std::uint32_t k = 0; k < 3u; ++k) to[x * 3u + k] = row[x * step + order[k]];
    }
    return true;
}

bool read_bmp(const std::string &path, Image &out, std::string &error) {
    std::ifstream in(path, std::ios::binary);
    if (!in) {
        error = "cannot read " + path;
        return false;
    }
    const std::vector<std::uint8_t> bytes((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
    if (!decode_bmp(bytes.data(), bytes.size(), out, error)) {
        error = path + ": " + error;
        return false;
    }
    return true;
}

// imgdiff.py's resize_nn: the source pixel of (x, y) is (floor(x * w / dw), floor(y * h / dh)).
Image resize_nearest(const Image &image, std::uint32_t width, std::uint32_t height) {
    Image out;
    out.width = width;
    out.height = height;
    out.rgb.resize(static_cast<std::size_t>(width) * height * 3u);
    for (std::uint32_t y = 0; y < height; ++y) {
        const std::uint64_t sy = static_cast<std::uint64_t>(y) * image.height / height;
        for (std::uint32_t x = 0; x < width; ++x) {
            const std::uint64_t sx = static_cast<std::uint64_t>(x) * image.width / width;
            std::memcpy(out.rgb.data() + (static_cast<std::size_t>(y) * width + x) * 3u,
                        image.rgb.data() + (sy * image.width + sx) * 3u, 3u);
        }
    }
    return out;
}

struct Diff {
    std::uint32_t width{};
    std::uint32_t height{};
    std::uint64_t differing{};
    std::uint64_t total{};
    double fraction{};
    bool resized{};
};

// Frames of different sizes are both resized to 480x272 (a 960x544 capture against a 480x272 one); frames of the
// same size are compared as they are. A pixel differs when any channel differs by more than `tol`.
Diff compare(const Image &a, const Image &b, int tol) {
    Diff diff;
    diff.resized = a.width != b.width || a.height != b.height;
    Image resized_a, resized_b;
    const Image *left = &a;
    const Image *right = &b;
    if (diff.resized) {
        resized_a = resize_nearest(a, gpu::kScreenWidth, gpu::kScreenHeight);
        resized_b = resize_nearest(b, gpu::kScreenWidth, gpu::kScreenHeight);
        left = &resized_a;
        right = &resized_b;
    }
    diff.width = left->width;
    diff.height = left->height;
    diff.total = static_cast<std::uint64_t>(diff.width) * diff.height;
    for (std::uint64_t i = 0; i < diff.total; ++i) {
        const std::uint8_t *p = left->rgb.data() + i * 3u;
        const std::uint8_t *q = right->rgb.data() + i * 3u;
        if (std::abs(p[0] - q[0]) > tol || std::abs(p[1] - q[1]) > tol || std::abs(p[2] - q[2]) > tol)
            ++diff.differing;
    }
    diff.fraction = diff.total != 0u ? static_cast<double>(diff.differing) / static_cast<double>(diff.total) : 0.0;
    return diff;
}

// ---- The recording -------------------------------------------------------------------------------------------

struct Record {
    Kind kind{};
    const std::uint8_t *payload{};
    std::uint32_t size{};
};

// A frame: the records after the FrameEnd before it (or after Begin) up to its own FrameEnd.
struct Frame {
    std::uint32_t number{};
    std::uint32_t display{};
    std::uint64_t presented{};
    std::uint64_t submitted{};
    std::uint32_t draws_said{};
    std::uint32_t records_said{};
    std::uint8_t api{};
    std::uint32_t width{};
    std::uint32_t height{};
    const std::uint8_t *image{};
    std::uint32_t image_size{};
    std::size_t first{};             // index of its first record
    std::size_t end{};               // index of its FrameEnd
    std::vector<std::size_t> draws;  // indices of its Draw records
};

struct Recording {
    std::vector<std::uint8_t> bytes;
    std::uint32_t version{};
    std::uint32_t first_frame{};
    std::uint32_t frames_asked{};
    std::string inner;
    std::string prefix;
    std::vector<Record> records;  // records[0] is Begin; the numbering is gerec_dump.py's
    std::vector<Frame> frames;
    bool ended{};
};

Recording load(const std::string &path) {
    Recording file;
    {
        std::ifstream in(path, std::ios::binary);
        if (!in) throw BadFile("cannot read " + path);
        file.bytes.assign(std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>());
    }
    const std::vector<std::uint8_t> &bytes = file.bytes;
    if (bytes.size() < 12u || std::memcmp(bytes.data(), gerec::kMagic, sizeof gerec::kMagic) != 0)
        throw BadFile(path + " is not a GE recording (no PKGEREC magic)");
    std::memcpy(&file.version, bytes.data() + 8u, sizeof file.version);
    if (file.version < 1u) throw BadFile(path + ": format version " + std::to_string(file.version));
    std::size_t at = 12u;
    while (at < bytes.size() && !file.ended) {
        if (bytes.size() - at < 5u)
            throw BadFile(path + ": a record header is cut short at byte " + std::to_string(at));
        Record record;
        record.kind = static_cast<Kind>(bytes[at]);
        std::memcpy(&record.size, bytes.data() + at + 1u, sizeof record.size);
        if (bytes.size() - at - 5u < record.size)
            throw BadFile(path + ": record " + std::to_string(file.records.size()) + " (" +
                          gerec::kind_name(record.kind) + ", " + std::to_string(record.size) +
                          " bytes) is cut short at byte " + std::to_string(at));
        record.payload = bytes.data() + at + 5u;
        at += 5u + record.size;
        file.ended = record.kind == Kind::End;
        file.records.push_back(record);
    }
    if (file.records.empty() || file.records.front().kind != Kind::Begin) throw BadFile(path + ": no Begin record");
    {
        gerec::Reader in(file.records.front().payload, file.records.front().size);
        file.first_frame = in.u32();
        file.frames_asked = in.u32();
        file.inner = in.string();
        file.prefix = in.string();
        if (!in.ok()) throw BadFile(path + ": the Begin record does not parse");
    }
    std::size_t first = 1u;
    std::vector<std::size_t> draws;
    for (std::size_t i = 1u; i < file.records.size(); ++i) {
        const Record &record = file.records[i];
        if (record.kind == Kind::Draw) draws.push_back(i);
        if (record.kind != Kind::FrameEnd) continue;
        Frame frame;
        gerec::Reader in(record.payload, record.size);
        frame.number = in.u32();
        frame.display = in.u32();
        frame.presented = in.u64();
        frame.submitted = in.u64();
        frame.draws_said = in.u32();
        frame.records_said = in.u32();
        frame.api = in.u8();
        frame.width = in.u32();
        frame.height = in.u32();
        frame.image_size = in.u32();
        if (!in.ok() || frame.image_size > in.remaining())
            throw BadFile(path + ": the FrameEnd record " + std::to_string(i) + " does not parse");
        frame.image = frame.image_size != 0u ? in.here() : nullptr;
        frame.first = first;
        frame.end = i;
        frame.draws = std::move(draws);
        draws.clear();
        file.frames.push_back(std::move(frame));
        first = i + 1u;
    }
    if (file.frames.empty()) throw BadFile(path + " holds no whole frame");
    return file;
}

// ---- A backend being replayed into, with the guest memory and the window shell it is given ---------------------

class Lane {
public:
    explicit Lane(std::string label) : label(std::move(label)) {}
    Lane(const Lane &) = delete;
    Lane &operator=(const Lane &) = delete;
    ~Lane() { close(); }

    // Makes and initialises the backend as hle_media.cpp's ensure_backend does: a backend that needs the window gets
    // a VulkanRenderer initialised as the game's shell, passed as BackendConfig::vulkan_shell. `scale` is the
    // recording's internal scale (0 when unknown), so the targets have the recorded size.
    bool open(const std::string &name, std::uint32_t scale, std::string &error) {
        backend = gpu::make_backend(name);
        if (!backend) {
            error = "there is no GE backend " + name + " (there are:";
            for (const std::string &known : gpu::backend_names()) error += " " + known;
            error += ")";
            return false;
        }
        gpu::BackendConfig config;
        config.internal_scale = scale != 0u ? scale : portablekit::settings::current().internal_scale;
        config.sharp_textures = portablekit::settings::current().sharp_textures;
        if (backend->needs_window()) {
#if defined(PORTABLEKIT_HAS_RENDERER)
            shell = std::make_unique<gpu::VulkanRenderer>();
            gpu::RendererConfig renderer_config;
            renderer_config.title = gpu::default_window_title() + " ge_replay (" + label + ")";
            if (!shell->initialize(renderer_config, error)) {
                error = "the window shell cannot be made (" + error + ")";
                shell.reset();
                return false;
            }
            if (scale != 0u && shell->target_size()[0] != gpu::kScreenWidth * scale) shell->set_internal_scale(scale);
            config.vulkan_shell = shell.get();
#else
            error = "it draws with the window shell, and this build has no renderer";
            return false;
#endif
        }
        if (!backend->initialize(config, error)) return false;
        initialized_ = true;
        backend->begin_frame();
        memory = std::make_unique<GuestMemory>(guest_bytes());
        return true;
    }

    void close() {
        if (backend && initialized_) backend->shutdown();
        initialized_ = false;
        backend.reset();
#if defined(PORTABLEKIT_HAS_RENDERER)
        shell.reset();
#endif
        memory.reset();
    }

    void write(std::uint32_t address, const std::uint8_t *bytes, std::size_t size) {
        if (std::uint8_t *to = memory->raw_pointer(address, size)) std::memcpy(to, bytes, size);
        else outside += size;
    }

    // The rows of the block transfer the backend was last handed, copied in guest memory as hle_media.cpp's
    // block_transfer does once the backend has seen it. The Memory records after a Transfer hold the source rows as
    // that copy read them, so the copy waits for the next record of another kind.
    void finish_transfer() {
        if (!pending) return;
        const gpu::BlockTransfer transfer = *pending;
        pending.reset();
        const std::size_t row_bytes = static_cast<std::size_t>(transfer.width) * transfer.bytes_per_pixel;
        for (std::uint32_t row = 0; row < transfer.height; ++row) {
            const std::uint32_t from =
                transfer.source +
                ((transfer.source_y + row) * transfer.source_stride + transfer.source_x) * transfer.bytes_per_pixel;
            const std::uint32_t to = transfer.destination + ((transfer.destination_y + row) *
                                                                 transfer.destination_stride +
                                                             transfer.destination_x) *
                                                                transfer.bytes_per_pixel;
            const std::uint8_t *source = memory->raw_pointer(from, row_bytes);
            std::uint8_t *destination = memory->raw_pointer(to, row_bytes);
            if (source == nullptr || destination == nullptr) {
                ++transfers_outside;
                return;
            }
            std::memmove(destination, source, row_bytes);
        }
    }

    // A flip, in the order present_frame() makes it: the display target's image, the shell's present (where the
    // Vulkan backend's frame ends), the capture, and begin_frame() for the next frame. An empty `capture` skips the
    // capture. Returns false when a capture was asked for and the backend wrote none.
    bool flip(std::uint32_t display, const std::string &capture) {
        const Clock::time_point start = Clock::now();
        finish_transfer();
        (void)backend->present_image(display);
#if defined(PORTABLEKIT_HAS_RENDERER)
        if (shell) shell->present(display);
#endif
        const bool captured = capture.empty() || backend->capture_frame(capture);
        backend->begin_frame();
#if defined(PORTABLEKIT_HAS_RENDERER)
        if (shell) (void)shell->pump_events();
#endif
        ms += ms_since(start);
        return captured;
    }

    std::string label;
    std::unique_ptr<gpu::GeBackend> backend;
#if defined(PORTABLEKIT_HAS_RENDERER)
    std::unique_ptr<gpu::VulkanRenderer> shell;
#endif
    std::unique_ptr<GuestMemory> memory;
    std::optional<gpu::BlockTransfer> pending;
    double ms{};                      // time spent in this lane in the current frame
    std::uint64_t outside{};          // bytes of Memory and Words records outside guest memory
    std::uint64_t transfers_outside{};

private:
    bool initialized_{};
};

// Applies one record to every lane, as the shell made the call (ge_record_format.hpp, record_backend.cpp). FrameEnd
// is the caller's (Lane::flip); Begin, End and kinds this reader does not know do nothing.
void apply(std::size_t index, const Record &record, const std::vector<Lane *> &lanes) {
    const auto bad = [&](const char *what) {
        return BadFile("record " + std::to_string(index) + " (" + gerec::kind_name(record.kind) + "): " + what);
    };
    const auto each = [&](auto &&call) {
        for (Lane *lane : lanes) {
            const Clock::time_point start = Clock::now();
            call(*lane);
            lane->ms += ms_since(start);
        }
    };
    if (record.kind != Kind::Memory) each([](Lane &lane) { lane.finish_transfer(); });
    gerec::Reader in(record.payload, record.size);
    switch (record.kind) {
    case Kind::Memory: {
        const std::uint32_t address = in.u32();
        const std::uint32_t size = in.u32();
        if (!in.ok() || size > in.remaining()) throw bad("the bytes are cut short");
        const std::uint8_t *bytes = in.here();
        each([&](Lane &lane) { lane.write(address, bytes, size); });
        break;
    }
    case Kind::Words: {
        const std::uint32_t address = in.u32();
        const std::uint32_t step = in.u32();
        const std::uint32_t count = in.u32();
        if (!in.ok() || static_cast<std::uint64_t>(count) * 4u > in.remaining()) throw bad("the words are cut short");
        const std::uint8_t *words = in.here();
        each([&](Lane &lane) {
            for (std::uint32_t i = 0; i < count; ++i) lane.write(address + i * step, words + i * 4u, 4u);
        });
        break;
    }
    case Kind::DisplayList: each([](Lane &lane) { lane.backend->begin_display_list(); }); break;
    case Kind::Draw: {
        gerec::RecordedDraw draw;
        in.get(draw);
        if (!in.ok()) throw bad("the draw does not parse");
        each([&](Lane &lane) { lane.backend->submit(draw.call, *lane.memory); });
        break;
    }
    case Kind::Transfer: {
        gpu::BlockTransfer transfer;
        in.get(transfer);
        if (!in.ok()) throw bad("the transfer does not parse");
        each([&](Lane &lane) {
            lane.backend->block_transfer(transfer, *lane.memory);
            lane.pending = transfer;
        });
        break;
    }
    case Kind::ReadBack: {
        const std::uint32_t address = in.u32();
        if (!in.ok()) throw bad("no address");
        each([&](Lane &lane) { lane.backend->read_back_framebuffer(address, *lane.memory); });
        break;
    }
    case Kind::WriteBackFrame: each([](Lane &lane) { lane.backend->write_back_frame(*lane.memory); }); break;
    case Kind::WriteBackDepth: {
        const std::uint32_t color = in.u32();
        const std::uint32_t depth = in.u32();
        const std::uint32_t stride = in.u32();
        (void)in.flag();  // whether the recorded backend wrote
        const std::string why = in.string();
        if (!in.ok()) throw bad("the arguments do not parse");
        each([&](Lane &lane) {
            (void)lane.backend->write_back_depth(color, depth, stride, *lane.memory, why.c_str());
        });
        break;
    }
    case Kind::Upload: {
        const std::uint32_t display = in.u32();
        const std::uint32_t width = in.u32();
        const std::uint32_t height = in.u32();
        if (!in.ok() || static_cast<std::uint64_t>(width) * height * 4u > in.remaining())
            throw bad("the pixels are cut short");
        const std::uint8_t *pixels = in.here();
        each([&](Lane &lane) { lane.backend->upload_frame(display, pixels, width, height, width); });
        break;
    }
    default: break;
    }
}

// ---- What a differing draw was drawn with ----------------------------------------------------------------------

const char *target_format_name(std::uint32_t format) {
    static constexpr const char *names[] = {"5650", "5551", "4444", "8888"};
    return format < std::size(names) ? names[format] : "?";
}

void describe(const gpu::DrawCall &call, std::ostream &out) {
    const auto on = [](bool value) { return value ? "on" : "off"; };
    out << "  primitive " << pure::gpu::primitive_name(call.primitive) << ", " << call.vertices.size() << " vertices, "
        << call.indices.size() << " indices, " << (call.through ? "through" : "transformed") << ", vertex type "
        << hex(call.vertex_type) << "\n";
    out << "  target " << hex(call.target.color_address) << " " << target_format_name(call.target.color_format)
        << " stride " << call.target.color_stride << ", depth " << hex(call.target.depth_address) << " stride "
        << call.target.depth_stride << "\n";
    const gpu::TextureState &t = call.texture;
    if (t.enabled) {
        out << "  texture " << hex(t.address) << " " << pure::gpu::texture_format_name(t.format) << " " << t.width << "x"
            << t.height << " buffer " << t.buffer_width << (t.swizzled ? " swizzled" : "");
        if (t.format >= gpu::TextureFormat::Clut4 && t.format <= gpu::TextureFormat::Clut32)
            out << ", clut " << hex(t.clut_address) << " format " << t.clut_format << " shift " << t.clut_shift
                << " mask " << hex(t.clut_mask, 2) << " offset " << t.clut_offset;
        out << ", function " << t.function << (t.alpha_from_texture ? " with texture alpha" : "") << ", filter "
            << t.min_filter << "/" << t.mag_filter << ", wrap " << t.wrap_s << "/" << t.wrap_t << "\n";
    } else {
        out << "  texture off\n";
    }
    out << "  blend " << on(call.blend.enabled) << ": source " << call.blend.source_factor << " destination "
        << call.blend.destination_factor << " equation " << call.blend.equation << ", fixed "
        << hex(call.blend.fixed_source, 6) << "/" << hex(call.blend.fixed_destination, 6) << "\n";
    out << "  alpha test " << on(call.alpha_test.enabled) << ": function " << call.alpha_test.function
        << " reference " << hex(call.alpha_test.reference, 2) << " mask " << hex(call.alpha_test.mask, 2) << "\n";
    out << "  stencil " << on(call.stencil.enabled) << ": function " << call.stencil.function << " reference "
        << hex(call.stencil.reference, 2) << " mask " << hex(call.stencil.mask, 2) << ", ops fail "
        << call.stencil.fail_op << " depth fail " << call.stencil.depth_fail_op << " pass " << call.stencil.pass_op
        << "\n";
    out << "  clear mode " << on(call.clear_mode);
    if (call.clear_mode)
        out << ": flags " << call.clear_flags << " (colour " << on((call.clear_flags & 1u) != 0u) << ", alpha/stencil "
            << on((call.clear_flags & 2u) != 0u) << ", depth " << on((call.clear_flags & 4u) != 0u) << ")";
    out << "\n";
    out << "  depth test " << on(call.depth.test_enabled) << " function " << call.depth.function << ", write "
        << on(call.depth.write_enabled) << ", write masks colour " << hex(call.color_write_mask, 6) << " alpha "
        << hex(call.alpha_write_mask, 2) << "\n";
}

// ---- The command -----------------------------------------------------------------------------------------------

struct Options {
    std::string file;
    std::string backend{"null"};
    bool backend_given{};
    std::string out;
    bool compare{};
    int tol{};
    double max_frac{};
    std::uint32_t first{};
    std::uint32_t last{0xFFFFFFFFu};
    std::size_t cut{};  // --cut N: the last frame replayed ends after its Nth draw (0: whole)
    std::string a;
    std::string b;
    bool first_diff{};
    bool quiet{};
};

const char *const kUsage =
    "usage: PureNative --replay FILE.gerec [--backend NAME] [--out DIR] [--compare] [--tol T] [--max-frac F]\n"
    "                                    [--frames A[-B]] [--cut N] [--a NAME --b NAME [--first-diff]] [--quiet]\n"
    "  --backend NAME  the GE backend to replay into (default null)\n"
    "  --out DIR       write each replayed frame as DIR/frame_N.bmp (DIR/a/ and DIR/b/ with --a/--b)\n"
    "  --compare       compare each frame with its recorded image (tools/imgdiff.py's comparison)\n"
    "  --tol T         a pixel differs when a channel differs by more than T (default 0)\n"
    "  --max-frac F    a frame passes when at most this fraction of its pixels differ (default 0)\n"
    "  --frames A[-B]  report and compare frames A to B only (earlier ones are replayed silently, later ones not)\n"
    "  --cut N         the last frame replayed (B, or the recording's last) only up to and including its Nth draw,\n"
    "                  then presented and captured (--out keeps the pictures)\n"
    "  --a, --b NAME   replay into two backends at once and compare their pictures per frame\n"
    "  --first-diff    with --a/--b: bisect the first failing frame to the first draw whose pictures differ\n"
    "  --quiet         print only failures and the summary\n"
    "exit 0: every compared frame passed (or nothing was compared); 1: a frame failed; 2: bad arguments, a bad file\n"
    "or a backend that cannot run\n";

int usage_error(const std::string &message) {
    std::cerr << "[replay] " << message << "\n" << kUsage;
    return 2;
}

bool parse_number(const std::string &text, double &value) {
    char *end = nullptr;
    value = std::strtod(text.c_str(), &end);
    return !text.empty() && end != nullptr && *end == '\0';
}

bool parse_frames(const std::string &text, std::uint32_t &first, std::uint32_t &last) {
    const std::size_t dash = text.find('-');
    const auto number = [](const std::string &part, std::uint32_t &value) {
        if (part.empty() || part.find_first_not_of("0123456789") != std::string::npos) return false;
        value = static_cast<std::uint32_t>(std::strtoul(part.c_str(), nullptr, 10));
        return true;
    };
    if (dash == std::string::npos) {
        if (!number(text, first)) return false;
        last = first;
        return true;
    }
    return number(text.substr(0, dash), first) && number(text.substr(dash + 1u), last) && first <= last;
}

// Returns 0 when parsed, 1 after --help, 2 on an error (printed).
int parse(int argc, char **argv, Options &options) {
    for (int i = 2; i < argc; ++i) {
        const std::string arg = argv[i];
        const auto value = [&](std::string &into) {
            if (i + 1 >= argc) return false;
            into = argv[++i];
            return true;
        };
        std::string text;
        double number = 0.0;
        if (arg == "--help" || arg == "-h") {
            std::cout << kUsage;
            return 1;
        } else if (arg == "--backend") {
            if (!value(options.backend)) return usage_error("--backend needs a name");
            options.backend_given = true;
        } else if (arg == "--out") {
            if (!value(options.out)) return usage_error("--out needs a directory");
        } else if (arg == "--compare") {
            options.compare = true;
        } else if (arg == "--tol") {
            if (!value(text) || !parse_number(text, number) || number < 0.0 || number > 255.0 ||
                number != static_cast<int>(number))
                return usage_error("--tol takes a whole number from 0 to 255");
            options.tol = static_cast<int>(number);
        } else if (arg == "--max-frac") {
            if (!value(text) || !parse_number(text, number) || number < 0.0 || number > 1.0)
                return usage_error("--max-frac takes a fraction from 0 to 1");
            options.max_frac = number;
        } else if (arg == "--frames") {
            if (!value(text) || !parse_frames(text, options.first, options.last))
                return usage_error("--frames takes A or A-B (frame numbers, A <= B)");
        } else if (arg == "--cut") {
            if (!value(text) || text.empty() || text.find_first_not_of("0123456789") != std::string::npos ||
                std::strtoull(text.c_str(), nullptr, 10) == 0u)
                return usage_error("--cut takes a draw count of 1 or more");
            options.cut = static_cast<std::size_t>(std::strtoull(text.c_str(), nullptr, 10));
        } else if (arg == "--a") {
            if (!value(options.a)) return usage_error("--a needs a backend name");
        } else if (arg == "--b") {
            if (!value(options.b)) return usage_error("--b needs a backend name");
        } else if (arg == "--first-diff") {
            options.first_diff = true;
        } else if (arg == "--quiet") {
            options.quiet = true;
        } else if (!arg.empty() && arg[0] == '-') {
            return usage_error("unknown option " + arg);
        } else if (options.file.empty()) {
            options.file = arg;
        } else {
            return usage_error("unexpected argument " + arg);
        }
    }
    if (options.file.empty()) return usage_error("no recording named");
    if (options.a.empty() != options.b.empty()) return usage_error("--a and --b go together");
    if (!options.a.empty() && options.backend_given) return usage_error("--backend or --a/--b, not both");
    if (options.first_diff && options.a.empty()) return usage_error("--first-diff needs --a and --b");
    return 0;
}

std::string temp_capture(const std::string &tag) {
    std::error_code ignored;
    const std::filesystem::path dir = std::filesystem::temp_directory_path(ignored);
    return (dir / ("ge_replay_" + std::to_string(getpid()) + "_" + tag + ".bmp")).string();
}

std::string format_ms(double ms) {
    char text[32];
    std::snprintf(text, sizeof text, "%.1f", ms);
    return text;
}

std::string format_diff(const Diff &diff, const Options &options, bool pass) {
    char text[160];
    std::snprintf(text, sizeof text, "diff %.6f (tol %d, %llu/%llu px at %ux%u) %s", diff.fraction, options.tol,
                  static_cast<unsigned long long>(diff.differing), static_cast<unsigned long long>(diff.total),
                  diff.width, diff.height, pass ? "PASS" : "FAIL");
    return text;
}

// The internal scale the recording was drawn at, from its first image of a multiple of 480x272; 0 when none is.
std::uint32_t recorded_scale(const Recording &file) {
    for (const Frame &frame : file.frames) {
        if (frame.width == 0u || frame.width % gpu::kScreenWidth != 0u) continue;
        const std::uint32_t scale = frame.width / gpu::kScreenWidth;
        if (frame.height == gpu::kScreenHeight * scale) return scale;
    }
    return 0u;
}

class Replay {
public:
    Replay(const Options &options, const Recording &file) : options_(options), file_(file) {}

    int run() {
        scale_ = recorded_scale(file_);
        const bool pair = !options_.a.empty();
        std::vector<std::unique_ptr<Lane>> owned;
        std::vector<Lane *> lanes;
        if (pair) {
            owned.push_back(std::make_unique<Lane>("a: " + options_.a));
            owned.push_back(std::make_unique<Lane>("b: " + options_.b));
        } else {
            owned.push_back(std::make_unique<Lane>(options_.backend));
        }
        for (std::size_t i = 0; i < owned.size(); ++i) {
            std::string error;
            const std::string &name = pair ? (i == 0u ? options_.a : options_.b) : options_.backend;
            if (!owned[i]->open(name, scale_, error)) {
                std::cerr << "[replay] backend " << name << " cannot run: " << error << "\n";
                return 2;
            }
            lanes.push_back(owned[i].get());
        }
        std::vector<std::string> out_dirs(lanes.size());
        if (!options_.out.empty()) {
            for (std::size_t i = 0; i < lanes.size(); ++i) {
                std::filesystem::path dir = options_.out;
                if (pair) dir /= i == 0u ? "a" : "b";
                std::error_code error;
                std::filesystem::create_directories(dir, error);
                if (error) {
                    std::cerr << "[replay] cannot make " << dir.string() << ": " << error.message() << "\n";
                    return 2;
                }
                out_dirs[i] = dir.string();
            }
        }
        const bool comparing = pair || options_.compare;
        if (!options_.quiet) {
            std::cout << "[replay] " << options_.file << ": frames " << file_.frames.front().number << "-"
                      << file_.frames.back().number << " recorded from " << file_.inner << " (format "
                      << file_.version << ", " << file_.records.size() << " records"
                      << (file_.ended ? "" : ", no End record") << "), replayed into "
                      << (pair ? options_.a + " and " + options_.b : options_.backend);
            if (scale_ != 0u) std::cout << " at " << scale_ << "x";
            std::cout << "\n";
        }

        // --cut: the last frame the loop below replays ends after its Nth draw.
        cut_frame_.reset();
        if (options_.cut != 0u) {
            for (std::size_t f = 0; f < file_.frames.size() && file_.frames[f].number <= options_.last; ++f) cut_frame_ = f;
        }
        std::size_t replayed = 0u, compared = 0u, passed = 0u;
        std::optional<std::size_t> first_failing;
        double worst = -1.0;
        std::uint32_t worst_frame = 0u;
        std::vector<double> total_ms(lanes.size(), 0.0);
        for (std::size_t f = 0; f < file_.frames.size(); ++f) {
            const Frame &frame = file_.frames[f];
            if (frame.number > options_.last) break;
            const bool wanted = frame.number >= options_.first;
            for (Lane *lane : lanes) lane->ms = 0.0;
            const std::size_t end = records_end(f);
            for (std::size_t r = frame.first; r < end; ++r) apply(r, file_.records[r], lanes);
            std::vector<std::string> captures(lanes.size());
            std::vector<bool> captured(lanes.size(), true);
            for (std::size_t i = 0; i < lanes.size(); ++i) {
                if (wanted && !out_dirs[i].empty())
                    captures[i] = out_dirs[i] + "/frame_" + std::to_string(frame.number) + ".bmp";
                else if (wanted && comparing)
                    captures[i] = temp_capture(std::to_string(i));
                captured[i] = lanes[i]->flip(frame.display, captures[i]);
            }
            if (!wanted) continue;
            ++replayed;
            std::ostringstream line;
            line << "[replay] frame " << frame.number << ": " << frame.draws.size() << " draws, "
                 << (frame.end - frame.first) << " records, ";
            if (cut_frame_ == f)
                line << (options_.cut <= frame.draws.size()
                             ? "cut after draw " + std::to_string(options_.cut) + " (" + std::to_string(end - frame.first) +
                                   " records), "
                             : "--cut " + std::to_string(options_.cut) + " reaches past its last draw: whole, ");
            for (std::size_t i = 0; i < lanes.size(); ++i) {
                total_ms[i] += lanes[i]->ms;
                line << (i != 0u ? " + " : "") << format_ms(lanes[i]->ms);
            }
            line << " ms";
            if (pair) line << " (" << options_.a << " + " << options_.b << ")";
            bool failed = false;
            if (comparing) {
                Image left, right;
                std::string error;
                bool usable = true;
                if (!captured[0] || !read_bmp(captures[0], left, error)) {
                    error = lanes[0]->label + " presented no picture" + (error.empty() ? "" : ": " + error);
                    usable = false;
                } else if (pair) {
                    if (!captured[1] || !read_bmp(captures[1], right, error)) {
                        error = lanes[1]->label + " presented no picture" + (error.empty() ? "" : ": " + error);
                        usable = false;
                    }
                } else if (frame.image == nullptr) {
                    line << ", no recorded image: not compared";
                } else if (!decode_bmp(frame.image, frame.image_size, right, error)) {
                    error = "the recorded image: " + error;
                    usable = false;
                }
                if (!usable) {
                    ++compared;
                    failed = true;
                    line << ", " << error << ": FAIL";
                } else if (!right.rgb.empty()) {
                    const Diff diff = compare(left, right, options_.tol);
                    const bool pass = diff.fraction <= options_.max_frac;
                    ++compared;
                    if (pass) ++passed;
                    failed = !pass;
                    if (diff.fraction > worst) {
                        worst = diff.fraction;
                        worst_frame = frame.number;
                    }
                    line << ", " << format_diff(diff, options_, pass);
                }
                if (failed && !first_failing) first_failing = f;
            }
            if (!options_.quiet || failed) std::cout << line.str() << "\n";
            const bool counts_differ =
                frame.draws.size() != frame.draws_said || frame.end - frame.first != frame.records_said;
            if (!options_.quiet && counts_differ)
                std::cout << "[replay] frame " << frame.number << ": its FrameEnd says " << frame.draws_said
                          << " draws and " << frame.records_said << " records\n";
        }
        for (Lane *lane : lanes) {
            if (lane->outside != 0u || lane->transfers_outside != 0u)
                std::cout << "[replay] " << lane->label << ": " << lane->outside
                          << " recorded bytes and " << lane->transfers_outside
                          << " block transfers fell outside guest memory and were left out\n";
        }
        for (const std::string &capture : {temp_capture("0"), temp_capture("1")}) {
            std::error_code ignored;
            std::filesystem::remove(capture, ignored);
        }
        owned.clear();
        lanes.clear();

        const bool ok = compared == passed;
        std::ostringstream summary;
        summary << "[replay] summary: " << replayed << (replayed == 1u ? " frame" : " frames") << " replayed into "
                << (pair ? options_.a + " and " + options_.b : options_.backend);
        if (replayed != 0u) {
            summary << " (";
            for (std::size_t i = 0; i < total_ms.size(); ++i)
                summary << (i != 0u ? ", " : "") << format_ms(total_ms[i] / static_cast<double>(replayed))
                        << " ms a frame" << (pair ? std::string(" in ") + (i == 0u ? options_.a : options_.b) : "");
            summary << ")";
        }
        if (comparing) {
            summary << ", " << compared << " compared, " << passed << " passed";
            if (worst >= 0.0) {
                char text[64];
                std::snprintf(text, sizeof text, ", worst diff %.6f (frame %u)", worst, worst_frame);
                summary << text;
            }
        }
        int code = ok ? 0 : 1;
        if (replayed == 0u) summary << "; no frame of the recording is in --frames";
        summary << "; exit " << code;
        std::cout << summary.str() << "\n";

        if (options_.first_diff && first_failing) {
            const int bisect = first_diff(*first_failing);
            if (bisect == 2) code = 2;
        }
        std::cout << std::flush;
        return code;
    }

private:
    // Where frame `f`'s records end: its FrameEnd, or with --cut, for the last frame replayed, the record after its
    // Nth Draw.
    std::size_t records_end(std::size_t f) const {
        const Frame &frame = file_.frames[f];
        if (cut_frame_ != f || options_.cut > frame.draws.size()) return frame.end;
        return frame.draws[options_.cut - 1u] + 1u;
    }

    // Replays the file from its Begin into fresh lanes A and B: every frame before `f` whole, then frame `f`'s
    // records up to and including its `n`th Draw, then a flip; returns how the two pictures compare.
    std::optional<Diff> prefix(std::size_t f, std::size_t n, std::string &error) {
        Lane a("a: " + options_.a), b("b: " + options_.b);
        if (!a.open(options_.a, scale_, error) || !b.open(options_.b, scale_, error)) return std::nullopt;
        const std::vector<Lane *> lanes{&a, &b};
        for (std::size_t g = 0; g < f; ++g) {
            const Frame &frame = file_.frames[g];
            for (std::size_t r = frame.first; r < frame.end; ++r) apply(r, file_.records[r], lanes);
            a.flip(frame.display, {});
            b.flip(frame.display, {});
        }
        const Frame &frame = file_.frames[f];
        const std::size_t last = frame.draws[n - 1u];
        for (std::size_t r = frame.first; r <= last; ++r) apply(r, file_.records[r], lanes);
        const std::string left_path = temp_capture("prefix_a"), right_path = temp_capture("prefix_b");
        const bool left_ok = a.flip(frame.display, left_path);
        const bool right_ok = b.flip(frame.display, right_path);
        Image left, right;
        std::optional<Diff> diff;
        if (!left_ok || !right_ok) error = "a backend presented no picture";
        else if (read_bmp(left_path, left, error) && read_bmp(right_path, right, error))
            diff = compare(left, right, options_.tol);
        std::error_code ignored;
        std::filesystem::remove(left_path, ignored);
        std::filesystem::remove(right_path, ignored);
        return diff;
    }

    // Bisects frame `f` to the smallest number of its draws after which the two pictures differ.
    int first_diff(std::size_t f) {
        const Frame &frame = file_.frames[f];
        // A frame cut with --cut is bisected within the draws it was cut to.
        const std::size_t draws = cut_frame_ == f ? std::min(options_.cut, frame.draws.size()) : frame.draws.size();
        if (draws == 0u) {
            std::cout << "[replay] frame " << frame.number
                      << " has no draws: the difference comes from its uploads, transfers or write-backs\n";
            return 1;
        }
        std::cout << "[replay] bisecting frame " << frame.number << " (" << draws << " draws) between "
                  << options_.a << " and " << options_.b << "\n";
        const auto differs = [&](std::size_t n, bool &result) {
            std::string error;
            const Clock::time_point start = Clock::now();
            const std::optional<Diff> diff = prefix(f, n, error);
            if (!diff) {
                std::cerr << "[replay] the prefix of " << n << " draws cannot be compared: " << error << "\n";
                return false;
            }
            result = diff->fraction > options_.max_frac;
            std::cout << "[replay]   " << n << (n == 1u ? " draw: " : " draws: ")
                      << format_diff(*diff, options_, !result) << " (" << format_ms(ms_since(start)) << " ms)\n";
            return true;
        };
        std::size_t low = 1u, high = draws;
        bool result = false;
        while (low < high) {
            const std::size_t middle = low + (high - low) / 2u;
            if (!differs(middle, result)) return 2;
            if (result) high = middle;
            else low = middle + 1u;
        }
        if (low == draws) {
            if (!differs(draws, result)) return 2;
            if (!result) {
                std::cout << "[replay] frame " << frame.number << ": the pictures agree after all " << draws
                          << " draws; they differ only through the records after the last draw\n";
                return 1;
            }
        }
        const std::size_t record = frame.draws[low - 1u];
        std::cout << "[replay] first difference in frame " << frame.number << ": draw " << low << " of " << draws
                  << " (record " << record << " in gerec_dump.py's listing)\n";
        gerec::RecordedDraw draw;
        gerec::Reader in(file_.records[record].payload, file_.records[record].size);
        in.get(draw);
        describe(draw.call, std::cout);
        return 1;
    }

    const Options &options_;
    const Recording &file_;
    std::uint32_t scale_{};
    std::optional<std::size_t> cut_frame_;  // the frame --cut cuts, by index
};

} // namespace

int run(int argc, char **argv) {
    Options options;
    if (const int parsed = parse(argc, argv, options); parsed != 0) return parsed == 1 ? 0 : 2;
    try {
        const Recording file = load(options.file);
        Replay replay(options, file);
        return replay.run();
    } catch (const BadFile &error) {
        std::cerr << "[replay] bad recording: " << error.what() << "\n";
        return 2;
    } catch (const std::exception &error) {
        std::cerr << "[replay] error: " << error.what() << "\n";
        return 2;
    }
}

} // namespace pure::replay
