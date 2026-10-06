// The one Metal device and command queue of the program (metal_device.hpp).
#include "metal_device.hpp"

namespace pure::metal {

id<MTLDevice> device() {
    static id<MTLDevice> const shared = MTLCreateSystemDefaultDevice();
    return shared;
}

id<MTLCommandQueue> queue() {
    static id<MTLCommandQueue> const shared = [device() newCommandQueue];
    return shared;
}

} // namespace pure::metal
