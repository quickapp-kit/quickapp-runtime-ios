#include "quickapp/ios/platform_adapter.h"

#include <algorithm>
#include <cmath>
#include <string_view>
#include <type_traits>


namespace quickapp::ios::platform {
namespace {

void iosMountStage(const core::render::MountTransaction&) noexcept {
}

core::EnqueueResult accepted(bool value, std::string_view message) noexcept {
  if (value) return core::EnqueueResult::success(core::Accepted{});
  return core::EnqueueResult::failure(platformError(message));
}

std::size_t utf8CodePoints(std::string_view text) noexcept {
  std::size_t count = 0;
  for (unsigned char byte : text) {
    if ((byte & 0xC0U) != 0x80U) ++count;
  }
  return count;
}

double constrain(double natural,
                 const core::render::MeasureConstraint& constraint) noexcept {
  using Kind = core::render::MeasureConstraintKind;
  if (constraint.kind == Kind::kExactly) return constraint.value;
  if (constraint.kind == Kind::kAtMost) return std::min(natural, constraint.value);
  return natural;
}

}  // namespace

core::RuntimeError platformError(std::string_view message,
                                 bool retryable) noexcept {
  return core::RuntimeError::simple(core::RuntimeErrorCode::kPlatformRejected,
                                    message, retryable);
}

core::EnqueueResult SurfacePort::post(
    core::surface::SurfaceCommand&& command) noexcept {
  if (!accepting_.load(std::memory_order_acquire)) {
    return core::EnqueueResult::failure(platformError("iOS Surface port is closed"));
  }
  return std::visit(
      [this](const auto& value) -> core::EnqueueResult {
        using Value = std::decay_t<decltype(value)>;
        if constexpr (std::is_same_v<Value,
                                     core::surface::SurfaceCreateHostCommand>) {
          return accepted(gateway_.postCreateSurface(value),
                          "iOS rejected CreateSurfaceHost");
        } else if constexpr (std::is_same_v<
                                 Value, core::surface::SurfacePresentCommand>) {
          const bool posted = gateway_.postPresentSurface(value);
          return accepted(posted,
                          "iOS rejected PresentSurfaceHost");
        } else if constexpr (std::is_same_v<
                                 Value, core::surface::SurfaceVisibilityCommand>) {
          return accepted(gateway_.postVisibility(value),
                          "iOS rejected SetSurfaceVisibility");
        } else if constexpr (std::is_same_v<Value,
                                             core::surface::SurfaceCloseCommand>) {
          return accepted(gateway_.postCloseSurface(value),
                          "iOS rejected CloseSurfaceHost");
        } else {
          return accepted(gateway_.postDestroySurface(value),
                          "iOS rejected DestroySurfaceHost");
        }
      },
      command);
}

core::EnqueueResult MountPort::post(
    core::render::MountTransaction&& transaction) noexcept {
  if (!accepting_.load(std::memory_order_acquire)) {
    return core::EnqueueResult::failure(platformError("iOS Mount port is closed"));
  }
  iosMountStage(transaction);
  return accepted(gateway_.postMount(transaction),
                  "iOS rejected MountTransaction");
}

core::render::MeasureResult MeasurePort::measure(
    const core::render::MeasureRequest& request) noexcept {
  auto failed = [&request](std::string_view message) {
    return core::render::MeasureResult{
        request.request_id, request.surface_id, request.node_id,
        request.content_revision, request.platform_font_generation, false, 0, 0,
        platformError(message)};
  };
  if (request.platform_font_generation == 0 || request.font_token != "system-default" ||
      request.font_size <= 0 || !std::isfinite(request.font_size) ||
      request.font_weight == 0 || request.font_weight > 1000) {
    return failed("iOS immutable font metrics rejected MeasureRequest");
  }
  const std::size_t code_points = utf8CodePoints(request.text);
  if (code_points > 65536) return failed("iOS MeasureRequest text limit exceeded");

  // A1 uses immutable, deterministic sans-serif metrics on the Core thread.
  // No iOS View or UI-thread measurement participates in this result.
  const double glyph_advance = request.font_size * 0.56;
  const double natural_width = glyph_advance * static_cast<double>(code_points);
  const double line_height = request.font_size * 1.25;
  double width = constrain(natural_width, request.width_constraint);
  double height = line_height;
  if (request.width_constraint.kind !=
          core::render::MeasureConstraintKind::kUnconstrained &&
      request.width_constraint.value > 0 && natural_width > request.width_constraint.value) {
    const double lines = std::ceil(natural_width / request.width_constraint.value);
    height = line_height * lines;
  }
  height = constrain(height, request.height_constraint);
  return {request.request_id,
          request.surface_id,
          request.node_id,
          request.content_revision,
          request.platform_font_generation,
          true,
          width,
          height,
          std::nullopt};
}

}  // namespace quickapp::ios::platform
