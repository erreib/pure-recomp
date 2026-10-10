// The one Metal device and command queue of the program (metal_device.hpp), and the frame trace's hook between the
// backend and the shell (task 033).
#include "metal_device.hpp"

#include "profile.hpp"

#include <atomic>
#include <map>
#include <mutex>
#include <utility>

namespace pure::metal {

id<MTLDevice> device() {
    static id<MTLDevice> const shared = MTLCreateSystemDefaultDevice();
    return shared;
}

id<MTLCommandQueue> queue() {
    static id<MTLCommandQueue> const shared = [device() newCommandQueue];
    return shared;
}

namespace {

std::atomic<std::uint32_t> drawable_width{};
std::atomic<std::uint32_t> drawable_height{};

} // namespace

void set_drawable_size(std::uint32_t width, std::uint32_t height) {
    drawable_width.store(width, std::memory_order_relaxed);
    drawable_height.store(height, std::memory_order_relaxed);
}

void drawable_size(std::uint32_t &width, std::uint32_t &height) {
    width = drawable_width.load(std::memory_order_relaxed);
    height = drawable_height.load(std::memory_order_relaxed);
}

namespace {

struct Trace {
    std::mutex lock;
    std::atomic<std::uint64_t> flip{};
    ShellPresents presents;
    std::map<std::uint64_t, std::pair<double, double>> presented;  // flip -> (presented time, latency)
};

// Never destroyed: the backend's shutdown, which writes the trace's last rows, can run during the program's exit after
// a function-local static made later than its owner would already be gone, and the drawables' presented handlers
// may still run on Metal's threads then.
Trace &trace() {
    static Trace *const value = new Trace;
    return *value;
}

} // namespace

bool trace_on() {
    static const bool on = [] {
        const char *path = portablekit::env("METAL_TRACE");
        return path != nullptr && *path != '\0';
    }();
    return on;
}

void trace_flip(std::uint64_t flip) { trace().flip.store(flip, std::memory_order_relaxed); }

std::uint64_t trace_current_flip() { return trace().flip.load(std::memory_order_relaxed); }

void trace_shell_present(double cpu_ms, double drawable_ms, bool occluded) {
    Trace &t = trace();
    std::lock_guard<std::mutex> guard(t.lock);
    t.presents.cpu_ms += cpu_ms;
    t.presents.drawable_ms += drawable_ms;
    ++t.presents.count;
    if (occluded) ++t.presents.occluded;
}

void trace_presented(std::uint64_t flip, double presented_s, double latency_ms) {
    Trace &t = trace();
    std::lock_guard<std::mutex> guard(t.lock);
    // The backend takes each flip's entry within a few flips; a bound keeps one it gave up on from piling up.
    if (t.presented.size() > 4096u) t.presented.erase(t.presented.begin());
    t.presented[flip] = {presented_s, latency_ms};
}

ShellPresents take_shell_presents() {
    Trace &t = trace();
    std::lock_guard<std::mutex> guard(t.lock);
    return std::exchange(t.presents, ShellPresents{});
}

bool take_presented(std::uint64_t flip, double &presented_s, double &latency_ms) {
    Trace &t = trace();
    std::lock_guard<std::mutex> guard(t.lock);
    const auto found = t.presented.find(flip);
    if (found == t.presented.end()) return false;
    presented_s = found->second.first;
    latency_ms = found->second.second;
    t.presented.erase(found);
    return true;
}

} // namespace pure::metal
