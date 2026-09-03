#include "quickapp/ios/runtime_spine.h"

#include <chrono>
#include <cstdio>
#include <memory>
#include <optional>
#include <string>
#include <thread>
#include <type_traits>
#include <variant>

namespace quickapp::ios {
namespace {

class ProbeGateway final : public platform::Gateway {
 public:
  void bind(std::shared_ptr<RuntimeSpine> spine) { spine_ = std::move(spine); }

  bool postCreateSurface(const core::surface::SurfaceCreateHostCommand &command) noexcept override {
    if (auto spine = spine_.lock()) {
      spine->acceptSurfaceResult(command.request_id.wire(), 0, command.surface_id.wire(),
                                 std::nullopt, std::nullopt, 0, true, std::nullopt, std::nullopt);
      return true;
    }
    return false;
  }

  bool postPresentSurface(const core::surface::SurfacePresentCommand &command) noexcept override {
    if (auto spine = spine_.lock()) {
      spine->acceptSurfaceResult(
          command.request_id.wire(), 1, command.target.wire(),
          command.source ? std::optional<std::string>(command.source->wire()) : std::nullopt,
          std::nullopt, 1, true, std::nullopt, std::nullopt);
      return true;
    }
    return false;
  }

  bool postVisibility(const core::surface::SurfaceVisibilityCommand &command) noexcept override {
    if (auto spine = spine_.lock()) {
      spine->acceptSurfaceResult(command.request_id.wire(), 2, command.surface_id.wire(),
                                 std::nullopt, std::nullopt, 1, true, std::nullopt, std::nullopt);
      return true;
    }
    return false;
  }

  bool postCloseSurface(const core::surface::SurfaceCloseCommand &command) noexcept override {
    if (auto spine = spine_.lock()) {
      spine->acceptSurfaceResult(command.request_id.wire(), 3, command.source.wire(),
                                 command.source.wire(), command.reveal.wire(), 1, true,
                                 std::nullopt, std::nullopt);
      return true;
    }
    return false;
  }

  bool postDestroySurface(const core::surface::SurfaceDestroyCommand &command) noexcept override {
    if (auto spine = spine_.lock()) {
      spine->acceptSurfaceResult(command.request_id.wire(), 4, command.surface_id.wire(),
                                 std::nullopt, std::nullopt, 0, true, std::nullopt, std::nullopt);
      return true;
    }
    return false;
  }

  bool postMount(const core::render::MountTransaction &transaction) noexcept override {
    std::printf("ios.probe.mount surface=%s revision=%llu operations=%zu mode=%d\n",
                transaction.surface_id.wire().c_str(),
                static_cast<unsigned long long>(transaction.revision),
                transaction.operations.size(), static_cast<int>(transaction.mode));
    for (const auto &operation : transaction.operations) {
        std::visit([](const auto &value) {
          using Value = std::decay_t<decltype(value)>;
          if constexpr (std::is_same_v<Value, core::render::SetHostProp>) {
            std::printf("ios.probe.mount.op=SetHostProp node=%s name=%s\n",
                        value.node_id.wire().c_str(), value.name.c_str());
          } else if constexpr (std::is_same_v<Value, core::render::CreateHost>) {
            std::printf("ios.probe.mount.op=CreateHost node=%s\n",
                        value.node_id.wire().c_str());
          } else if constexpr (std::is_same_v<Value, core::render::SetHostLayout>) {
            std::printf("ios.probe.mount.op=SetHostLayout node=%s rect=<%.1f,%.1f,%.1f,%.1f>\n",
                        value.node_id.wire().c_str(), value.rect.x, value.rect.y,
                        value.rect.width, value.rect.height);
          } else if constexpr (std::is_same_v<Value, core::render::InsertHostChild>) {
            std::printf("ios.probe.mount.op=InsertHostChild node=%s parent=%s\n",
                        value.node_id.wire().c_str(), value.parent_node_id.wire().c_str());
          } else if constexpr (std::is_same_v<Value, core::render::RemoveHost>) {
            std::printf("ios.probe.mount.op=RemoveHost node=%s\n",
                        value.node_id.wire().c_str());
          } else if constexpr (std::is_same_v<Value, core::render::MoveHost>) {
            std::printf("ios.probe.mount.op=MoveHost node=%s parent=%s\n",
                        value.node_id.wire().c_str(), value.new_parent_node_id.wire().c_str());
          }
        }, operation);
    }
    if (auto spine = spine_.lock()) {
      spine->acceptMountResult(transaction.surface_id.wire(), transaction.revision,
                                transaction.mount_attempt_id.wire(),
                                core::render::render_source_wire(transaction.source_id), true,
                                std::nullopt, std::nullopt);
      return true;
    }
    return false;
  }

