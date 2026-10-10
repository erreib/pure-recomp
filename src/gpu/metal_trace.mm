// The Metal backend's frame trace and counts (docs/metal-backend.md, "Frame times"): PURE_METAL_TRACE's CSV row per
// flip, each written once the Metal shell has said when its picture reached the screen (metal_device.hpp's hook);
// the line printed every 600 frames, and the exit lines of the stencil, guest memory, the colour test, 16-bit
// targets and the depth clamp.
#include "metal_backend.hpp"
#include "metal_device.hpp"

#include <chrono>
#include <cstdio>
#include <filesystem>
#include <iostream>
#include <system_error>
#include <utility>

namespace pure::gpu::metal_backend {
namespace {

constexpr const char *kTraceHeader =
    "flip,t_ms,frame_ms,submit_ms,pipeline_ms,texture_ms,present_ms,memory_ms,wait_ms,wait_depth_ms,"
    "wait_frame_ms,wait_guest_ms,wait_capture_ms,wait_ring_ms,pipelines,depth_states,decoded,decoded_kb,"
    "stencil_copies,draws,passes,copies,shell_ms,drawable_ms,occluded,shown_ms,latency_ms,other_ms";
// How many flips a row waits for the shell to say when its picture reached the screen.
constexpr std::uint64_t kTraceDelay = 30u;

} // namespace

// The internal scale (D-015), for the start-up line: `internal scale 4: targets 1920x1088, effects 480x272`, the
// screen-wide targets' size and the narrower ones' (the bloom's and the billboards'). Part of the line that opens with
// "drawing with", which tools/refactor_check.sh leaves out of the counts it compares. `changed`: the line of a change
// from the menu (task 067), `internal scale now 1: ...`, printed only when the scale changes.
std::string MetalGeBackend::scale_report(bool changed) const {
    return std::string("internal scale ") + (changed ? "now " : "") + std::to_string(scale_) + ": targets " +
           std::to_string(kWidth * scale_) + "x" + std::to_string(kHeight * scale_) + ", effects " +
           std::to_string(kWidth) + "x" + std::to_string(kHeight);
}

void MetalGeBackend::open_trace(const char *path) {
    std::error_code ignored;
    const std::filesystem::path file(path);
    if (file.has_parent_path()) std::filesystem::create_directories(file.parent_path(), ignored);
    trace_.file = std::fopen(path, "w");
    if (trace_.file == nullptr) {
        std::cout << "[metal] cannot write the frame trace to " << path << "\n";
        return;
    }
    trace_.path = path;
    std::fprintf(trace_.file, "%s\n", kTraceHeader);
    trace_.stats = stats_;
    trace_.times = FrameTimes{};
    std::cout << "[metal] frame trace: a row per flip -> " << path << "\n";
}

// At a flip: the row of the interval since the previous flip, and the rows whose pictures the shell has
// reported on written out.
void MetalGeBackend::end_trace_interval() {
    const auto now = std::chrono::steady_clock::now();
    TraceRow row;
    row.flip = frames_ + 1u;
    row.t_ms = std::chrono::duration<double, std::milli>(now - trace_.started).count();
    row.frame_ms =
        std::chrono::duration<double, std::milli>(now - (trace_.has_flip ? trace_.last_flip : trace_.started)).count();
    trace_.last_flip = now;
    trace_.has_flip = true;
    row.times = std::exchange(trace_.times, FrameTimes{});
    row.counts = since(trace_.stats);
    trace_.stats = stats_;
    const pure::metal::ShellPresents shell = pure::metal::take_shell_presents();
    row.shell_ms = shell.cpu_ms;
    row.drawable_ms = shell.drawable_ms;
    row.shell_presents = shell.count;
    row.occluded = shell.occluded;
    if (shell.count != 0u) trace_.shell_seen = true;
    trace_.pending_rows.push_back(row);
    flush_trace(false);
}

// The counts of stats_ since `before`.
Stats MetalGeBackend::since(const Stats &before) const {
    Stats d;
    d.draws = stats_.draws - before.draws;
    d.passes = stats_.passes - before.passes;
    d.decoded = stats_.decoded - before.decoded;
    d.decoded_bytes = stats_.decoded_bytes - before.decoded_bytes;
    d.copies = stats_.copies - before.copies;
    d.stencil_copies = stats_.stencil_copies - before.stencil_copies;
    d.pipelines_made = stats_.pipelines_made - before.pipelines_made;
    d.depth_states_made = stats_.depth_states_made - before.depth_states_made;
    return d;
}

// Writes the rows in order, each once the shell has reported when its picture reached the screen (under the
// Metal shell; at once under any other), or kTraceDelay flips later, or with `all` at the end.
void MetalGeBackend::flush_trace(bool all) {
    while (!trace_.pending_rows.empty()) {
        const TraceRow &row = trace_.pending_rows.front();
        double presented_s = 0.0, latency_ms = 0.0;
        const bool known = pure::metal::take_presented(row.flip, presented_s, latency_ms);
        if (!known && trace_.shell_seen && !all && frames_ + 1u - row.flip < kTraceDelay) break;
        write_trace_row(row, known, presented_s, latency_ms);
        trace_.pending_rows.pop_front();
    }
}

// `known`: the shell reported on the flip's picture; it reached the screen at presented_s, or never (0).
void MetalGeBackend::write_trace_row(const TraceRow &row, bool known, double presented_s, double latency_ms) {
    const FrameTimes &t = row.times;
    const Stats &c = row.counts;
    const double waits = t.wait_depth + t.wait_frame + t.wait_guest + t.wait_capture + t.wait_ring;
    const double other = row.frame_ms - t.submit - t.present - t.memory - row.shell_ms;
    std::fprintf(trace_.file,
                 "%llu,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%llu,%llu,%llu,%.1f,%llu,"
                 "%llu,%llu,%llu,",
                 static_cast<unsigned long long>(row.flip), row.t_ms, row.frame_ms, t.submit, t.pipeline, t.texture,
                 t.present, t.memory, waits, t.wait_depth, t.wait_frame, t.wait_guest, t.wait_capture, t.wait_ring,
                 static_cast<unsigned long long>(c.pipelines_made), static_cast<unsigned long long>(c.depth_states_made),
                 static_cast<unsigned long long>(c.decoded), static_cast<double>(c.decoded_bytes) / 1024.0,
                 static_cast<unsigned long long>(c.stencil_copies), static_cast<unsigned long long>(c.draws),
                 static_cast<unsigned long long>(c.passes), static_cast<unsigned long long>(c.copies));
    // The shell's columns are empty where no Metal shell presents.
    if (trace_.shell_seen) std::fprintf(trace_.file, "%.3f,%.3f,%u,", row.shell_ms, row.drawable_ms, row.occluded);
    else std::fprintf(trace_.file, ",,,");
    // shown_ms: since the last picture that reached the screen, 0 for one that never did, empty when unknown.
    const bool presented = known && presented_s > 0.0;
    if (presented && trace_.last_presented_s > 0.0)
        std::fprintf(trace_.file, "%.3f,", (presented_s - trace_.last_presented_s) * 1000.0);
    else if (known && !presented)
        std::fprintf(trace_.file, "0,");
    else std::fprintf(trace_.file, ",");
    if (presented) {
        std::fprintf(trace_.file, "%.3f,", latency_ms);
        trace_.last_presented_s = presented_s;
        ++trace_.shown;
    } else {
        std::fprintf(trace_.file, ",");
        if (known) ++trace_.not_shown;
    }
    std::fprintf(trace_.file, "%.3f\n", other);
    if (++trace_.rows % 60u == 0u) std::fflush(trace_.file);
}

void MetalGeBackend::close_trace() {
    if (trace_.file == nullptr) return;
    flush_trace(true);
    std::fclose(trace_.file);
    trace_.file = nullptr;
    std::cout << "[metal] frame trace: " << trace_.rows << " rows -> " << trace_.path;
    if (trace_.shell_seen)
        std::cout << "; the shell's pictures: " << trace_.shown << " reached the screen, " << trace_.not_shown
                  << " never did, " << trace_.rows - trace_.shown - trace_.not_shown << " not reported";
    std::cout << "\n";
}

void MetalGeBackend::report() {
    const auto now = std::chrono::steady_clock::now();
    const double seconds = std::chrono::duration<double>(now - trace_.report_start).count();
    const std::uint64_t frames = frames_ - trace_.report_frames;
    std::cout << "[metal] frame " << frames_ << ", " << stats_.draws << " draws ("
              << (stats_.draws - trace_.report_draws) << " in the last " << frames << " frames, "
              << (seconds > 0.0 ? static_cast<double>(frames) / seconds : 0.0) << " fps), " << targets_.size()
              << " targets, " << textures_.size() << " textures cached, " << stats_.decoded << " decoded\n";
    trace_.report_start = now;
    trace_.report_frames = frames_;
    trace_.report_draws = stats_.draws;
}

void MetalGeBackend::report_guest_writes() {
    const auto line = [](const char *what, const GuestWrites &writes) {
        std::cout << " " << what << " " << writes.written << "/" << writes.calls << " (" << writes.wait_ms
                  << " ms waited)";
    };
    std::cout << "[metal] stencil: " << stats_.stencil_draws << " draws, " << stats_.stencil_copies
              << " copies into the alpha; guest memory written/asked:";
    line("transfers", stats_.transfers);
    line("read-backs", stats_.read_backs);
    line("frames", stats_.frames);
    line("depths", stats_.depths);
    std::cout << "\n";
    std::cout << "[metal] colour test: " << stats_.color_tested << " draws; 16-bit targets: " << stats_.sixteen_bit
              << " draws (" << stats_.dithered << " dithered); depth clamp: " << stats_.depth_clamped
              << " draws\n";
}

} // namespace pure::gpu::metal_backend
