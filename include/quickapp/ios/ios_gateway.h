#pragma once

#ifdef __OBJC__
#import <UIKit/UIKit.h>
#else
class UIView;
#endif

#include <memory>
#include <map>
#include <cstdint>
#include <string>
#include <vector>

#include "quickapp/core/feature/module_registry.h"
#include "quickapp/ios/runtime_spine.h"

namespace quickapp::ios {

class IOSGateway;
namespace platform {
class Gateway;
}

std::shared_ptr<platform::Gateway> makeGateway(UIView *root_view) noexcept;
void bindGateway(const std::shared_ptr<platform::Gateway> &gateway,
                 const std::shared_ptr<RuntimeSpine> &spine) noexcept;
void closeGateway(const std::shared_ptr<platform::Gateway> &gateway) noexcept;
using ResourceBytes = std::shared_ptr<const std::vector<std::uint8_t>>;
struct ResourceRecord final {
  ResourceBytes bytes;
  std::string media_type;
  std::uint64_t byte_length{0};
  std::string sha256;
};
using ResourceRecords = std::map<std::string, ResourceRecord, std::less<>>;
void setGatewayResources(
    const std::shared_ptr<platform::Gateway> &gateway,
    ResourceRecords resources) noexcept;
bool controlVideo(const std::shared_ptr<platform::Gateway> &gateway,
                  std::string surface_id, std::string node_id,
                  std::string action, double position_seconds = 0) noexcept;
bool controlTabs(const std::shared_ptr<platform::Gateway> &gateway,
                 std::string surface_id, std::string node_id,
                 std::int64_t index) noexcept;
bool controlClick(const std::shared_ptr<platform::Gateway> &gateway,
                  std::string surface_id, std::string node_id) noexcept;
bool controlInput(const std::shared_ptr<platform::Gateway> &gateway,
                  std::string surface_id, std::string node_id,
                  std::string value) noexcept;
bool controlSwitch(const std::shared_ptr<platform::Gateway> &gateway,
                   std::string surface_id, std::string node_id,
                   bool checked) noexcept;
bool controlSlider(const std::shared_ptr<platform::Gateway> &gateway,
                   std::string surface_id, std::string node_id,
                   double value) noexcept;
bool controlPicker(const std::shared_ptr<platform::Gateway> &gateway,
                   std::string surface_id, std::string node_id,
                   std::int64_t index) noexcept;
bool controlScroll(const std::shared_ptr<platform::Gateway> &gateway,
                   std::string surface_id, std::string node_id,
                   double offset) noexcept;
core::feature::Provider *featureProvider(
    const std::shared_ptr<platform::Gateway> &gateway) noexcept;

}  // namespace quickapp::ios