  void notifyStarted(std::string_view surface_id) noexcept override {
    std::printf("ios.probe.runtime.started surface=%.*s\n",
                static_cast<int>(surface_id.size()), surface_id.data());
  }

  void notifyFailed(std::string_view code, std::string_view message) noexcept override {
    std::printf("ios.probe.runtime.failed code=%.*s message=%.*s\n",
                static_cast<int>(code.size()), code.data(), static_cast<int>(message.size()),
                message.data());
  }

  void notifyStopped(std::size_t surfaces, std::size_t nodes, std::size_t handlers,
                     std::size_t pending_callbacks, std::size_t js_resources,
                     std::size_t core_queue_depth) noexcept override {
    std::printf("ios.probe.runtime.stopped surfaces=%zu nodes=%zu handlers=%zu pendingCallbacks=%zu jsResources=%zu coreQueue=%zu\n",
                surfaces, nodes, handlers, pending_callbacks, js_resources, core_queue_depth);
  }

  std::size_t pendingCallbacks() const noexcept override { return 0; }
  void close() noexcept override { spine_.reset(); }

 private:
  std::weak_ptr<RuntimeSpine> spine_;
};

}  // namespace
}  // namespace quickapp::ios

int main(int argc, char **argv) {
  const std::string rpk = argc > 1 ? argv[1] : "../quickapp-toolkit/evidence/tk-s12-lvgl-p0.rpk";
  const std::string click_node = argc > 2 ? argv[2] : "";
  const std::string event_name = argc > 3 ? argv[3] : "click";
  const std::string feature_module = argc > 4 ? argv[4] : "";
  const std::string feature_method = argc > 5 ? argv[5] : "";
  const std::string feature_value = argc > 6 ? argv[6] : "";
  const std::string back_node = argc > 7
      ? argv[7]
      : (rpk.find("list-001") != std::string::npos ? "node:10" : "node:4");
  auto gateway = std::make_shared<quickapp::ios::ProbeGateway>();
  auto spine = quickapp::ios::RuntimeSpine::create(gateway, 390.0, 844.0);
  if (!spine) return 2;
  gateway->bind(spine);
  spine->start(rpk);
  for (int i = 0; i < 500; ++i) {
    const auto snapshot = spine->snapshot();
    if (snapshot.surfaces >= 1 && snapshot.nodes >= 3 && snapshot.handlers >= 1) break;
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
  }
  auto before = spine->snapshot();
  std::printf("ios.probe.first surfaces=%zu nodes=%zu handlers=%zu jsResources=%zu\n",
              before.surfaces, before.nodes, before.handlers, before.js_resources);
  // The optional event arguments exercise the same platform input contract as UIKit.
  const auto event_node = click_node.empty() ? "node:5" : click_node;
  if (event_name == "feature") {
    const bool accepted = spine->dispatchFeature(feature_module, feature_method,
                                                  feature_value);
    std::printf("ios.probe.feature.queued module=%s method=%s accepted=%d\n",
                feature_module.c_str(), feature_method.c_str(), accepted ? 1 : 0);
  } else if (event_name == "input" || event_name == "change") {
    auto value = quickapp::core::RuntimeValue::utf8_string("Codex");
    quickapp::core::RuntimeValue::Object payload;
    if (value) payload.emplace("value", std::move(value).value());
    static_cast<void>(spine->dispatchInput(
        "srf:1", event_node,
        event_name == "input" ? quickapp::core::package::EventType::kInput
                               : quickapp::core::package::EventType::kChange,
        std::move(payload), 1000000));
  } else if (event_name == "focus") {
    static_cast<void>(spine->dispatchInput(
        "srf:1", event_node, quickapp::core::package::EventType::kFocus, {}, 1000000));
  } else if (event_name == "switch") {
    quickapp::core::RuntimeValue::Object payload;
    payload.emplace("checked", quickapp::core::RuntimeValue::boolean(false));
    static_cast<void>(spine->dispatchInput(
        "srf:1", event_node, quickapp::core::package::EventType::kChange,
        std::move(payload), 1000000));
  } else if (event_name == "slider") {
    quickapp::core::RuntimeValue::Object payload;
    auto value = quickapp::core::RuntimeValue::finite_number(55.0);
    if (value) payload.emplace("value", std::move(value).value());
    payload.emplace("isFromUser", quickapp::core::RuntimeValue::boolean(true));
    static_cast<void>(spine->dispatchInput(
        "srf:1", event_node, quickapp::core::package::EventType::kChange,
        std::move(payload), 1000000));
  } else if (event_name == "picker") {
    quickapp::core::RuntimeValue::Object payload;
    auto selected = quickapp::core::RuntimeValue::finite_number(2.0);
    if (selected) payload.emplace("selected", std::move(selected).value());
    auto value = quickapp::core::RuntimeValue::utf8_string("性能");
    if (value) payload.emplace("value", std::move(value).value());
    static_cast<void>(spine->dispatchInput(
        "srf:1", event_node, quickapp::core::package::EventType::kChange,
        std::move(payload), 1000000));
  } else if (event_name == "scroll" || event_name == "scrollend" ||
             event_name == "scrolltop" || event_name == "scrollbottom") {
    quickapp::core::RuntimeValue::Object payload;
    auto offset = quickapp::core::RuntimeValue::finite_number(
        event_name == "scrollbottom" ? 210.0 : 0.0);
    auto content = quickapp::core::RuntimeValue::finite_number(620.0);
    auto viewport = quickapp::core::RuntimeValue::finite_number(410.0);
    if (offset) payload.emplace("scrollOffset", std::move(offset).value());
    if (content) payload.emplace("contentSize", std::move(content).value());
    if (viewport) payload.emplace("viewportSize", std::move(viewport).value());
    auto event_type = event_name == "scroll" ? quickapp::core::package::EventType::kScroll
        : event_name == "scrollend" ? quickapp::core::package::EventType::kScrollEnd
        : event_name == "scrolltop" ? quickapp::core::package::EventType::kScrollTop
                                     : quickapp::core::package::EventType::kScrollBottom;
    static_cast<void>(spine->dispatchInput("srf:1", event_node, event_type,
                                           std::move(payload), 1000000));
  } else {
    static_cast<void>(spine->dispatchClick("srf:1", event_node, 1000000));
  }
  if (event_name == "feature" || rpk.find("controls-001") != std::string::npos ||
      rpk.find("controls-002") != std::string::npos || event_name != "click") {
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
    const auto after_event = spine->snapshot();
    std::printf("ios.probe.after_event type=%s surfaces=%zu nodes=%zu handlers=%zu jsResources=%zu\n",
                event_name.c_str(), after_event.surfaces, after_event.nodes,
                after_event.handlers, after_event.js_resources);
    spine->destroy();
    return 0;
  }
  for (int i = 0; i < 200; ++i) {
    if (spine->snapshot().surfaces >= 2) break;
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
  }
  auto after = spine->snapshot();
  std::printf("ios.probe.after_click surfaces=%zu nodes=%zu handlers=%zu jsResources=%zu\n",
              after.surfaces, after.nodes, after.handlers, after.js_resources);
    static_cast<void>(spine->dispatchClick("srf:2", back_node, 2000000));
  for (int i = 0; i < 200; ++i) {
    if (spine->snapshot().surfaces <= 1) break;
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
  }
  auto returned = spine->snapshot();
  std::printf("ios.probe.after_back surfaces=%zu nodes=%zu handlers=%zu jsResources=%zu\n",
              returned.surfaces, returned.nodes, returned.handlers,
              returned.js_resources);
  spine->destroy();
  return 0;
}
