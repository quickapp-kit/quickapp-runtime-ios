#pragma once

#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>

#include "quickapp/core/event/event_router.h"
#include "quickapp/ios/platform_adapter.h"

namespace quickapp::ios {

struct RuntimeSpineSnapshot final {
  std::size_t surfaces{0};
  std::size_t nodes{0};
  std::size_t handlers{0};
  std::size_t pending_callbacks{0};
  std::size_t js_resources{0};
  std::size_t core_queue_depth{0};
};

class RuntimeSpine final : public std::enable_shared_from_this<RuntimeSpine> {
 public:
  static std::shared_ptr<RuntimeSpine> create(
      std::shared_ptr<platform::Gateway> gateway, double viewport_width,
      double viewport_height) noexcept;
  ~RuntimeSpine();

  RuntimeSpine(const RuntimeSpine&) = delete;
  RuntimeSpine& operator=(const RuntimeSpine&) = delete;

  void start(std::string rpk_path) noexcept;
  [[nodiscard]] bool dispatchClick(std::string surface_id, std::string node_id,
                                   std::uint64_t timestamp_ns) noexcept;
  [[nodiscard]] bool dispatchInput(
      std::string surface_id, std::string node_id,
      core::package::EventType event_type,
      core::RuntimeValue::Object payload,
      std::uint64_t timestamp_ns) noexcept;
  [[nodiscard]] bool dispatchFeature(std::string module, std::string method,
                                     std::string value = {}) noexcept;
  void acceptSurfaceResult(std::string request_id, int kind,
                           std::string target_surface_id,
                           std::optional<std::string> source_surface_id,
                           std::optional<std::string> reveal_surface_id,
                           int visibility, bool completed,
                           std::optional<std::string> error_code,
                           std::optional<std::string> error_message) noexcept;
  void acceptMountResult(std::string surface_id, std::uint64_t revision,
                         std::string mount_attempt_id, std::string source_id,
                         bool mounted,
                         std::optional<std::string> error_code,
                         std::optional<std::string> error_message) noexcept;
  void destroy() noexcept;
  [[nodiscard]] RuntimeSpineSnapshot snapshot() const noexcept;

 private:
  struct Impl;
  explicit RuntimeSpine(std::unique_ptr<Impl> impl) noexcept;
  std::unique_ptr<Impl> impl_;
};

}  // namespace quickapp::ios
