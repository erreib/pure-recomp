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

void MetalGeBackend::open_trace(const char *path) {
    std::error_code ignored;
    const std::filesystem::path file(path);
    if (file.has_parent_path()) std::filesystem::create_directories(file.parent_path(), ignored);
    trace_file_ = std::fopen(path, "w");
    if (trace_file_ == nullptr) {
        std::cout << "[metal] cannot write the frame trace to " << path << "\n";
        return;
    }
    trace_path_ = path;
    std::fprintf(trace_file_, "%s\n", kTraceHeader);
    trace_stats_ = stats_;
    times_ = FrameTimes{};
    std::cout << "[metal] frame trace: a row per flip -> " << path << "\n";
}

// At a flip: the row of the interval since the previous flip, and the rows whose pictures the shell has
// reported on written out.
void MetalGeBackend::end_trace_interval() {
    const auto now = std::chrono::steady_clock::now();
    TraceRow row;
    row.flip = frames_ + 1u;
    row.t_ms = std::chrono::duration<double, std::milli>(now - started_).count();
    row.frame_ms = std::chrono::duration<double, std::milli>(now - (trace_has_flip_ ? trace_last_flip_ : started_)).count();
    trace_last_flip_ = now;
    trace_has_flip_ = true;
    row.times = std::exchange(times_, FrameTimes{});
    row.counts = since(trace_stats_);
    trace_stats_ = stats_;
    const pure::metal::ShellPresents shell = pure::metal::take_shell_presents();
    row.shell_ms = shell.cpu_ms;
    row.drawable_ms = shell.drawable_ms;
    row.shell_presents = shell.count;
    row.occluded = shell.occluded;
    if (shell.count != 0u) shell_seen_ = true;
    pending_rows_.push_back(row);
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
    while (!pending_rows_.empty()) {
        const TraceRow &row = pending_rows_.front();
        double presented_s = 0.0, latency_ms = 0.0;
        const bool known = pure::metal::take_presented(row.flip, presented_s, latency_ms);
        if (!known && shell_seen_ && !all && frames_ + 1u - row.flip < kTraceDelay) break;
        write_trace_row(row, known, presented_s, latency_ms);
        pending_rows_.pop_front();
    }
}

// `known`: the shell reported on the flip's picture; it reached the screen at presented_s, or never (0).
void MetalGeBackend::write_trace_row(const TraceRow &row, bool known, double presented_s, double latency_ms) {
    const FrameTimes &t = row.times;
    const Stats &c = row.counts;
    const double waits = t.wait_depth + t.wait_frame + t.wait_guest + t.wait_capture + t.wait_ring;
    const double other = row.frame_ms - t.submit - t.present - t.memory - row.shell_ms;
    std::fprintf(trace_file_,
                 "%llu,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%llu,%llu,%llu,%.1f,%llu,"
                 "%llu,%llu,%llu,",
                 static_cast<unsigned long long>(row.flip), row.t_ms, row.frame_ms, t.submit, t.pipeline, t.texture,
                 t.present, t.memory, waits, t.wait_depth, t.wait_frame, t.wait_guest, t.wait_capture, t.wait_ring,
                 static_cast<unsigned long long>(c.pipelines_made), static_cast<unsigned long long>(c.depth_states_made),
                 static_cast<unsigned long long>(c.decoded), static_cast<double>(c.decoded_bytes) / 1024.0,
                 static_cast<unsigned long long>(c.stencil_copies), static_cast<unsigned long long>(c.draws),
                 static_cast<unsigned long long>(c.passes), static_cast<unsigned long long>(c.copies));
    // The shell's columns are empty where no Metal shell presents.
    if (shell_seen_) std::fprintf(trace_file_, "%.3f,%.3f,%u,", row.shell_ms, row.drawable_ms, row.occluded);
    else std::fprintf(trace_file_, ",,,");
    // shown_ms: since the last picture that reached the screen, 0 for one that never did, empty when unknown.
    const bool presented = known && presented_s > 0.0;
    if (presented && last_presented_s_ > 0.0)
        std::fprintf(trace_file_, "%.3f,", (presented_s - last_presented_s_) * 1000.0);
    else if (known && !presented)
        std::fprintf(trace_file_, "0,");
    else std::fprintf(trace_file_, ",");
    if (presented) {
        std::fprintf(trace_file_, "%.3f,", latency_ms);
        last_presented_s_ = presented_s;
        ++trace_shown_;
    } else {
        std::fprintf(trace_file_, ",");
        if (known) ++trace_not_shown_;
    }
    std::fprintf(trace_file_, "%.3f\n", other);
    if (++trace_rows_ % 60u == 0u) std::fflush(trace_file_);
}

void MetalGeBackend::close_trace() {
    if (trace_file_ == nullptr) return;
    flush_trace(true);
    std::fclose(trace_file_);
    trace_file_ = nullptr;
    std::cout << "[metal] frame trace: " << trace_rows_ << " rows -> " << trace_path_;
    if (shell_seen_)
        std::cout << "; the shell's pictures: " << trace_shown_ << " reached the screen, " << trace_not_shown_
                  << " never did, " << trace_rows_ - trace_shown_ - trace_not_shown_ << " not reported";
    std::cout << "\n";
}

void MetalGeBackend::report() {
    const auto now = std::chrono::steady_clock::now();
    const double seconds = std::chrono::duration<double>(now - report_start_).count();
    const std::uint64_t frames = frames_ - report_frames_;
    std::cout << "[metal] frame " << frames_ << ", " << stats_.draws << " draws ("
              << (stats_.draws - report_draws_) << " in the last " << frames << " frames, "
              << (seconds > 0.0 ? static_cast<double>(frames) / seconds : 0.0) << " fps), " << targets_.size()
              << " targets, " << textures_.size() << " textures cached, " << stats_.decoded << " decoded\n";
    report_start_ = now;
    report_frames_ = frames_;
    report_draws_ = stats_.draws;
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
