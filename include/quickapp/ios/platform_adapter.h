#pragma once

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <optional>
#include <string>

#include "quickapp/core/event/event_router.h"
#include "quickapp/core/render/initial_render_pipeline.h"
#include "quickapp/core/surface/surface_controller.h"

namespace quickapp::ios::platform {

class Gateway {
 public:
  virtual ~Gateway() = default;

  virtual bool postCreateSurface(const core::surface::SurfaceCreateHostCommand& command) noexcept = 0;
  virtual bool postPresentSurface(const core::surface::SurfacePresentCommand& command) noexcept = 0;
  virtual bool postVisibility(const core::surface::SurfaceVisibilityCommand& command) noexcept = 0;
  virtual bool postCloseSurface(const core::surface::SurfaceCloseCommand& command) noexcept = 0;
  virtual bool postDestroySurface(const core::surface::SurfaceDestroyCommand& command) noexcept = 0;
  virtual bool postMount(const core::render::MountTransaction& transaction) noexcept = 0;

  virtual void notifyStarted(std::string_view surface_id) noexcept = 0;
  virtual void notifyFailed(std::string_view code, std::string_view message) noexcept = 0;
  virtual void notifyStopped(std::size_t surfaces, std::size_t nodes,
                             std::size_t handlers,
                             std::size_t pending_callbacks,
                             std::size_t js_resources,
                             std::size_t core_queue_depth) noexcept = 0;
  virtual std::size_t pendingCallbacks() const noexcept = 0;
  virtual void close() noexcept = 0;
};

class SurfacePort final : public core::surface::SurfacePlatformPort {
 public:
  explicit SurfacePort(Gateway& gateway) noexcept : gateway_(gateway) {}

  core::EnqueueResult post(core::surface::SurfaceCommand&& command) noexcept override;
  void close() noexcept override { accepting_.store(false, std::memory_order_release); }

 private:
  Gateway& gateway_;
  std::atomic<bool> accepting_{true};
};

class MountPort final : public core::render::MountPort {
 public:
  explicit MountPort(Gateway& gateway) noexcept : gateway_(gateway) {}

  core::EnqueueResult post(core::render::MountTransaction&& transaction) noexcept override;
  void close() noexcept override { accepting_.store(false, std::memory_order_release); }

 private:
  Gateway& gateway_;
  std::atomic<bool> accepting_{true};
};

class MeasurePort final : public core::render::MeasurePort {
 public:
  core::render::MeasureResult measure(
      const core::render::MeasureRequest& request) noexcept override;
};

[[nodiscard]] core::RuntimeError platformError(
    std::string_view message, bool retryable = false) noexcept;

}  // namespace quickapp::ios::platform
