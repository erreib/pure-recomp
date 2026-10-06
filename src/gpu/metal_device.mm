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

struct Trace {
    std::mutex lock;
    std::atomic<std::uint64_t> flip{};
    ShellPresents presents;
    std::map<std::uint64_t, std::pair<double, double>> presented;  // flip -> (presented time, latency)
};

Trace &trace() {
    static Trace value;
    return value;
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

void trace_shell_present(double cpu_ms, double drawable_ms) {
    Trace &t = trace();
    std::lock_guard<std::mutex> guard(t.lock);
    t.presents.cpu_ms += cpu_ms;
    t.presents.drawable_ms += drawable_ms;
    ++t.presents.count;
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
