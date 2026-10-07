// The Metal backend's pipelines (docs/metal-backend.md, "The pipeline key" and "The pre-warm list"): the fragment
// function's variants, a render pipeline per RenderKey and a depth-stencil state per DepthStencilKey, made on first
// use or taken from the pre-warm, which makes config/metal_pipelines.txt's keys at start; the keys' text form and
// its parser, and the list a run used (PURE_METAL_PIPELINES_OUT).
#include "metal_backend.hpp"
#include "profile.hpp"

#include <chrono>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <mutex>
#include <set>
#include <sstream>
#include <string>
#include <vector>

namespace pure::gpu::metal_backend {
namespace {

// The GE's stencil operations: 0 KEEP, 1 ZERO, 2 REPLACE, 3 INVERT, 4 INCR, 5 DECR (both clamping).
MTLStencilOperation to_stencil_operation(std::uint32_t op) {
    switch (op & 7u) {
    case 1u: return MTLStencilOperationZero;
    case 2u: return MTLStencilOperationReplace;
    case 3u: return MTLStencilOperationInvert;
    case 4u: return MTLStencilOperationIncrementClamp;
    case 5u: return MTLStencilOperationDecrementClamp;
    default: return MTLStencilOperationKeep;
    }
}

// The pre-warm list's text (config/metal_pipelines.txt, PURE_METAL_PIPELINES_OUT): a line per key, `render` or
// `depth` and the key's fields as name=value, the numbers the key holds (Metal's values for the blend factors and
// operations, the write masks and the depth compare; the GE's for the stencil function and operations).
std::string to_text(const RenderKey &key) {
    std::ostringstream out;
    out << "render blend=" << unsigned{key.blend} << " source=" << unsigned{key.source}
        << " destination=" << unsigned{key.destination} << " operation=" << unsigned{key.operation}
        << " write_mask=" << unsigned{key.write_mask} << " alpha_destination=" << unsigned{key.alpha_destination}
        << " dual_source=" << unsigned{key.dual_source} << " textured=" << unsigned{key.textured}
        << " alpha_test=" << unsigned{key.alpha_test} << " color_test=" << unsigned{key.color_test}
        << " sixteen=" << unsigned{key.sixteen};
    return out.str();
}

std::string to_text(const DepthStencilKey &key) {
    std::ostringstream out;
    out << "depth compare=" << unsigned{key.compare} << " write=" << unsigned{key.write}
        << " stencil=" << unsigned{key.stencil} << " function=" << unsigned{key.stencil_function}
        << " fail=" << unsigned{key.fail} << " depth_fail=" << unsigned{key.depth_fail} << " pass=" << unsigned{key.pass}
        << " compare_mask=" << unsigned{key.compare_mask} << " write_mask=" << unsigned{key.write_mask};
    return out.str();
}

// A line of the list as its kind and fields; false for a blank line or a comment (`#`).
bool parse_key_line(const std::string &line, std::string &kind, std::map<std::string, unsigned> &fields) {
    std::istringstream in(line);
    if (!(in >> kind) || kind.front() == '#') return false;
    fields.clear();
    for (std::string field; in >> field;) {
        const std::size_t equals = field.find('=');
        if (equals == std::string::npos) return false;
        fields[field.substr(0, equals)] = static_cast<unsigned>(std::strtoul(field.c_str() + equals + 1, nullptr, 10));
    }
    return true;
}

// The field `name` into `out` when present and it fits; false otherwise.
template <typename T>
bool take_field(const std::map<std::string, unsigned> &fields, const char *name, T &out, unsigned largest = 255u) {
    const auto found = fields.find(name);
    if (found == fields.end() || found->second > largest) return false;
    out = static_cast<T>(found->second);
    return true;
}

// A field added after the list was first written (task 040's color_test and sixteen): 0 when the line has none.
template <typename T>
bool take_later_field(const std::map<std::string, unsigned> &fields, const char *name, T &out, unsigned largest) {
    if (fields.find(name) == fields.end()) {
        out = T{};
        return true;
    }
    return take_field(fields, name, out, largest);
}

bool from_fields(const std::map<std::string, unsigned> &fields, RenderKey &key) {
    return take_field(fields, "blend", key.blend, 1u) && take_field(fields, "source", key.source) &&
           take_field(fields, "destination", key.destination) && take_field(fields, "operation", key.operation) &&
           take_field(fields, "write_mask", key.write_mask) &&
           take_field(fields, "alpha_destination", key.alpha_destination) &&
           take_field(fields, "dual_source", key.dual_source, 1u) && take_field(fields, "textured", key.textured, 1u) &&
           take_field(fields, "alpha_test", key.alpha_test, 1u) &&
           take_later_field(fields, "color_test", key.color_test, 1u) &&
           take_later_field(fields, "sixteen", key.sixteen, 1u);
}

bool from_fields(const std::map<std::string, unsigned> &fields, DepthStencilKey &key) {
    return take_field(fields, "compare", key.compare, 7u) && take_field(fields, "write", key.write, 1u) &&
           take_field(fields, "stencil", key.stencil, 1u) && take_field(fields, "function", key.stencil_function, 7u) &&
           take_field(fields, "fail", key.fail, 7u) && take_field(fields, "depth_fail", key.depth_fail, 7u) &&
           take_field(fields, "pass", key.pass, 7u) && take_field(fields, "compare_mask", key.compare_mask) &&
           take_field(fields, "write_mask", key.write_mask);
}

} // namespace

// The GE's compare functions (depth test, alpha test, stencil test): 0 NEVER, 1 ALWAYS, then EQUAL,
// NOTEQUAL, LESS, LEQUAL, GREATER, GEQUAL.
MTLCompareFunction to_compare(std::uint32_t function) {
    switch (function & 7u) {
    case 0u: return MTLCompareFunctionNever;
    case 1u: return MTLCompareFunctionAlways;
    case 2u: return MTLCompareFunctionEqual;
    case 3u: return MTLCompareFunctionNotEqual;
    case 4u: return MTLCompareFunctionLess;
    case 5u: return MTLCompareFunctionLessEqual;
    case 6u: return MTLCompareFunctionGreater;
    default: return MTLCompareFunctionGreaterEqual;
    }
}

// The fragment function by kTextured | kAlphaTest << 1 | dual source << 2 | kColorTest << 3 | 16-bit target << 4
// (ge_fragment, ge_fragment_dual or ge_fragment_16, specialised), made on first use.
id<MTLFunction> MetalGeBackend::fragment_function(std::uint32_t variant, NSError **failure) {
    variant &= 31u;
    if (fragment_functions_[variant] != nil) return fragment_functions_[variant];
    MTLFunctionConstantValues *values = [MTLFunctionConstantValues new];
    const bool textured = (variant & 1u) != 0u;
    const bool alpha_test = (variant & 2u) != 0u;
    const bool color_test = (variant & 8u) != 0u;
    [values setConstantValue:&textured type:MTLDataTypeBool atIndex:0];
    [values setConstantValue:&alpha_test type:MTLDataTypeBool atIndex:1];
    [values setConstantValue:&color_test type:MTLDataTypeBool atIndex:2];
    NSString *name = (variant & 16u) != 0u ? @"ge_fragment_16"
                     : (variant & 4u) != 0u ? @"ge_fragment_dual"
                                             : @"ge_fragment";
    NSError *error = nil;
    fragment_functions_[variant] = [library_ newFunctionWithName:name constantValues:values error:&error];
    if (fragment_functions_[variant] == nil) {
        std::cout << "[metal] the fragment function " << name.UTF8String << " " << variant
                  << " does not specialise: " << (error != nil ? error.localizedDescription.UTF8String : "no message")
                  << "\n";
        if (failure != nullptr) *failure = error;
    }
    return fragment_functions_[variant];
}

// The descriptor of a render pipeline: what render_pipeline() makes on first use and the pre-warm ahead of it.
MTLRenderPipelineDescriptor *MetalGeBackend::pipeline_descriptor(const RenderKey &key) {
    MTLRenderPipelineDescriptor *descriptor = [MTLRenderPipelineDescriptor new];
    descriptor.vertexFunction = vertex_function_;
    descriptor.fragmentFunction = fragment_function((key.textured ? 1u : 0u) | (key.alpha_test ? 2u : 0u) |
                                                    (key.dual_source ? 4u : 0u) | (key.color_test ? 8u : 0u) |
                                                    (key.sixteen ? 16u : 0u));
    // With dual-source blending the colour blend's source alpha is the fragment's own, from the second
    // output, while the first output's alpha is the stencil value the target stores.
    const auto colour_factor = [&](std::uint8_t factor) {
        const auto metal = static_cast<MTLBlendFactor>(factor);
        if (!key.dual_source) return metal;
        if (metal == MTLBlendFactorSourceAlpha) return MTLBlendFactorSource1Alpha;
        if (metal == MTLBlendFactorOneMinusSourceAlpha) return MTLBlendFactorOneMinusSource1Alpha;
        return metal;
    };
    MTLRenderPipelineColorAttachmentDescriptor *colour = descriptor.colorAttachments[0];
    colour.pixelFormat = MTLPixelFormatRGBA8Unorm;
    colour.writeMask = key.write_mask;
    colour.blendingEnabled = key.blend;
    colour.rgbBlendOperation = static_cast<MTLBlendOperation>(key.operation);
    colour.sourceRGBBlendFactor = colour_factor(key.source);
    colour.destinationRGBBlendFactor = colour_factor(key.destination);
    // The alpha is the PSP's stencil: the fragment's value (the stencil value or a clear's alpha) is stored
    // as it is, or added for the copy of the stencil into the alpha.
    colour.alphaBlendOperation = MTLBlendOperationAdd;
    colour.sourceAlphaBlendFactor = MTLBlendFactorOne;
    colour.destinationAlphaBlendFactor = static_cast<MTLBlendFactor>(key.alpha_destination);
    descriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
    descriptor.stencilAttachmentPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
    return descriptor;
}

id<MTLRenderPipelineState> MetalGeBackend::render_pipeline(const RenderKey &key) {
    if (const auto found = render_pipelines_.find(key); found != render_pipelines_.end()) return found->second;
    const TraceClock clock(trace_file_ != nullptr, times_.pipeline);
    render_seen_.insert(key);
    bool waited = false;
    if (prewarm_) {
        // Made at start, or still being made: then this draw waits for it, which is still quicker than
        // compiling it a second time.
        std::unique_lock<std::mutex> lock(prewarm_->lock);
        if (prewarm_->pending.count(key) != 0u) {
            waited = true;
            ++prewarm_waits_;
            prewarm_->changed.wait(lock, [&] { return prewarm_->pending.count(key) == 0u; });
        }
        if (const auto ready = prewarm_->ready.find(key); ready != prewarm_->ready.end()) {
            id<MTLRenderPipelineState> state = ready->second;
            prewarm_->ready.erase(ready);
            lock.unlock();
            // A draw that had to wait for the pre-warm counts as one that made its pipeline.
            if (waited) ++stats_.pipelines_made;
            ++prewarm_used_;
            render_pipelines_.emplace(key, state);
            return state;
        }
    }
    NSError *failure = nil;
    id<MTLRenderPipelineState> state = [device_ newRenderPipelineStateWithDescriptor:pipeline_descriptor(key)
                                                                                error:&failure];
    if (state == nil)
        std::cout << "[metal] cannot make a pipeline: "
                  << (failure != nil ? failure.localizedDescription.UTF8String : "no message") << "\n";
    ++stats_.pipelines_made;
    if (prewarm_) ++prewarm_missed_;
    if (log_draws_) std::cout << "[metal] frame " << frames_ + 1u << " new pipeline " << to_text(key) << "\n";
    render_pipelines_.emplace(key, state);
    return state;
}

// A depth-stencil state, made on first use unless the pre-warm made it at start.
id<MTLDepthStencilState> MetalGeBackend::depth_state(const DepthStencilKey &key) {
    if (const auto found = depth_states_.find(key); found != depth_states_.end()) {
        if (!pipelines_out_.empty()) depth_seen_.insert(key);
        return found->second;
    }
    const TraceClock clock(trace_file_ != nullptr, times_.pipeline);
    depth_seen_.insert(key);
    ++stats_.depth_states_made;
    if (log_draws_) std::cout << "[metal] frame " << frames_ + 1u << " new depth state " << to_text(key) << "\n";
    id<MTLDepthStencilState> state = make_depth_state(key);
    depth_states_.emplace(key, state);
    return state;
}

id<MTLDepthStencilState> MetalGeBackend::make_depth_state(const DepthStencilKey &key) {
    MTLDepthStencilDescriptor *descriptor = [MTLDepthStencilDescriptor new];
    descriptor.depthCompareFunction = static_cast<MTLCompareFunction>(key.compare);
    descriptor.depthWriteEnabled = key.write;
    if (key.stencil) {
        // The GE compares the reference with the stored stencil (reference OP stencil, both under the
        // compare mask) as Metal does, with the alpha test's function numbers; both faces alike.
        MTLStencilDescriptor *stencil = [MTLStencilDescriptor new];
        stencil.stencilCompareFunction = to_compare(key.stencil_function);
        stencil.stencilFailureOperation = to_stencil_operation(key.fail);
        stencil.depthFailureOperation = to_stencil_operation(key.depth_fail);
        stencil.depthStencilPassOperation = to_stencil_operation(key.pass);
        stencil.readMask = key.compare_mask;
        stencil.writeMask = key.write_mask;
        descriptor.frontFaceStencil = stencil;
        descriptor.backFaceStencil = stencil;
    }
    return [device_ newDepthStencilStateWithDescriptor:descriptor];
}

// The pre-warm list: PURE_METAL_PIPELINES names it (0 or empty turns the pre-warm off); otherwise
// metal_pipelines.txt in an app's Resources, config/metal_pipelines.txt three levels above the executable
// (build/<preset>/bin in a checkout), or config/metal_pipelines.txt under the working directory.
std::string MetalGeBackend::find_pipeline_list() {
    if (const char *named = portablekit::env("METAL_PIPELINES"); named != nullptr)
        return *named == '\0' || std::strcmp(named, "0") == 0 ? std::string{} : std::string(named);
    std::vector<std::filesystem::path> candidates;
    if (NSString *resources = NSBundle.mainBundle.resourcePath; resources != nil)
        candidates.emplace_back(std::filesystem::path(resources.UTF8String) / "metal_pipelines.txt");
    if (NSString *executable = NSBundle.mainBundle.executablePath; executable != nil)
        candidates.emplace_back(std::filesystem::path(executable.UTF8String).parent_path() / "../../../config" /
                                "metal_pipelines.txt");
    candidates.emplace_back(std::filesystem::path("config") / "metal_pipelines.txt");
    for (const std::filesystem::path &candidate : candidates) {
        std::error_code ignored;
        if (std::filesystem::is_regular_file(candidate, ignored)) return candidate.lexically_normal().string();
    }
    return {};
}

// The depth-stencil states of the list made now (each a few microseconds), and its render pipelines asked of
// Metal asynchronously: they compile on Metal's threads while the game boots, and a draw takes each from
// prewarm_ on first use (render_pipeline()), waiting only for one not done yet.
void MetalGeBackend::start_prewarm() {
    const std::string path = find_pipeline_list();
    if (path.empty()) return;
    std::ifstream in(path);
    if (!in) {
        std::cout << "[metal] cannot read the pipeline list " << path << "; pipelines are made on first use\n";
        return;
    }
    const auto start = std::chrono::steady_clock::now();
    std::vector<RenderKey> renders;
    std::vector<DepthStencilKey> depths;
    std::uint32_t unread = 0u;
    std::string kind;
    std::map<std::string, unsigned> fields;
    for (std::string line; std::getline(in, line);) {
        if (!parse_key_line(line, kind, fields)) continue;
        RenderKey render;
        DepthStencilKey depth;
        if (kind == "render" && from_fields(fields, render)) renders.push_back(render);
        else if (kind == "depth" && from_fields(fields, depth)) depths.push_back(depth);
        else ++unread;
    }
    for (const DepthStencilKey &key : depths)
        if (depth_states_.find(key) == depth_states_.end()) depth_states_.emplace(key, make_depth_state(key));
    prewarm_ = std::make_shared<Prewarm>();
    prewarm_->started = start;
    {
        std::lock_guard<std::mutex> guard(prewarm_->lock);
        prewarm_->pending.insert(renders.begin(), renders.end());
        prewarm_->asked = static_cast<std::uint32_t>(prewarm_->pending.size());
    }
    for (const RenderKey &key : std::set<RenderKey>(renders.begin(), renders.end())) {
        const std::shared_ptr<Prewarm> shared = prewarm_;
        const RenderKey made = key;
        [device_ newRenderPipelineStateWithDescriptor:pipeline_descriptor(key)
                                    completionHandler:^(id<MTLRenderPipelineState> state, NSError *) {
                                        std::lock_guard<std::mutex> guard(shared->lock);
                                        if (state != nil) shared->ready[made] = state;
                                        else ++shared->failed;
                                        shared->pending.erase(made);
                                        if (shared->pending.empty())
                                            shared->done_ms = std::chrono::duration<double, std::milli>(
                                                                  std::chrono::steady_clock::now() - shared->started)
                                                                  .count();
                                        shared->changed.notify_all();
                                    }];
    }
    prewarm_path_ = path;
    prewarm_depth_states_ = depths.size();
    prewarm_start_ms_ = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
    std::cout << "[metal] pre-warm: " << prewarm_->asked << " render pipelines (made asynchronously) and "
              << depths.size() << " depth-stencil states from " << path << ", " << prewarm_start_ms_
              << " ms at start" << (unread != 0u ? " (" + std::to_string(unread) + " lines not read)" : "")
              << "\n";
}

// Once every pipeline the pre-warm asked for is made: how long that took.
void MetalGeBackend::report_prewarm_done() {
    std::lock_guard<std::mutex> guard(prewarm_->lock);
    if (!prewarm_->pending.empty()) return;
    prewarm_reported_ = true;
    std::cout << "[metal] pre-warm done: " << prewarm_->asked - prewarm_->failed << " render pipelines made in "
              << prewarm_->done_ms << " ms" << (prewarm_->failed != 0u ? ", " + std::to_string(prewarm_->failed) + " failed" : "")
              << " (frame " << frames_ << ")\n";
}

void MetalGeBackend::report_pipelines() {
    std::cout << "[metal] pipelines: " << render_pipelines_.size() << " render pipelines used, "
              << stats_.pipelines_made << " made by a draw";
    if (prewarm_) {
        std::cout << " (" << prewarm_waits_ << " of them waited for the pre-warm, " << prewarm_missed_
                  << " not in the list), " << prewarm_used_ << " taken from the pre-warm of " << prewarm_->asked;
    }
    std::cout << "; " << depth_states_.size() << " depth-stencil states, " << stats_.depth_states_made
              << " made by a draw" << (prewarm_ ? ", " + std::to_string(prewarm_depth_states_) + " pre-warmed" : "")
              << "\n";
}

// PURE_METAL_PIPELINES_OUT: every key the run's draws used, as config/metal_pipelines.txt holds them.
void MetalGeBackend::write_pipeline_list() {
    if (pipelines_out_.empty()) return;
    std::error_code ignored;
    const std::filesystem::path file(pipelines_out_);
    if (file.has_parent_path()) std::filesystem::create_directories(file.parent_path(), ignored);
    std::ofstream out(pipelines_out_);
    if (!out) {
        std::cout << "[metal] cannot write the pipeline list to " << pipelines_out_ << "\n";
        return;
    }
    out << "# The Metal backend's render pipelines and depth-stencil states made at start (task 033,\n"
           "# docs/metal-backend.md \"Frame times\"): written by PURE_METAL_PIPELINES_OUT=FILE, every key a run's\n"
           "# draws used. A key not listed is still made on first use.\n";
    for (const RenderKey &key : render_seen_) out << to_text(key) << "\n";
    for (const DepthStencilKey &key : depth_seen_) out << to_text(key) << "\n";
    std::cout << "[metal] " << render_seen_.size() << " render pipeline keys and " << depth_seen_.size()
              << " depth-stencil keys -> " << pipelines_out_ << "\n";
}

} // namespace pure::gpu::metal_backend
