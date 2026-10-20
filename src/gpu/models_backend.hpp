// The models backend (task 102, D-025; docs/ge-backend.md, "The models backend"): PURE_GE_BACKEND=models, the default
// since task 102 (src/host/pure_main.cpp). It wraps the backend PURE_GE_MODELS_INNER names (the platform's: metal on
// macOS, vulkan under the Vulkan shell and elsewhere) and hands it every call unchanged, except, with the Video tab's
// Crowds and people row at Models, the draws of a figure's texture that models/models.ini maps to a model: each quad
// of such a draw is drawn as that model instead (models_backend.cpp says how).
//
// What looks for the inner backend's own interfaces through the running backend asks it for inner(): the Metal shell
// finds the Metal backend's texture pack host that way (src/host/metal_shell.mm).
#pragma once

#include "gpu/ge_backend.hpp"

namespace pure::models {

// A backend that draws through another one.
class WrappingBackend : public portablekit::gpu::GeBackend {
public:
    // The backend it hands its calls to; never null once made.
    [[nodiscard]] virtual portablekit::gpu::GeBackend *inner() const noexcept = 0;
};

} // namespace pure::models
