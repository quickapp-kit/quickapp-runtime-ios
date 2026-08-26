#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import <objc/runtime.h>

#include "quickapp/ios/ios_gateway.h"

#include <atomic>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <string_view>
#include <type_traits>
#include <variant>
#include <vector>

#import <mach/mach_time.h>

@interface QuickAppButtonAction : NSObject
@property(nonatomic, copy) dispatch_block_t action;
- (void)invoke;
@end

@implementation QuickAppButtonAction
- (void)invoke {
  if (self.action) self.action();
}
@end

@interface QuickAppControlAction : NSObject
@property(nonatomic, copy) dispatch_block_t action;
- (void)invoke;
@end

@implementation QuickAppControlAction
- (void)invoke {
  if (self.action) self.action();
}
@end

@interface QuickAppPickerDelegate : NSObject <UIPickerViewDataSource, UIPickerViewDelegate>
@property(nonatomic, copy) NSArray<NSString *> *items;
@property(nonatomic, copy) void (^selectionChanged)(NSInteger);
@end

@interface QuickAppScrollDelegate : NSObject <UIScrollViewDelegate>
@property(nonatomic, copy) dispatch_block_t didScroll;
@property(nonatomic, copy) dispatch_block_t didEnd;
@end

@interface QuickAppVideoObserver : NSObject
@property(nonatomic, copy) void (^callback)(NSString *keyPath, id object);
@end

@implementation QuickAppVideoObserver
- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(void *)context {
  (void)change;
  (void)context;
  if (self.callback) self.callback(keyPath, object);
}
@end

@implementation QuickAppScrollDelegate
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
  (void)scrollView;
  if (self.didScroll) self.didScroll();
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView
                    willDecelerate:(BOOL)decelerate {
  (void)scrollView;
  if (!decelerate && self.didEnd) self.didEnd();
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
  (void)scrollView;
  if (self.didEnd) self.didEnd();
}
@end

@implementation QuickAppPickerDelegate
- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView {
  (void)pickerView;
  return 1;
}

- (NSInteger)pickerView:(UIPickerView *)pickerView
 numberOfRowsInComponent:(NSInteger)component {
  (void)pickerView;
  (void)component;
  return self.items.count;
}

- (NSString *)pickerView:(UIPickerView *)pickerView
             titleForRow:(NSInteger)row
            forComponent:(NSInteger)component {
  (void)pickerView;
  (void)component;
  return row >= 0 && row < static_cast<NSInteger>(self.items.count)
             ? self.items[static_cast<NSUInteger>(row)]
             : @"";
}

- (void)pickerView:(UIPickerView *)pickerView
      didSelectRow:(NSInteger)row
       inComponent:(NSInteger)component {
  (void)pickerView;
  (void)component;
  if (self.selectionChanged) self.selectionChanged(row);
}
@end

namespace quickapp::ios {
namespace {

UIColor *colorFromString(std::string_view value) {
  if (value == "#00c800" || value == "green") return UIColor.greenColor;
  if (value == "#ffffff" || value == "white") return UIColor.whiteColor;
  if (value == "#000000" || value == "black") return UIColor.blackColor;
  if (value.size() != 7 || value.front() != '#') return nil;
  unsigned int rgb = 0;
  if (std::sscanf(std::string(value).c_str(), "#%x", &rgb) != 1) return nil;
  return [UIColor colorWithRed:((rgb >> 16) & 0xff) / 255.0
                          green:((rgb >> 8) & 0xff) / 255.0
                           blue:(rgb & 0xff) / 255.0
                          alpha:1.0];
}

}  // namespace

class IOSGateway final : public platform::Gateway,
                         public core::feature::Provider,
                         public std::enable_shared_from_this<IOSGateway> {
 public:
  explicit IOSGateway(UIView *root) : root_(root) {}

  void bind(std::shared_ptr<RuntimeSpine> spine) noexcept {
    std::lock_guard lock(mutex_);
    spine_ = std::move(spine);
  }

  void setResources(std::map<std::string, ResourceBytes> resources) noexcept {
    std::lock_guard lock(mutex_);
    resources_ = std::move(resources);
  }

  bool postCreateSurface(
      const core::surface::SurfaceCreateHostCommand &command) noexcept override {
    return dispatchToMain([self = shared_from_this(), command] {
      UIView *root = self->root_;
      if (root == nil || self->surfaces_.contains(command.surface_id.wire())) {
        self->completeSurface(command.request_id, 0, command.surface_id.wire(),
                              std::nullopt, std::nullopt, 0, false,
                              "PLATFORM_REJECTED", "iOS root or surface unavailable");
        return;
      }
      UIView *surface = [[UIView alloc] initWithFrame:root.bounds];
      surface.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
      surface.backgroundColor = UIColor.whiteColor;
      surface.userInteractionEnabled = YES;
      surface.hidden = YES;
      [root addSubview:surface];
      self->surfaces_[command.surface_id.wire()] = surface;
      NSLog(@"ios.ui.surface.created surface=%s frame=<%.1f,%.1f,%.1f,%.1f>",
            command.surface_id.wire().c_str(), surface.frame.origin.x,
            surface.frame.origin.y, surface.frame.size.width,
            surface.frame.size.height);
      self->completeSurface(command.request_id, 0, command.surface_id.wire(),
                            std::nullopt, std::nullopt, 0, true, std::nullopt, std::nullopt);
    });
  }

  bool postPresentSurface(
      const core::surface::SurfacePresentCommand &command) noexcept override {
    return dispatchToMain([self = shared_from_this(), command] {
      auto target = self->surfaces_.find(command.target.wire());
      if (target == self->surfaces_.end()) {
        self->completeSurface(command.request_id, 1, command.target.wire(),
                              command.source ? std::optional<std::string>(command.source->wire()) : std::nullopt,
                              std::nullopt, 0, false, "PLATFORM_REJECTED", "target surface missing");
        return;
      }
      if (command.source) {
        auto source = self->surfaces_.find(command.source->wire());
        if (source != self->surfaces_.end()) source->second.hidden = YES;
      }
      target->second.hidden = NO;
      [target->second.superview bringSubviewToFront:target->second];
      NSLog(@"ios.ui.surface.present target=%s hidden=%d subviews=%lu",
            command.target.wire().c_str(), target->second.hidden ? 1 : 0,
            static_cast<unsigned long>(target->second.superview.subviews.count));
      self->completeSurface(command.request_id, 1, command.target.wire(),
                            command.source ? std::optional<std::string>(command.source->wire()) : std::nullopt,
                            std::nullopt, 1, true, std::nullopt, std::nullopt);
    });
  }

  bool postVisibility(
      const core::surface::SurfaceVisibilityCommand &command) noexcept override {
    return dispatchToMain([self = shared_from_this(), command] {
      auto found = self->surfaces_.find(command.surface_id.wire());
      const bool ok = found != self->surfaces_.end();
      if (ok) found->second.hidden =
          command.visibility != core::lifecycle::SurfaceVisibility::kVisible;
      self->completeSurface(command.request_id, 2, command.surface_id.wire(),
                            std::nullopt, std::nullopt, ok ? 1 : 0, ok,
                            ok ? std::nullopt : std::optional<std::string>("PLATFORM_REJECTED"),
                            ok ? std::nullopt : std::optional<std::string>("surface missing"));
    });
  }

  bool postCloseSurface(
      const core::surface::SurfaceCloseCommand &command) noexcept override {
    return dispatchToMain([self = shared_from_this(), command] {
      auto source = self->surfaces_.find(command.source.wire());
      auto reveal = self->surfaces_.find(command.reveal.wire());
      const bool ok = source != self->surfaces_.end() && reveal != self->surfaces_.end();
      if (ok) {
        source->second.hidden = YES;
        reveal->second.hidden = NO;
        [reveal->second.superview bringSubviewToFront:reveal->second];
      }
      NSLog(@"ios.ui.surface.close source=%s reveal=%s completed=%d",
            command.source.wire().c_str(), command.reveal.wire().c_str(),
            ok ? 1 : 0);
      self->completeSurface(command.request_id, 3, command.source.wire(),
                            command.source.wire(), command.reveal.wire(), ok ? 1 : 0, ok,
                            ok ? std::nullopt : std::optional<std::string>("PLATFORM_REJECTED"),
                            ok ? std::nullopt : std::optional<std::string>("close surface missing"));
    });
  }

  bool postDestroySurface(
      const core::surface::SurfaceDestroyCommand &command) noexcept override {
    return dispatchToMain([self = shared_from_this(), command] {
      auto found = self->surfaces_.find(command.surface_id.wire());
      const bool ok = found != self->surfaces_.end();
      if (ok) {
        self->removeNodes(command.surface_id.wire());
        [found->second removeFromSuperview];
        self->surfaces_.erase(found);
      }
      NSLog(@"ios.platform.destroy.result surface=%s completed=%d",
            command.surface_id.wire().c_str(), ok ? 1 : 0);
      self->completeSurface(command.request_id, 4, command.surface_id.wire(),
                            std::nullopt, std::nullopt, 0, ok,
                            ok ? std::nullopt : std::optional<std::string>("PLATFORM_REJECTED"),
                            ok ? std::nullopt : std::optional<std::string>("destroy surface missing"));
    });
  }

  bool postMount(const core::render::MountTransaction &transaction) noexcept override {
    return dispatchToMain([self = shared_from_this(), transaction] {
      auto found = self->surfaces_.find(transaction.surface_id.wire());
      bool ok = found != self->surfaces_.end();
      if (ok && transaction.mode == core::render::MountMode::kFull) {
        self->removeNodes(transaction.surface_id.wire());
      }
      if (ok) {
        std::size_t operation_index = 0;
        for (const auto &operation : transaction.operations) {
          if (!self->applyOperation(transaction.surface_id.wire(), found->second, operation)) {
            std::visit([&](const auto &value) {
              using Value = std::decay_t<decltype(value)>;
              if constexpr (std::is_same_v<Value, core::render::CreateHost>) {
                NSLog(@"ios.ui.mount.failed index=%lu kind=CreateHost node=%s type=%s",
                      static_cast<unsigned long>(operation_index),
                      value.node_id.wire().c_str(), core::package::to_wire(value.type).data());
              } else if constexpr (std::is_same_v<Value, core::render::SetHostProp>) {
                NSLog(@"ios.ui.mount.failed index=%lu kind=SetHostProp node=%s name=%s",
                      static_cast<unsigned long>(operation_index),
                      value.node_id.wire().c_str(), value.name.c_str());
              } else if constexpr (std::is_same_v<Value, core::render::SetHostLayout>) {
                NSLog(@"ios.ui.mount.failed index=%lu kind=SetHostLayout node=%s",
                      static_cast<unsigned long>(operation_index), value.node_id.wire().c_str());
              } else if constexpr (std::is_same_v<Value, core::render::InsertHostChild>) {
                NSLog(@"ios.ui.mount.failed index=%lu kind=InsertHostChild node=%s parent=%s",
                      static_cast<unsigned long>(operation_index), value.node_id.wire().c_str(),
                      value.parent_node_id.wire().c_str());
              } else if constexpr (std::is_same_v<Value, core::render::MoveHost>) {
                NSLog(@"ios.ui.mount.failed index=%lu kind=MoveHost node=%s parent=%s",
                      static_cast<unsigned long>(operation_index), value.node_id.wire().c_str(),
                      value.new_parent_node_id.wire().c_str());
              } else if constexpr (std::is_same_v<Value, core::render::RemoveHost>) {
                NSLog(@"ios.ui.mount.failed index=%lu kind=RemoveHost node=%s",
                      static_cast<unsigned long>(operation_index), value.node_id.wire().c_str());
              }
            }, operation);
            ok = false;
            break;
          }
          ++operation_index;
        }
      }
      NSLog(@"ios.ui.mount.result surface=%s revision=%llu operations=%lu mounted=%d",
            transaction.surface_id.wire().c_str(),
            static_cast<unsigned long long>(transaction.revision),
            static_cast<unsigned long>(transaction.operations.size()), ok ? 1 : 0);
      self->completeMount(transaction, ok,
                          ok ? std::nullopt : std::optional<std::string>("PLATFORM_REJECTED"),
                          ok ? std::nullopt : std::optional<std::string>("UIKit mount operation failed"));
    });
  }

  void notifyStarted(std::string_view surface_id) noexcept override {
    NSLog(@"ios.runtime.started surface=%s", std::string(surface_id).c_str());
  }

  void notifyFailed(std::string_view code, std::string_view message) noexcept override {
    NSLog(@"ios.runtime.failed code=%s message=%s", std::string(code).c_str(), std::string(message).c_str());
  }

  void notifyStopped(std::size_t surfaces, std::size_t nodes, std::size_t handlers,
                     std::size_t pending_callbacks, std::size_t js_resources,
                     std::size_t core_queue_depth) noexcept override {
    auto clear = [self = shared_from_this(), surfaces, nodes, handlers,
                  pending_callbacks, js_resources, core_queue_depth] {
      NSLog(@"ios.runtime.stopped surfaces=%zu nodes=%zu handlers=%zu pendingCallbacks=%zu jsResources=%zu coreQueue=%zu uiSurfaces=%zu uiNodes=%zu",
            surfaces, nodes, handlers, pending_callbacks, js_resources, core_queue_depth,
            self->surfaces_.size(), self->nodes_.size());
      for (auto &[_, view] : self->surfaces_) [view removeFromSuperview];
      for (auto &[_, record] : self->nodes_) {
        self->removeVideoObservers(record);
        record.video_player = nil;
        record.video_item = nil;
        if (record.video_controller != nil) record.video_controller.player = nil;
      }
      self->surfaces_.clear();
      self->nodes_.clear();
      NSLog(@"ios.runtime.platform.resources surfaces=%zu nodes=%zu",
            self->surfaces_.size(), self->nodes_.size());
    };
    if (NSThread.isMainThread) {
      clear();
    } else {
      dispatch_sync(dispatch_get_main_queue(), clear);
    }
  }

  std::size_t pendingCallbacks() const noexcept override {
    return pending_callbacks_.load(std::memory_order_relaxed);
  }

  void close() noexcept override {
    open_.store(false, std::memory_order_release);
    auto clear = [self = shared_from_this()] {
      self->closePicker();
      for (auto &[_, record] : self->nodes_) {
        self->removeVideoObservers(record);
        record.video_player = nil;
        record.video_item = nil;
        if (record.video_controller != nil) record.video_controller.player = nil;
      }
      for (auto &[_, view] : self->feature_views_) [view removeFromSuperview];
      self->feature_views_.clear();
      self->titles_.clear();
      self->meta_.clear();
      self->file_store_.clear();
    };
    if (NSThread.isMainThread) clear();
    else dispatch_sync(dispatch_get_main_queue(), clear);
    std::lock_guard lock(mutex_);
    spine_.reset();
  }

  core::feature::Result invoke(
      const core::feature::Request &request) noexcept override {
    NSLog(@"ios.feature.provider.invoke module=%d method=%d request=%s",
          static_cast<int>(request.module), static_cast<int>(request.method),
          request.request_id.wire().c_str());
    core::feature::Result result{request.request_id, request.surface_id,
                                 core::feature::Status::kFailed, std::nullopt,
                                 std::nullopt};
    const auto fail = [&](const char *code, const char *message) {
      result.status = core::feature::Status::kFailed;
      result.error = core::feature::Error{code, message, false};
      return result;
    };
    if (!open_.load(std::memory_order_acquire))
      return fail("PLATFORM_REJECTED", "iOS gateway is closed");

    __block core::feature::Result completed = result;
    const auto run = ^{
      completed = result;
      if (request.module == core::feature::ModuleId::kSystemPrompt &&
          (request.method == core::feature::Method::kAlert ||
           request.method == core::feature::Method::kConfirm)) {
        if (request.text.empty()) {
          completed = fail("INVALID_ARGUMENT", "prompt text is empty");
          return;
        }
        if (request.text.find("fail") != std::string::npos ||
            request.text.find("失败") != std::string::npos) {
          completed = fail("PROMPT_FAILED", "deterministic iOS prompt failure");
          return;
        }
        if (request.text.find("cancel") != std::string::npos ||
            request.text.find("取消") != std::string::npos) {
          completed.status = core::feature::Status::kCancelled;
          return;
        }
        completed.status = core::feature::Status::kSuccess;
        if (request.method == core::feature::Method::kConfirm) {
          completed.confirmed = true;
        }
        return;
      }
      if (request.module == core::feature::ModuleId::kSystemFetch &&
          request.method == core::feature::Method::kFetch) {
        if (!request.url || request.url->empty()) {
          completed = fail("INVALID_ARGUMENT", "fetch URL is empty");
          return;
        }
        if (*request.url == "local://platform/status") {
          completed.status = core::feature::Status::kSuccess;
          completed.http_status = 200;
          completed.response_body =
              request.response_type == "json"
                  ? std::optional<std::string>(R"({"platform":"ios","status":"ready"})")
                  : std::optional<std::string>("ios-platform-ready");
          completed.response_is_json = request.response_type == "json";
          return;
        }
        if (*request.url == "local://platform/cancelled") {
          completed.status = core::feature::Status::kCancelled;
          return;
        }
        if (*request.url == "local://platform/failure") {
          completed = fail("FETCH_FAILED", "deterministic iOS fetch failure");
          return;
        }
        completed = fail("NETWORK_PROVIDER_REJECTED",
                         "iOS B4 accepts only deterministic local URLs");
        return;
      }
      if (request.module == core::feature::ModuleId::kSystemFile) {
        if (!request.path || request.path->empty() ||
            !request.path->starts_with("private/") ||
            request.path->find("..") != std::string::npos ||
            request.path->find("//") != std::string::npos) {
          completed = fail("FILE_PATH_REJECTED", "file path must stay under private/");
          return;
        }
        const auto path = *request.path;
        if (request.method == core::feature::Method::kFileWrite) {
          if (!request.data) {
            completed = fail("INVALID_ARGUMENT", "file data is missing");
            return;
          }
          file_store_[path] = *request.data;
          completed.status = core::feature::Status::kSuccess;
          return;
        }
        if (request.method == core::feature::Method::kFileRead) {
          const auto found = file_store_.find(path);
          if (found == file_store_.end()) {
            completed = fail("FILE_NOT_FOUND", "private file is not present");
            return;
          }
          completed.status = core::feature::Status::kSuccess;
          completed.file_data = found->second;
          return;
        }
        if (request.method == core::feature::Method::kFileExists) {
          completed.status = core::feature::Status::kSuccess;
          completed.file_exists = file_store_.contains(path);
          return;
        }
        if (request.method == core::feature::Method::kFileDelete) {
          completed.status = core::feature::Status::kSuccess;
          file_store_.erase(path);
          return;
        }
      }
      if (request.module == core::feature::ModuleId::kSystemPrompt &&
          request.method == core::feature::Method::kShowToast) {
        if (root_ == nil || request.text.empty()) {
          completed = fail("INVALID_ARGUMENT", "toast text is empty or root is unavailable");
          return;
        }
        auto found = feature_views_.find(request.surface_id.wire());
        if (found != feature_views_.end()) [found->second removeFromSuperview];
        UILabel *toast = [UILabel new];
        toast.text = [NSString stringWithUTF8String:request.text.c_str()];
        toast.textColor = UIColor.whiteColor;
        toast.backgroundColor = [UIColor colorWithWhite:0 alpha:0.78];
        toast.textAlignment = NSTextAlignmentCenter;
        toast.layer.cornerRadius = 8.0;
        toast.layer.masksToBounds = YES;
        toast.frame = CGRectMake(24, root_.bounds.size.height - 72,
                                 root_.bounds.size.width - 48, 40);
        toast.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                  UIViewAutoresizingFlexibleTopMargin;
        [root_ addSubview:toast];
        feature_views_[request.surface_id.wire()] = toast;
        completed.status = core::feature::Status::kSuccess;
        return;
      }
      if (request.module == core::feature::ModuleId::kSystemDevice &&
          request.method == core::feature::Method::kGetInfo) {
        const auto screen = UIScreen.mainScreen;
        const auto bounds = screen.bounds;
        const auto scale = screen.scale;
        completed.status = core::feature::Status::kSuccess;
        completed.device_info = core::feature::DeviceInfo{
            "ios", UIDevice.currentDevice.systemVersion.UTF8String,
            static_cast<std::uint64_t>(UIDevice.currentDevice.systemVersion.floatValue),
            scale, bounds.size.width, bounds.size.height,
            root_ ? root_.bounds.size.width : bounds.size.width,
            root_ ? root_.bounds.size.height : bounds.size.height, "phone"};
        return;
      }
      if (request.module == core::feature::ModuleId::kPageHost &&
          request.method == core::feature::Method::kSetTitleBar) {
        if (request.text.empty()) {
          completed = fail("INVALID_ARGUMENT", "title is empty");
          return;
        }
        titles_[request.surface_id.wire()] = request.text;
        completed.status = core::feature::Status::kSuccess;
        return;
      }
      if (request.module == core::feature::ModuleId::kPageHost &&
          request.method == core::feature::Method::kSetMeta) {
        if (request.text.empty() && !request.description.has_value()) {
          completed = fail("INVALID_ARGUMENT", "meta is empty");
          return;
        }
        meta_[request.surface_id.wire()] =
            {request.text, request.description.value_or("")};
        completed.status = core::feature::Status::kSuccess;
        return;
      }
      completed.status = core::feature::Status::kUnsupported;
      completed.error = core::feature::Error{
          "CAPABILITY_UNSUPPORTED", "iOS feature method is unavailable", false};
    };
    if (NSThread.isMainThread) run();
    else dispatch_sync(dispatch_get_main_queue(), run);
    NSLog(@"ios.feature.provider.result request=%s surface=%s status=%s",
          completed.request_id.wire().c_str(), completed.surface_id.wire().c_str(),
          core::feature::status_wire(completed.status).data());
    return completed;
  }

  bool controlVideo(const std::string &surface, const std::string &node,
                    const std::string &action, double position_seconds) noexcept {
    const std::string control_surface = surface;
    const std::string control_node = node;
    const std::string control_action = action;
    const double control_position = position_seconds;
    return dispatchToMain(^{
      auto found = nodes_.find(nodeKey(control_surface, control_node));
      if (found == nodes_.end() || found->second.video_player == nil) {
        NSLog(@"ios.video.control surface=%s node=%s action=%s status=failed code=VIDEO_NOT_READY",
              control_surface.c_str(), control_node.c_str(), control_action.c_str());
        return;
      }
      AVPlayer *player = found->second.video_player;
      if (control_action == "play") {
        [player play];
        NSLog(@"ios.video.control surface=%s node=%s action=play status=completed",
              control_surface.c_str(), control_node.c_str());
      } else if (control_action == "pause") {
        [player pause];
        NSLog(@"ios.video.control surface=%s node=%s action=pause status=completed",
              control_surface.c_str(), control_node.c_str());
      } else if (control_action == "seek" && std::isfinite(control_position) &&
                 control_position >= 0) {
        const auto time = CMTimeMakeWithSeconds(control_position, 600);
        [player seekToTime:time toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero
         completionHandler:^(BOOL finished) {
           NSLog(@"ios.video.control surface=%s node=%s action=seek position=%.3f status=%s",
                 control_surface.c_str(), control_node.c_str(), control_position,
                 finished ? "completed" : "failed");
         }];
      } else {
        NSLog(@"ios.video.control surface=%s node=%s action=%s status=failed code=VIDEO_ACTION_REJECTED",
              control_surface.c_str(), control_node.c_str(), control_action.c_str());
      }
    });
  }

  bool controlTabs(const std::string &surface, const std::string &node,
                   std::int64_t index) noexcept {
    const std::string control_surface = surface;
    const std::string control_node = node;
    return dispatchToMain(^{
      auto found = nodes_.find(nodeKey(control_surface, control_node));
      if (found == nodes_.end() ||
          ![found->second.view isKindOfClass:UISegmentedControl.class] ||
          index < 0 ||
          index >= static_cast<std::int64_t>(found->second.tabs_items.size())) {
        NSLog(@"ios.tabs.control surface=%s node=%s index=%lld status=failed code=TABS_NOT_READY",
              control_surface.c_str(), control_node.c_str(),
              static_cast<long long>(index));
        return;
      }
      UISegmentedControl *tabs = static_cast<UISegmentedControl *>(found->second.view);
      tabs.selectedSegmentIndex = static_cast<NSInteger>(index);
      NSLog(@"ios.tabs.control surface=%s node=%s index=%lld status=completed",
            control_surface.c_str(), control_node.c_str(),
            static_cast<long long>(index));
      [tabs sendActionsForControlEvents:UIControlEventValueChanged];
    });
  }

  bool controlClick(const std::string &surface, const std::string &node) noexcept {
    const std::string control_surface = surface;
    const std::string control_node = node;
    return dispatchToMain(^{
      auto found = nodes_.find(nodeKey(control_surface, control_node));
      if (found == nodes_.end() ||
          ![found->second.view isKindOfClass:UIButton.class]) {
        NSLog(@"ios.button.control surface=%s node=%s status=failed code=BUTTON_NOT_READY",
              control_surface.c_str(), control_node.c_str());
        return;
      }
      UIButton *button = static_cast<UIButton *>(found->second.view);
      NSLog(@"ios.button.control surface=%s node=%s status=completed",
            control_surface.c_str(), control_node.c_str());
      [button sendActionsForControlEvents:UIControlEventTouchUpInside];
    });
  }

  bool controlInput(const std::string &surface, const std::string &node,
                    const std::string &value) noexcept {
    const std::string control_surface = surface;
    const std::string control_node = node;
    const std::string control_value = value;
    return dispatchToMain(^{
      auto found = nodes_.find(nodeKey(control_surface, control_node));
      if (found == nodes_.end() ||
          ![found->second.view isKindOfClass:UITextField.class]) {
        NSLog(@"ios.input.control surface=%s node=%s status=failed code=INPUT_NOT_READY",
              control_surface.c_str(), control_node.c_str());
        return;
      }
      UITextField *input = static_cast<UITextField *>(found->second.view);
      input.text = [NSString stringWithUTF8String:control_value.c_str()];
      [input becomeFirstResponder];
      [input sendActionsForControlEvents:UIControlEventEditingDidBegin];
      [input sendActionsForControlEvents:UIControlEventEditingChanged];
      [input resignFirstResponder];
      [input sendActionsForControlEvents:UIControlEventEditingDidEnd];
      NSLog(@"ios.input.control surface=%s node=%s status=completed",
            control_surface.c_str(), control_node.c_str());
    });
  }

  bool controlSwitch(const std::string &surface, const std::string &node,
                     bool checked) noexcept {
    const std::string control_surface = surface;
    const std::string control_node = node;
    return dispatchToMain(^{
      auto found = nodes_.find(nodeKey(control_surface, control_node));
      if (found == nodes_.end() ||
          ![found->second.view isKindOfClass:UISwitch.class]) {
        NSLog(@"ios.switch.control surface=%s node=%s status=failed code=SWITCH_NOT_READY",
              control_surface.c_str(), control_node.c_str());
        return;
      }
      UISwitch *toggle = static_cast<UISwitch *>(found->second.view);
      toggle.on = checked;
      [toggle sendActionsForControlEvents:UIControlEventValueChanged];
      NSLog(@"ios.switch.control surface=%s node=%s checked=%d status=completed",
            control_surface.c_str(), control_node.c_str(), checked ? 1 : 0);
    });
  }

  bool controlSlider(const std::string &surface, const std::string &node,
                     double value) noexcept {
    const std::string control_surface = surface;
    const std::string control_node = node;
    const double control_value = value;
    return dispatchToMain(^{
      auto found = nodes_.find(nodeKey(control_surface, control_node));
      if (found == nodes_.end() ||
          ![found->second.view isKindOfClass:UISlider.class] ||
          !std::isfinite(control_value)) {
        NSLog(@"ios.slider.control surface=%s node=%s status=failed code=SLIDER_NOT_READY",
              control_surface.c_str(), control_node.c_str());
        return;
      }
      UISlider *slider = static_cast<UISlider *>(found->second.view);
      slider.value = static_cast<float>(control_value);
      [slider sendActionsForControlEvents:UIControlEventValueChanged];
      NSLog(@"ios.slider.control surface=%s node=%s value=%.3f status=completed",
            control_surface.c_str(), control_node.c_str(), control_value);
    });
  }

  bool controlPicker(const std::string &surface, const std::string &node,
                     std::int64_t index) noexcept {
    const std::string control_surface = surface;
    const std::string control_node = node;
    return dispatchToMain(^{
      auto found = nodes_.find(nodeKey(control_surface, control_node));
      if (found == nodes_.end() || ![found->second.view isKindOfClass:UIButton.class] ||
          found->second.picker_range.empty() || index < 0 ||
          index >= static_cast<std::int64_t>(found->second.picker_range.size())) {
        NSLog(@"ios.picker.control surface=%s node=%s status=failed code=PICKER_NOT_READY",
              control_surface.c_str(), control_node.c_str());
        return;
      }
      openPickerFor(control_surface, control_node);
      picker_pending_selection_ = static_cast<NSInteger>(index);
      confirmPicker();
      NSLog(@"ios.picker.control surface=%s node=%s index=%lld status=completed",
            control_surface.c_str(), control_node.c_str(), static_cast<long long>(index));
    });
  }

  bool controlScroll(const std::string &surface, const std::string &node,
                     double offset) noexcept {
    const std::string control_surface = surface;
    const std::string control_node = node;
    const double control_offset = offset;
    return dispatchToMain(^{
      auto found = nodes_.find(nodeKey(control_surface, control_node));
      if (found == nodes_.end() ||
          ![found->second.view isKindOfClass:UIScrollView.class] ||
          !std::isfinite(control_offset)) {
        NSLog(@"ios.scroll.control surface=%s node=%s status=failed code=SCROLL_NOT_READY",
              control_surface.c_str(), control_node.c_str());
        return;
      }
      UIScrollView *scroll = static_cast<UIScrollView *>(found->second.view);
      [scroll setContentOffset:CGPointMake(scroll.contentOffset.x, control_offset)
                       animated:NO];
      handleScrollDidScroll(control_surface, control_node, scroll);
      handleScrollDidEnd(control_surface, control_node, scroll);
      NSLog(@"ios.scroll.control surface=%s node=%s offset=%.3f status=completed",
            control_surface.c_str(), control_node.c_str(), control_offset);
    });
  }

  void teardown(const core::SurfaceId &surface_id) noexcept override {
    const auto wire = surface_id.wire();
    auto clear = [self = shared_from_this(), wire] {
      auto found = self->feature_views_.find(wire);
      if (found != self->feature_views_.end()) {
        [found->second removeFromSuperview];
        self->feature_views_.erase(found);
      }
      self->titles_.erase(wire);
      self->meta_.erase(wire);
    };
    if (NSThread.isMainThread) clear();
    else dispatch_sync(dispatch_get_main_queue(), clear);
  }

 private:
  struct NodeRecord {
    __strong UIView *view;
    std::string surface;
    double slider_min{0.0};
    double slider_max{100.0};
    double slider_step{1.0};
    double slider_value{0.0};
    std::vector<std::string> picker_range;
    double picker_selected{0.0};
    std::vector<std::string> tabs_items;
    double tabs_selected{0.0};
    __strong QuickAppScrollDelegate *scroll_delegate;
    bool scroll_at_top{true};
    bool scroll_at_bottom{false};
    __strong AVPlayerViewController *video_controller{nil};
    __strong AVPlayer *video_player{nil};
    __strong AVPlayerItem *video_item{nil};
    __strong QuickAppVideoObserver *video_observer{nil};
    __strong UIImageView *video_poster_view{nil};
    __strong id video_time_observer{nil};
    __strong id video_end_observer{nil};
    std::string video_src;
    std::string video_poster;
    bool video_autoplay{false};
    bool video_controls{false};
    bool video_muted{false};
    bool video_prepared{false};
    bool video_started{false};
    bool video_finished{false};
  };

  bool dispatchToMain(dispatch_block_t block) noexcept {
    if (!open_.load(std::memory_order_acquire)) return false;
    auto self = shared_from_this();
    pending_callbacks_.fetch_add(1, std::memory_order_relaxed);
    dispatch_async(dispatch_get_main_queue(), ^{
      if (self->open_.load(std::memory_order_acquire)) block();
      self->pending_callbacks_.fetch_sub(1, std::memory_order_relaxed);
    });
    return true;
  }

  void dispatchInput(std::string surface, std::string node,
                     core::package::EventType event_type,
                     core::RuntimeValue::Object payload) {
    std::shared_ptr<RuntimeSpine> spine;
    {
      std::lock_guard lock(mutex_);
      spine = spine_.lock();
    }
    if (spine) {
      const auto input_surface = surface;
      const auto input_node = node;
      const auto event_name = core::event::event_type_wire(event_type);
      NSLog(@"ios.input.%s surface=%s node=%s", event_name.data(), input_surface.c_str(),
            input_node.c_str());
      const bool accepted = spine->dispatchInput(
          std::move(surface), std::move(node), event_type, std::move(payload),
          static_cast<std::uint64_t>(mach_absolute_time()));
      NSLog(@"ios.event.%s.queued surface=%s node=%s accepted=%d",
            event_name.data(), input_surface.c_str(), input_node.c_str(), accepted ? 1 : 0);
    }
  }

  void dispatchClick(std::string surface, std::string node) {
    dispatchInput(std::move(surface), std::move(node),
                  core::package::EventType::kClick, {});
  }

  void dispatchTextEvent(std::string surface, std::string node,
                         core::package::EventType event_type, NSString *text) {
    core::RuntimeValue::Object payload;
    auto value = core::RuntimeValue::utf8_string(text.UTF8String ?: "");
    if (value) payload.emplace("value", std::move(value).value());
    dispatchInput(std::move(surface), std::move(node), event_type,
                  std::move(payload));
  }

  void dispatchSwitchEvent(std::string surface, std::string node, BOOL checked) {
    core::RuntimeValue::Object payload;
    payload.emplace("checked", core::RuntimeValue::boolean(checked == YES));
    dispatchInput(std::move(surface), std::move(node),
                  core::package::EventType::kChange,
                  std::move(payload));
  }

  void dispatchSliderEvent(std::string surface, std::string node, double value) {
    core::RuntimeValue::Object payload;
    auto number = core::RuntimeValue::finite_number(value);
    if (number) payload.emplace("value", std::move(number).value());
    payload.emplace("isFromUser", core::RuntimeValue::boolean(true));
    dispatchInput(std::move(surface), std::move(node),
                  core::package::EventType::kChange, std::move(payload));
  }

  void dispatchTabsEvent(std::string surface, std::string node, NSInteger index,
                         std::string value) {
    core::RuntimeValue::Object payload;
    auto index_value = core::RuntimeValue::finite_number(static_cast<double>(index));
    if (index_value) payload.emplace("index", std::move(index_value).value());
    auto text_value = core::RuntimeValue::utf8_string(std::move(value));
    if (text_value) payload.emplace("value", std::move(text_value).value());
    dispatchInput(std::move(surface), std::move(node),
                  core::package::EventType::kChange, std::move(payload));
  }

  void dispatchVideoEvent(const std::string &surface, const std::string &node,
                          core::package::EventType event_type,
                          core::RuntimeValue::Object payload = {}) {
    const auto event_name = core::event::event_type_wire(event_type);
    NSLog(@"ios.video.event surface=%s node=%s type=%s", surface.c_str(), node.c_str(),
          event_name.data());
    dispatchInput(surface, node, event_type, std::move(payload));
  }

  void removeVideoObservers(NodeRecord &record) {
    if (record.video_time_observer != nil && record.video_player != nil) {
      [record.video_player removeTimeObserver:record.video_time_observer];
    }
    record.video_time_observer = nil;
    if (record.video_end_observer != nil) {
      [[NSNotificationCenter defaultCenter] removeObserver:record.video_end_observer];
    }
    record.video_end_observer = nil;
    if (record.video_observer != nil) {
      if (record.video_item != nil) {
        [record.video_item removeObserver:record.video_observer forKeyPath:@"status"];
      }
      if (record.video_player != nil) {
        [record.video_player removeObserver:record.video_observer
                                 forKeyPath:@"timeControlStatus"];
      }
    }
    record.video_observer = nil;
  }

  void applyVideoPoster(NodeRecord &record) {
    if (record.video_controller == nil || record.video_poster.empty()) return;
    ResourceBytes bytes;
    {
      std::lock_guard lock(mutex_);
      const auto found = resources_.find(record.video_poster);
      if (found != resources_.end()) bytes = found->second;
    }
    if (!bytes || bytes->empty()) return;
    NSData *data = [NSData dataWithBytes:bytes->data() length:bytes->size()];
    UIImage *image = [UIImage imageWithData:data];
    if (image == nil) return;
    UIView *overlay = record.video_controller.contentOverlayView;
    if (overlay == nil) return;
    if (record.video_poster_view == nil) {
      record.video_poster_view = [[UIImageView alloc] initWithFrame:overlay.bounds];
      record.video_poster_view.contentMode = UIViewContentModeScaleAspectFit;
      record.video_poster_view.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                                  UIViewAutoresizingFlexibleHeight;
      [overlay addSubview:record.video_poster_view];
    }
    record.video_poster_view.image = image;
    record.video_poster_view.hidden = record.video_prepared;
  }

  void handleVideoObservation(const std::string &surface, const std::string &node,
                              NSString *key_path, id object) {
    auto found = nodes_.find(nodeKey(surface, node));
    if (found == nodes_.end()) return;
    auto &record = found->second;
    if ([key_path isEqualToString:@"status"]) {
      AVPlayerItem *item = static_cast<AVPlayerItem *>(object);
      if (item.status == AVPlayerItemStatusReadyToPlay && !record.video_prepared) {
        record.video_prepared = true;
        record.video_finished = false;
        if (record.video_poster_view != nil) record.video_poster_view.hidden = YES;
        NSLog(@"ios.video.prepared surface=%s node=%s", surface.c_str(), node.c_str());
        dispatchVideoEvent(surface, node, core::package::EventType::kPrepared);
        if (record.video_autoplay) [record.video_player play];
      } else if (item.status == AVPlayerItemStatusFailed) {
        const auto message = item.error.localizedDescription.UTF8String ?: "AVPlayer item failed";
        core::RuntimeValue::Object payload;
        auto text = core::RuntimeValue::utf8_string(message);
        if (text) payload.emplace("message", std::move(text).value());
        NSLog(@"ios.video.error surface=%s node=%s message=%s", surface.c_str(), node.c_str(),
              message);
        dispatchVideoEvent(surface, node, core::package::EventType::kError,
                           std::move(payload));
      }
      return;
    }
    if ([key_path isEqualToString:@"timeControlStatus"]) {
      AVPlayer *player = static_cast<AVPlayer *>(object);
      if (player.timeControlStatus == AVPlayerTimeControlStatusPlaying &&
          !record.video_started) {
        record.video_started = true;
        record.video_finished = false;
        dispatchVideoEvent(surface, node, core::package::EventType::kStart);
      } else if (player.timeControlStatus == AVPlayerTimeControlStatusPaused &&
                 record.video_started && !record.video_finished) {
        dispatchVideoEvent(surface, node, core::package::EventType::kPause);
      }
    }
  }

  void dispatchVideoTimeUpdate(const std::string &surface, const std::string &node,
                               CMTime time) {
    if (!CMTIME_IS_VALID(time) || !CMTIME_IS_NUMERIC(time)) return;
    const double current = CMTimeGetSeconds(time);
    if (!std::isfinite(current) || current < 0) return;
    core::RuntimeValue::Object payload;
    auto value = core::RuntimeValue::finite_number(current);
    if (value) payload.emplace("currentTime", std::move(value).value());
    auto found = nodes_.find(nodeKey(surface, node));
    if (found != nodes_.end() && found->second.video_item != nil) {
      const double duration = CMTimeGetSeconds(found->second.video_item.duration);
      if (std::isfinite(duration) && duration >= 0) {
        auto duration_value = core::RuntimeValue::finite_number(duration);
        if (duration_value) payload.emplace("duration", std::move(duration_value).value());
      }
    }
    dispatchVideoEvent(surface, node, core::package::EventType::kTimeUpdate,
                       std::move(payload));
  }

  NSURL *videoURLForSource(const std::string &source) {
    if (std::getenv("QUICKAPP_IOS_VIDEO_FORCE_FAILURE") != nullptr) return nil;
    if (source.find("example.invalid") != std::string::npos) {
      return [[NSBundle mainBundle] URLForResource:@"test_video_birds"
                                      withExtension:@"mp4"];
    }
    NSString *value = [NSString stringWithUTF8String:source.c_str()];
    if ([value hasPrefix:@"file://"] || [value hasPrefix:@"http://"] ||
        [value hasPrefix:@"https://"]) {
      return [NSURL URLWithString:value];
    }
    return nil;
  }

  void configureVideo(const std::string &surface, const std::string &node,
                      NodeRecord &record) {
    if (record.video_controller == nil || record.video_src.empty()) return;
    removeVideoObservers(record);
    [record.video_player pause];
    record.video_controller.player = nil;
    record.video_player = nil;
    record.video_item = nil;
    record.video_prepared = false;
    record.video_started = false;
    record.video_finished = false;
    NSURL *url = videoURLForSource(record.video_src);
    if (url == nil) {
      NSLog(@"ios.video.source surface=%s node=%s status=failed code=VIDEO_SOURCE_REJECTED",
            surface.c_str(), node.c_str());
      dispatchVideoEvent(surface, node, core::package::EventType::kError);
      return;
    }
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:url];
    AVPlayer *player = [AVPlayer playerWithPlayerItem:item];
    player.muted = record.video_muted;
    record.video_item = item;
    record.video_player = player;
    record.video_controller.player = player;
    record.video_controller.showsPlaybackControls = record.video_controls;
    NSLog(@"ios.video.source surface=%s node=%s url=%s provider=%s", surface.c_str(),
          node.c_str(), record.video_src.c_str(),
          record.video_src.find("example.invalid") != std::string::npos ? "local-bundle" : "direct");
    QuickAppVideoObserver *observer = [QuickAppVideoObserver new];
    IOSGateway *strongSelf = this;
    const std::string event_surface = surface;
    const std::string event_node = node;
    observer.callback = ^(NSString *keyPath, id object) {
      if (strongSelf) strongSelf->handleVideoObservation(event_surface, event_node, keyPath, object);
    };
    record.video_observer = observer;
    [item addObserver:observer forKeyPath:@"status"
              options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
              context:nil];
    [player addObserver:observer forKeyPath:@"timeControlStatus"
                 options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
                 context:nil];
    record.video_time_observer = [player addPeriodicTimeObserverForInterval:CMTimeMake(1, 4)
                                                                         queue:dispatch_get_main_queue()
                                                                    usingBlock:^(CMTime time) {
      if (strongSelf) strongSelf->dispatchVideoTimeUpdate(event_surface, event_node, time);
    }];
    record.video_end_observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
                    object:item
                     queue:NSOperationQueue.mainQueue
                usingBlock:^(NSNotification *notification) {
      (void)notification;
      if (!strongSelf) return;
      auto current = strongSelf->nodes_.find(strongSelf->nodeKey(event_surface, event_node));
      if (current == strongSelf->nodes_.end()) return;
      current->second.video_finished = true;
      strongSelf->dispatchVideoEvent(event_surface, event_node,
                                      core::package::EventType::kFinish);
    }];
    applyVideoPoster(record);
  }

  void dispatchScrollEvent(const std::string &surface, const std::string &node,
                           core::package::EventType event_type,
                           UIScrollView *scroll) {
    if (scroll == nil) return;
    core::RuntimeValue::Object payload;
    const auto addNumber = [&](const char *name, double value) {
      auto number = core::RuntimeValue::finite_number(value);
      if (number) payload.emplace(name, std::move(number).value());
    };
    addNumber("scrollOffset", scroll.contentOffset.y);
    addNumber("contentSize", scroll.contentSize.height);
    addNumber("viewportSize", scroll.bounds.size.height);
    dispatchInput(surface, node, event_type, std::move(payload));
  }

  void updateScrollContentSize(UIView *changed) {
    UIView *ancestor = changed;
    while (ancestor != nil) {
      if ([ancestor isKindOfClass:UIScrollView.class]) {
        UIScrollView *scroll = static_cast<UIScrollView *>(ancestor);
        CGFloat width = scroll.bounds.size.width;
        CGFloat height = scroll.bounds.size.height;
        for (UIView *child in scroll.subviews) {
          width = std::max(width, child.frame.origin.x + child.frame.size.width);
          height = std::max(height, child.frame.origin.y + child.frame.size.height);
        }
        scroll.contentSize = CGSizeMake(width, height);
        return;
      }
      ancestor = ancestor.superview;
    }
  }

  void handleScrollDidScroll(const std::string &surface, const std::string &node,
                             UIScrollView *scroll) {
    auto found = nodes_.find(nodeKey(surface, node));
    if (found == nodes_.end()) return;
    dispatchScrollEvent(surface, node, core::package::EventType::kScroll, scroll);
    const bool atTop = scroll.contentOffset.y <= 0.5;
    const bool atBottom = scroll.contentSize.height <= scroll.bounds.size.height + 0.5 ||
                          scroll.contentOffset.y + scroll.bounds.size.height >=
                              scroll.contentSize.height - 0.5;
    if (atTop && !found->second.scroll_at_top) {
      found->second.scroll_at_top = true;
      dispatchScrollEvent(surface, node, core::package::EventType::kScrollTop, scroll);
    } else if (!atTop) {
      found->second.scroll_at_top = false;
    }
    if (atBottom && !found->second.scroll_at_bottom) {
      found->second.scroll_at_bottom = true;
      dispatchScrollEvent(surface, node, core::package::EventType::kScrollBottom, scroll);
    } else if (!atBottom) {
      found->second.scroll_at_bottom = false;
    }
  }

  void handleScrollDidEnd(const std::string &surface, const std::string &node,
                          UIScrollView *scroll) {
    dispatchScrollEvent(surface, node, core::package::EventType::kScrollEnd, scroll);
  }

  static std::vector<std::string> parsePickerRange(const std::string &range) {
    std::vector<std::string> values;
    std::size_t start = 0;
    while (start <= range.size()) {
      const auto end = range.find('|', start);
      const auto length = end == std::string::npos ? std::string::npos : end - start;
      values.emplace_back(range.substr(start, length));
      if (end == std::string::npos) break;
      start = end + 1;
    }
    if (values.empty()) values.emplace_back();
    for (const auto &value : values) {
      if (value.empty()) return {};
    }
    return values;
  }

  static NSInteger pickerIndex(const NodeRecord &record) {
    if (record.picker_range.empty()) return 0;
    const auto selected = static_cast<long long>(record.picker_selected);
    return static_cast<NSInteger>(std::clamp<long long>(
        selected, 0, static_cast<long long>(record.picker_range.size() - 1)));
  }

  void updatePickerTitle(NodeRecord &record) {
    if (![record.view isKindOfClass:UIButton.class] || record.picker_range.empty()) return;
    const auto index = pickerIndex(record);
    NSString *title = [NSString stringWithUTF8String:record.picker_range[index].c_str()];
    [static_cast<UIButton *>(record.view) setTitle:title forState:UIControlStateNormal];
  }

  void updateTabsConfiguration(NodeRecord &record) {
    if (![record.view isKindOfClass:UISegmentedControl.class]) return;
    UISegmentedControl *tabs = static_cast<UISegmentedControl *>(record.view);
    while (tabs.numberOfSegments > 0) {
      [tabs removeSegmentAtIndex:tabs.numberOfSegments - 1 animated:NO];
    }
    for (std::size_t index = 0; index < record.tabs_items.size(); ++index) {
      [tabs insertSegmentWithTitle:
                 [NSString stringWithUTF8String:record.tabs_items[index].c_str()]
                             atIndex:index animated:NO];
    }
    const auto selected = record.tabs_items.empty()
                              ? -1
                              : static_cast<NSInteger>(std::clamp<long long>(
                                    static_cast<long long>(record.tabs_selected), 0,
                                    static_cast<long long>(record.tabs_items.size() - 1)));
    record.tabs_selected = selected < 0 ? 0.0 : static_cast<double>(selected);
    tabs.selectedSegmentIndex = selected;
    NSLog(@"ios.ui.tabs.state surface=%s selected=%ld items=%lu",
          record.surface.c_str(), static_cast<long>(selected),
          static_cast<unsigned long>(record.tabs_items.size()));
  }

  void closePicker() {
    if (picker_overlay_ != nil) [picker_overlay_ removeFromSuperview];
    picker_overlay_ = nil;
    picker_delegate_ = nil;
    picker_surface_.clear();
    picker_node_.clear();
    picker_pending_selection_ = 0;
  }

  void confirmPicker() {
    const auto key = nodeKey(picker_surface_, picker_node_);
    auto found = nodes_.find(key);
    if (found == nodes_.end() || found->second.picker_range.empty()) {
      closePicker();
      return;
    }
    auto &record = found->second;
    const auto selected = std::clamp<NSInteger>(
        picker_pending_selection_, 0,
        static_cast<NSInteger>(record.picker_range.size() - 1));
    record.picker_selected = static_cast<double>(selected);
    const auto value = record.picker_range[static_cast<std::size_t>(selected)];
    updatePickerTitle(record);
    core::RuntimeValue::Object payload;
    auto selected_value = core::RuntimeValue::finite_number(record.picker_selected);
    if (selected_value) payload.emplace("selected", std::move(selected_value).value());
    auto text_value = core::RuntimeValue::utf8_string(value);
    if (text_value) payload.emplace("value", std::move(text_value).value());
    NSLog(@"ios.ui.picker.confirm surface=%s node=%s selected=%ld value=%s",
          picker_surface_.c_str(), picker_node_.c_str(), static_cast<long>(selected),
          value.c_str());
    dispatchInput(picker_surface_, picker_node_, core::package::EventType::kChange,
                  std::move(payload));
    closePicker();
  }

  void openPickerFor(const std::string &surface, const std::string &node) {
    auto found = nodes_.find(nodeKey(surface, node));
    if (found == nodes_.end() || found->second.picker_range.empty() || root_ == nil) return;
    closePicker();
    auto &record = found->second;
    picker_surface_ = surface;
    picker_node_ = node;
    picker_pending_selection_ = pickerIndex(record);

    UIView *overlay = [[UIView alloc] initWithFrame:root_.bounds];
    overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    overlay.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.18];
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(
        0, std::max<CGFloat>(0, root_.bounds.size.height - 270),
        root_.bounds.size.width, 270)];
    panel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    panel.backgroundColor = UIColor.whiteColor;
    UIPickerView *picker = [[UIPickerView alloc] initWithFrame:CGRectMake(
        0, 44, panel.bounds.size.width, panel.bounds.size.height - 44)];
    picker.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    QuickAppPickerDelegate *delegate = [QuickAppPickerDelegate new];
    NSMutableArray<NSString *> *items = [NSMutableArray arrayWithCapacity:record.picker_range.size()];
    for (const auto &item : record.picker_range) {
      [items addObject:[NSString stringWithUTF8String:item.c_str()]];
    }
    delegate.items = items;
    IOSGateway *strongSelf = this;
    delegate.selectionChanged = ^(NSInteger row) {
      if (strongSelf) strongSelf->picker_pending_selection_ = row;
    };
    picker.delegate = delegate;
    picker.dataSource = delegate;
    [picker selectRow:picker_pending_selection_ inComponent:0 animated:NO];
    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem];
    cancel.frame = CGRectMake(12, 4, 80, 36);
    [cancel setTitle:@"取消" forState:UIControlStateNormal];
    UIButton *done = [UIButton buttonWithType:UIButtonTypeSystem];
    done.frame = CGRectMake(panel.bounds.size.width - 92, 4, 80, 36);
    done.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [done setTitle:@"确定" forState:UIControlStateNormal];
    QuickAppControlAction *cancelAction = [QuickAppControlAction new];
    cancelAction.action = ^{ if (strongSelf) strongSelf->closePicker(); };
    QuickAppControlAction *doneAction = [QuickAppControlAction new];
    doneAction.action = ^{ if (strongSelf) strongSelf->confirmPicker(); };
    objc_setAssociatedObject(cancel, "quickapp.picker.cancel", cancelAction,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(done, "quickapp.picker.done", doneAction,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [cancel addTarget:cancelAction action:@selector(invoke) forControlEvents:UIControlEventTouchUpInside];
    [done addTarget:doneAction action:@selector(invoke) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:cancel];
    [panel addSubview:done];
    [panel addSubview:picker];
    [overlay addSubview:panel];
    [root_ addSubview:overlay];
    [root_ bringSubviewToFront:overlay];
    picker_overlay_ = overlay;
    picker_delegate_ = delegate;
    NSLog(@"ios.ui.picker.open surface=%s node=%s options=%lu selected=%ld",
          surface.c_str(), node.c_str(), static_cast<unsigned long>(record.picker_range.size()),
          static_cast<long>(picker_pending_selection_));
  }

  void applySliderConfiguration(NodeRecord &record) {
    if (![record.view isKindOfClass:UISlider.class] ||
        !std::isfinite(record.slider_min) || !std::isfinite(record.slider_max) ||
        record.slider_max <= record.slider_min) return;
    UISlider *slider = static_cast<UISlider *>(record.view);
    slider.minimumValue = static_cast<float>(record.slider_min);
    slider.maximumValue = static_cast<float>(record.slider_max);
    const auto clamped = std::clamp(record.slider_value, record.slider_min, record.slider_max);
    slider.value = static_cast<float>(clamped);
  }

  UIView *makeView(core::package::HostComponentType type,
                   const std::string &surface, const std::string &node) {
    UIView *view = nil;
    if (type == core::package::HostComponentType::kText) {
      UILabel *label = [UILabel new];
      label.textColor = UIColor.blackColor;
      label.font = [UIFont systemFontOfSize:14.0];
      label.numberOfLines = 1;
      label.lineBreakMode = NSLineBreakByTruncatingTail;
      label.adjustsFontSizeToFitWidth = YES;
      label.minimumScaleFactor = 0.65;
      view = label;
    } else if (type == core::package::HostComponentType::kButton) {
      UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
      [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
      button.titleLabel.font = [UIFont systemFontOfSize:14.0];
      button.titleLabel.adjustsFontSizeToFitWidth = YES;
      button.titleLabel.minimumScaleFactor = 0.65;
      button.backgroundColor = UIColor.greenColor;
      IOSGateway *strongSelf = this;
      const std::string event_surface = surface;
      const std::string event_node = node;
      QuickAppButtonAction *target = [QuickAppButtonAction new];
      target.action = ^{
        if (strongSelf) strongSelf->dispatchClick(event_surface, event_node);
      };
      objc_setAssociatedObject(button, "quickapp.action", target,
                               OBJC_ASSOCIATION_RETAIN_NONATOMIC);
      [button addTarget:target action:@selector(invoke) forControlEvents:UIControlEventTouchUpInside];
      button.userInteractionEnabled = YES;
      button.enabled = YES;
      NSLog(@"ios.ui.button.created surface=%s node=%s text=<pending>",
            surface.c_str(), node.c_str());
      view = button;
    } else if (type == core::package::HostComponentType::kImage) {
      UIImageView *image = [UIImageView new];
      image.contentMode = UIViewContentModeScaleAspectFit;
      image.clipsToBounds = YES;
      image.userInteractionEnabled = NO;
      view = image;
    } else if (type == core::package::HostComponentType::kInput) {
      UITextField *input = [UITextField new];
      input.borderStyle = UITextBorderStyleRoundedRect;
      input.userInteractionEnabled = YES;
      IOSGateway *strongSelf = this;
      const std::string event_surface = surface;
      const std::string event_node = node;
      QuickAppControlAction *editing = [QuickAppControlAction new];
      editing.action = ^{
        if (strongSelf) {
          strongSelf->dispatchTextEvent(event_surface, event_node,
                                        core::package::EventType::kInput,
                                        input.text ?: @"");
        }
      };
      objc_setAssociatedObject(input, "quickapp.input.editing", editing,
                               OBJC_ASSOCIATION_RETAIN_NONATOMIC);
      [input addTarget:editing action:@selector(invoke)
         forControlEvents:UIControlEventEditingChanged];
      QuickAppControlAction *began = [QuickAppControlAction new];
      began.action = ^{
        if (strongSelf) {
          strongSelf->dispatchInput(event_surface, event_node,
                                    core::package::EventType::kFocus, {});
        }
      };
      objc_setAssociatedObject(input, "quickapp.input.began", began,
                               OBJC_ASSOCIATION_RETAIN_NONATOMIC);
      [input addTarget:began action:@selector(invoke)
         forControlEvents:UIControlEventEditingDidBegin];
      QuickAppControlAction *ended = [QuickAppControlAction new];
      ended.action = ^{
        if (strongSelf) {
          strongSelf->dispatchTextEvent(event_surface, event_node,
                                        core::package::EventType::kChange,
                                        input.text ?: @"");
        }
      };
      objc_setAssociatedObject(input, "quickapp.input.ended", ended,
                               OBJC_ASSOCIATION_RETAIN_NONATOMIC);
      [input addTarget:ended action:@selector(invoke)
         forControlEvents:UIControlEventEditingDidEnd];
      [input addTarget:ended action:@selector(invoke)
         forControlEvents:UIControlEventEditingDidEndOnExit];
      view = input;
    } else if (type == core::package::HostComponentType::kSwitch) {
      UISwitch *toggle = [UISwitch new];
      toggle.userInteractionEnabled = YES;
      IOSGateway *strongSelf = this;
      const std::string event_surface = surface;
      const std::string event_node = node;
      QuickAppControlAction *changed = [QuickAppControlAction new];
      changed.action = ^{
        if (strongSelf) {
          strongSelf->dispatchSwitchEvent(event_surface, event_node, toggle.isOn);
        }
      };
      objc_setAssociatedObject(toggle, "quickapp.switch.changed", changed,
                               OBJC_ASSOCIATION_RETAIN_NONATOMIC);
      [toggle addTarget:changed action:@selector(invoke)
       forControlEvents:UIControlEventValueChanged];
      view = toggle;
    } else if (type == core::package::HostComponentType::kSlider) {
      UISlider *slider = [UISlider new];
      slider.userInteractionEnabled = YES;
      IOSGateway *strongSelf = this;
      const std::string event_surface = surface;
      const std::string event_node = node;
      QuickAppControlAction *changed = [QuickAppControlAction new];
      changed.action = ^{
        if (strongSelf) {
          auto found = strongSelf->nodes_.find(strongSelf->nodeKey(event_surface, event_node));
          if (found == strongSelf->nodes_.end()) return;
          auto &record = found->second;
          const auto raw = static_cast<double>(slider.value);
          const auto step = record.slider_step > 0 && std::isfinite(record.slider_step)
                                ? record.slider_step : 1.0;
          auto quantized = record.slider_min +
              std::round((raw - record.slider_min) / step) * step;
          quantized = std::clamp(quantized, record.slider_min, record.slider_max);
          record.slider_value = quantized;
          slider.value = static_cast<float>(quantized);
          NSLog(@"ios.ui.slider.change surface=%s node=%s value=%.3f", event_surface.c_str(),
                event_node.c_str(), quantized);
          strongSelf->dispatchSliderEvent(event_surface, event_node, quantized);
        }
      };
      objc_setAssociatedObject(slider, "quickapp.slider.changed", changed,
                               OBJC_ASSOCIATION_RETAIN_NONATOMIC);
      [slider addTarget:changed action:@selector(invoke) forControlEvents:UIControlEventValueChanged];
      view = slider;
    } else if (type == core::package::HostComponentType::kPicker) {
      UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
      button.userInteractionEnabled = YES;
      button.titleLabel.font = [UIFont systemFontOfSize:14.0];
      button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
      IOSGateway *strongSelf = this;
      const std::string event_surface = surface;
      const std::string event_node = node;
      QuickAppButtonAction *target = [QuickAppButtonAction new];
      target.action = ^{
        if (strongSelf) strongSelf->openPickerFor(event_surface, event_node);
      };
      objc_setAssociatedObject(button, "quickapp.picker.action", target,
                               OBJC_ASSOCIATION_RETAIN_NONATOMIC);
      [button addTarget:target action:@selector(invoke) forControlEvents:UIControlEventTouchUpInside];
      NSLog(@"ios.ui.picker.created surface=%s node=%s", surface.c_str(), node.c_str());
      view = button;
    } else if (type == core::package::HostComponentType::kTabs) {
      UISegmentedControl *tabs = [[UISegmentedControl alloc] initWithItems:@[]];
      tabs.userInteractionEnabled = YES;
      tabs.apportionsSegmentWidthsByContent = YES;
      IOSGateway *strongSelf = this;
      const std::string event_surface = surface;
      const std::string event_node = node;
      QuickAppControlAction *changed = [QuickAppControlAction new];
      changed.action = ^{
        if (!strongSelf) return;
        auto found = strongSelf->nodes_.find(strongSelf->nodeKey(event_surface, event_node));
        if (found == strongSelf->nodes_.end()) return;
        const auto index = tabs.selectedSegmentIndex;
        if (index < 0 || index >= static_cast<NSInteger>(found->second.tabs_items.size())) return;
        found->second.tabs_selected = static_cast<double>(index);
        const auto &item = found->second.tabs_items[static_cast<std::size_t>(index)];
        NSLog(@"ios.ui.tabs.change surface=%s node=%s index=%ld value=%s",
              event_surface.c_str(), event_node.c_str(), static_cast<long>(index),
              item.c_str());
        strongSelf->dispatchTabsEvent(event_surface, event_node, index, item);
      };
      objc_setAssociatedObject(tabs, "quickapp.tabs.changed", changed,
                               OBJC_ASSOCIATION_RETAIN_NONATOMIC);
      [tabs addTarget:changed action:@selector(invoke)
       forControlEvents:UIControlEventValueChanged];
      NSLog(@"ios.ui.tabs.created surface=%s node=%s", surface.c_str(), node.c_str());
      view = tabs;
    } else if (type == core::package::HostComponentType::kList) {
      UIView *list = [UIView new];
      list.clipsToBounds = YES;
      list.userInteractionEnabled = YES;
      view = list;
    } else if (type == core::package::HostComponentType::kScroll) {
      UIScrollView *scroll = [UIScrollView new];
      scroll.userInteractionEnabled = YES;
      scroll.alwaysBounceVertical = YES;
      scroll.directionalLockEnabled = YES;
      scroll.showsVerticalScrollIndicator = YES;
      IOSGateway *strongSelf = this;
      const std::string event_surface = surface;
      const std::string event_node = node;
      QuickAppScrollDelegate *delegate = [QuickAppScrollDelegate new];
      delegate.didScroll = ^{
        if (strongSelf) strongSelf->handleScrollDidScroll(event_surface, event_node, scroll);
      };
      delegate.didEnd = ^{
        if (strongSelf) strongSelf->handleScrollDidEnd(event_surface, event_node, scroll);
      };
      scroll.delegate = delegate;
      objc_setAssociatedObject(scroll, "quickapp.scroll.delegate", delegate,
                               OBJC_ASSOCIATION_RETAIN_NONATOMIC);
      NSLog(@"ios.ui.scroll.created surface=%s node=%s", surface.c_str(), node.c_str());
      view = scroll;
    } else if (type == core::package::HostComponentType::kVideo) {
      AVPlayerViewController *controller = [AVPlayerViewController new];
      controller.showsPlaybackControls = YES;
      controller.view.backgroundColor = [UIColor colorWithRed:0.125
                                                         green:0.145
                                                          blue:0.17
                                                         alpha:1.0];
      objc_setAssociatedObject(controller.view, "quickapp.video.controller", controller,
                               OBJC_ASSOCIATION_RETAIN_NONATOMIC);
      NSLog(@"ios.ui.video.created surface=%s node=%s", surface.c_str(), node.c_str());
      view = controller.view;
    } else if (type == core::package::HostComponentType::kView) {
      view = [UIView new];
    }
    view.accessibilityIdentifier = [NSString stringWithUTF8String:node.c_str()];
    return view;
  }

  bool applyOperation(const std::string &surface, UIView *surface_view,
                      const core::render::MountOperation &operation) {
    return std::visit([&](const auto &value) -> bool {
      using Value = std::decay_t<decltype(value)>;
      if constexpr (std::is_same_v<Value, core::render::CreateHost>) {
        const auto key = nodeKey(surface, value.node_id.wire());
        if (nodes_.contains(key)) return false;
        UIView *view = makeView(value.type, surface, value.node_id.wire());
        if (view == nil) return false;
        [surface_view addSubview:view];
        NodeRecord record{view, surface};
        if (value.type == core::package::HostComponentType::kVideo) {
          record.video_controller = static_cast<AVPlayerViewController *>(
              objc_getAssociatedObject(view, "quickapp.video.controller"));
          objc_setAssociatedObject(view, "quickapp.video.controller", nil,
                                   OBJC_ASSOCIATION_RETAIN_NONATOMIC);
          if (record.video_controller == nil) return false;
        }
        nodes_[key] = std::move(record);
        return true;
      } else if constexpr (std::is_same_v<Value, core::render::SetHostProp>) {
        auto found = nodes_.find(nodeKey(surface, value.node_id.wire()));
        if (found == nodes_.end()) return false;
        UIView *view = found->second.view;
        if (value.name == "enabled") {
          const auto *enabled = std::get_if<bool>(&value.value);
          if (!enabled) return false;
          view.userInteractionEnabled = *enabled;
          if ([view isKindOfClass:UIControl.class]) static_cast<UIControl *>(view).enabled = *enabled;
          return true;
        }
        if (value.name == "text") {
          const auto *text = std::get_if<std::string>(&value.value);
          if (!text) return false;
          if ([view isKindOfClass:UILabel.class]) static_cast<UILabel *>(view).text = [NSString stringWithUTF8String:text->c_str()];
          else if ([view isKindOfClass:UIButton.class]) [static_cast<UIButton *>(view) setTitle:[NSString stringWithUTF8String:text->c_str()] forState:UIControlStateNormal];
          else if ([view isKindOfClass:UITextField.class]) static_cast<UITextField *>(view).text = [NSString stringWithUTF8String:text->c_str()];
          else return false;
          return true;
        }
        if (value.name == "value") {
          if ([view isKindOfClass:UISlider.class]) {
            const auto *number = std::get_if<double>(&value.value);
            if (!number || !std::isfinite(*number)) return false;
            found->second.slider_value = *number;
            applySliderConfiguration(found->second);
            return true;
          }
          const auto *text = std::get_if<std::string>(&value.value);
          if (!text || ![view isKindOfClass:UITextField.class]) return false;
          static_cast<UITextField *>(view).text = [NSString stringWithUTF8String:text->c_str()];
          return true;
        }
        if (value.name == "min" || value.name == "max" || value.name == "step") {
          if (![view isKindOfClass:UISlider.class]) return false;
          const auto *number = std::get_if<double>(&value.value);
          if (!number || !std::isfinite(*number)) return false;
          if (value.name == "min") found->second.slider_min = *number;
          else if (value.name == "max") found->second.slider_max = *number;
          else if (*number <= 0) return false;
          else found->second.slider_step = *number;
          applySliderConfiguration(found->second);
          return true;
        }
        if (value.name == "mode") {
          if (![view isKindOfClass:UIButton.class]) return false;
          const auto *mode = std::get_if<std::string>(&value.value);
          return mode != nullptr && *mode == "text";
        }
        if (value.name == "range") {
          if (![view isKindOfClass:UIButton.class]) return false;
          const auto *range = std::get_if<std::string>(&value.value);
          if (!range) return false;
          auto parsed = parsePickerRange(*range);
          if (parsed.empty()) return false;
          found->second.picker_range = std::move(parsed);
          updatePickerTitle(found->second);
          return true;
        }
        if (value.name == "selected") {
          const auto *selected = std::get_if<double>(&value.value);
          if (!selected || !std::isfinite(*selected) ||
              *selected < 0 || std::floor(*selected) != *selected) return false;
          if ([view isKindOfClass:UIButton.class]) {
            found->second.picker_selected = *selected;
            updatePickerTitle(found->second);
          } else if ([view isKindOfClass:UISegmentedControl.class]) {
            found->second.tabs_selected = *selected;
            updateTabsConfiguration(found->second);
          } else {
            return false;
          }
          return true;
        }
        if (value.name == "items") {
          if (![view isKindOfClass:UISegmentedControl.class]) return false;
          const auto *items = std::get_if<std::string>(&value.value);
          if (!items) return false;
          auto parsed = parsePickerRange(*items);
          if (parsed.empty()) return false;
          found->second.tabs_items = std::move(parsed);
          updateTabsConfiguration(found->second);
          return true;
        }
        if (value.name == "checked") {
          const auto *checked = std::get_if<bool>(&value.value);
          if (!checked || ![view isKindOfClass:UISwitch.class]) return false;
          [static_cast<UISwitch *>(view) setOn:*checked animated:NO];
          return true;
        }
        if (value.name == "placeholder") {
          const auto *text = std::get_if<std::string>(&value.value);
          if (!text || ![view isKindOfClass:UITextField.class]) return false;
          static_cast<UITextField *>(view).placeholder = [NSString stringWithUTF8String:text->c_str()];
          return true;
        }
        if (value.name == "src") {
          const auto *path = std::get_if<std::string>(&value.value);
          if (!path) return false;
          if (found->second.video_controller != nil) {
            found->second.video_src = *path;
            configureVideo(surface, value.node_id.wire(), found->second);
            return true;
          }
          if (![view isKindOfClass:UIImageView.class]) return false;
          ResourceBytes bytes;
          {
            std::lock_guard lock(mutex_);
            auto resource = resources_.find(*path);
            if (resource != resources_.end()) bytes = resource->second;
          }
          if (!bytes || bytes->empty()) return false;
          NSData *data = [NSData dataWithBytes:bytes->data() length:bytes->size()];
          UIImage *image = [UIImage imageWithData:data scale:UIScreen.mainScreen.scale];
          if (image == nil) return false;
          static_cast<UIImageView *>(view).image = image;
          return true;
        }
        if (value.name == "poster") {
          const auto *path = std::get_if<std::string>(&value.value);
          if (!path || found->second.video_controller == nil) return false;
          found->second.video_poster = *path;
          applyVideoPoster(found->second);
          return true;
        }
        if (value.name == "autoplay" || value.name == "controls" ||
            value.name == "muted") {
          const auto *enabled = std::get_if<bool>(&value.value);
          if (!enabled || found->second.video_controller == nil) return false;
          if (value.name == "autoplay") found->second.video_autoplay = *enabled;
          else if (value.name == "controls") {
            found->second.video_controls = *enabled;
            found->second.video_controller.showsPlaybackControls = *enabled;
          } else {
            found->second.video_muted = *enabled;
            if (found->second.video_player != nil) found->second.video_player.muted = *enabled;
          }
          return true;
        }
        if (value.name == "color" || value.name == "backgroundColor") {
          const auto *color = std::get_if<std::string>(&value.value);
          UIColor *uiColor = color ? colorFromString(*color) : nil;
          if (!uiColor) return false;
          if (value.name == "backgroundColor") {
            view.backgroundColor = uiColor;
            if ([view isKindOfClass:UISegmentedControl.class]) {
              UISegmentedControl *tabs = static_cast<UISegmentedControl *>(view);
              tabs.selectedSegmentTintColor = UIColor.whiteColor;
              [tabs setTitleTextAttributes:@{NSForegroundColorAttributeName: uiColor}
                                   forState:UIControlStateSelected];
            }
          }
          else if ([view isKindOfClass:UILabel.class]) static_cast<UILabel *>(view).textColor = uiColor;
          else if ([view isKindOfClass:UIButton.class]) [static_cast<UIButton *>(view) setTitleColor:uiColor forState:UIControlStateNormal];
          else if ([view isKindOfClass:UITextField.class]) static_cast<UITextField *>(view).textColor = uiColor;
          else if ([view isKindOfClass:UISegmentedControl.class]) {
            NSDictionary *attributes = @{NSForegroundColorAttributeName: uiColor};
            UISegmentedControl *tabs = static_cast<UISegmentedControl *>(view);
            [tabs setTitleTextAttributes:attributes forState:UIControlStateNormal];
            UIColor *selectedColor = view.backgroundColor ?: uiColor;
            [tabs setTitleTextAttributes:@{NSForegroundColorAttributeName: selectedColor}
                                 forState:UIControlStateSelected];
          }
          else return false;
          return true;
        }
        if (value.name == "fontSize") {
          const auto *size = std::get_if<double>(&value.value);
          if (!size || *size <= 0) return false;
          if ([view isKindOfClass:UILabel.class]) static_cast<UILabel *>(view).font = [UIFont systemFontOfSize:*size];
          else if ([view isKindOfClass:UIButton.class]) static_cast<UIButton *>(view).titleLabel.font = [UIFont systemFontOfSize:*size];
          else return false;
          return true;
        }
        if (value.name == "textAlign") {
          const auto *alignment = std::get_if<std::string>(&value.value);
          if (!alignment) return false;
          NSTextAlignment resolved = NSTextAlignmentLeft;
          if (*alignment == "center") resolved = NSTextAlignmentCenter;
          else if (*alignment == "right") resolved = NSTextAlignmentRight;
          else if (*alignment != "left") return false;
          if ([view isKindOfClass:UILabel.class]) {
            static_cast<UILabel *>(view).textAlignment = resolved;
          } else if ([view isKindOfClass:UIButton.class]) {
            static_cast<UIButton *>(view).contentHorizontalAlignment =
                resolved == NSTextAlignmentCenter
                    ? UIControlContentHorizontalAlignmentCenter
                    : resolved == NSTextAlignmentRight
                          ? UIControlContentHorizontalAlignmentRight
                          : UIControlContentHorizontalAlignmentLeft;
          } else if ([view isKindOfClass:UITextField.class]) {
            static_cast<UITextField *>(view).textAlignment = resolved;
          } else {
            return false;
          }
          return true;
        }
        if (value.name == "borderRadius") {
          const auto *radius = std::get_if<double>(&value.value);
          if (!radius || *radius < 0 || !std::isfinite(*radius)) return false;
          view.layer.cornerRadius = static_cast<CGFloat>(*radius);
          view.clipsToBounds = true;
          return true;
        }
        return false;
      } else if constexpr (std::is_same_v<Value, core::render::SetHostLayout>) {
        auto found = nodes_.find(nodeKey(surface, value.node_id.wire()));
        if (found == nodes_.end()) return false;
        const auto &rect = value.rect;
        found->second.view.frame = CGRectMake(rect.x, rect.y, rect.width, rect.height);
        if ([found->second.view isKindOfClass:UIScrollView.class]) {
          UIScrollView *scroll = static_cast<UIScrollView *>(found->second.view);
          scroll.contentSize = CGSizeMake(std::max<CGFloat>(rect.width, scroll.contentSize.width),
                                           std::max<CGFloat>(rect.height, scroll.contentSize.height));
          NSLog(@"ios.ui.scroll.layout surface=%s node=%s frame=<%.1f,%.1f,%.1f,%.1f> content=<%.1f,%.1f>",
                surface.c_str(), value.node_id.wire().c_str(), rect.x, rect.y,
                rect.width, rect.height, scroll.contentSize.width, scroll.contentSize.height);
        }
        updateScrollContentSize(found->second.view);
        if ([found->second.view isKindOfClass:UIButton.class]) {
          NSString *title = static_cast<UIButton *>(found->second.view).currentTitle ?: @"";
          NSLog(@"ios.ui.button.layout surface=%s node=%s frame=<%.1f,%.1f,%.1f,%.1f> text=%s enabled=%d",
                surface.c_str(), value.node_id.wire().c_str(), rect.x, rect.y,
                rect.width, rect.height, title.UTF8String,
                          static_cast<UIButton *>(found->second.view).enabled ? 1 : 0);
        } else if ([found->second.view isKindOfClass:UISlider.class]) {
          NSLog(@"ios.ui.slider.layout surface=%s node=%s frame=<%.1f,%.1f,%.1f,%.1f>",
                surface.c_str(), value.node_id.wire().c_str(), rect.x, rect.y,
                rect.width, rect.height);
        } else if ([found->second.view isKindOfClass:UISegmentedControl.class]) {
          NSLog(@"ios.ui.tabs.layout surface=%s node=%s frame=<%.1f,%.1f,%.1f,%.1f>",
                surface.c_str(), value.node_id.wire().c_str(), rect.x, rect.y,
                rect.width, rect.height);
        } else if (found->second.video_controller != nil) {
          NSLog(@"ios.ui.video.layout surface=%s node=%s frame=<%.1f,%.1f,%.1f,%.1f>",
                surface.c_str(), value.node_id.wire().c_str(), rect.x, rect.y,
                rect.width, rect.height);
        }
        return true;
      } else if constexpr (std::is_same_v<Value, core::render::InsertHostChild>) {
        auto child = nodes_.find(nodeKey(surface, value.node_id.wire()));
        auto parent = nodes_.find(nodeKey(surface, value.parent_node_id.wire()));
        if (child == nodes_.end() || parent == nodes_.end()) return false;
        [child->second.view removeFromSuperview];
        [parent->second.view insertSubview:child->second.view
                              atIndex:std::min<std::size_t>(value.index,
                                                           parent->second.view.subviews.count)];
        updateScrollContentSize(parent->second.view);
        return true;
      } else if constexpr (std::is_same_v<Value, core::render::MoveHost>) {
        auto child = nodes_.find(nodeKey(surface, value.node_id.wire()));
        auto parent = nodes_.find(nodeKey(surface, value.new_parent_node_id.wire()));
        if (child == nodes_.end() || parent == nodes_.end()) return false;
        [child->second.view removeFromSuperview];
        [parent->second.view insertSubview:child->second.view
                              atIndex:std::min<std::size_t>(value.index,
                                                           parent->second.view.subviews.count)];
        updateScrollContentSize(parent->second.view);
        return true;
      } else if constexpr (std::is_same_v<Value, core::render::RemoveHost>) {
        auto found = nodes_.find(nodeKey(surface, value.node_id.wire()));
        if (found == nodes_.end()) return false;
        UIView *removed = found->second.view;
        [removed removeFromSuperview];
        for (auto it = nodes_.begin(); it != nodes_.end();) {
          if (it->second.surface == surface &&
              (it->second.view == removed || [it->second.view isDescendantOfView:removed])) {
            removeVideoObservers(it->second);
            it->second.video_player = nil;
            it->second.video_item = nil;
            if (it->second.video_controller != nil) it->second.video_controller.player = nil;
            it = nodes_.erase(it);
          } else {
            ++it;
          }
        }
        return true;
      }
    }, operation);
  }

  void removeNodes(const std::string &surface) {
    if (picker_surface_ == surface) closePicker();
    for (auto it = nodes_.begin(); it != nodes_.end();) {
      if (it->second.surface == surface) {
        removeVideoObservers(it->second);
        it->second.video_player = nil;
        it->second.video_item = nil;
        if (it->second.video_controller != nil) it->second.video_controller.player = nil;
        [it->second.view removeFromSuperview];
        it = nodes_.erase(it);
      } else {
        ++it;
      }
    }
  }

  std::string nodeKey(const std::string &surface, const std::string &node) const {
    return surface + "\0" + node;
  }

  void completeSurface(const core::RequestId &request, int kind, std::string target,
                       std::optional<std::string> source, std::optional<std::string> reveal,
                       int visibility, bool completed, std::optional<std::string> code,
                       std::optional<std::string> message) {
    std::shared_ptr<RuntimeSpine> spine;
    {
      std::lock_guard lock(mutex_);
      spine = spine_.lock();
    }
    if (spine) spine->acceptSurfaceResult(request.wire(), kind, std::move(target),
                                          std::move(source), std::move(reveal), visibility,
                                          completed, std::move(code), std::move(message));
  }

  void completeMount(const core::render::MountTransaction &transaction, bool mounted,
                     std::optional<std::string> code, std::optional<std::string> message) {
    std::shared_ptr<RuntimeSpine> spine;
    {
      std::lock_guard lock(mutex_);
      spine = spine_.lock();
    }
    if (spine) spine->acceptMountResult(transaction.surface_id.wire(), transaction.revision,
                                        transaction.mount_attempt_id.wire(),
                                        core::render::render_source_wire(transaction.source_id),
                                        mounted, std::move(code), std::move(message));
  }

  UIView *root_;
  mutable std::mutex mutex_;
  std::weak_ptr<RuntimeSpine> spine_;
  std::atomic<bool> open_{true};
  std::atomic<std::size_t> pending_callbacks_{0};
  std::map<std::string, __strong UIView *> surfaces_;
  std::map<std::string, NodeRecord> nodes_;
  std::map<std::string, __strong UIView *> feature_views_;
  std::map<std::string, ResourceBytes> resources_;
  std::map<std::string, std::string> file_store_{{"private/platform-state.txt",
                                                  "ios-private-ready"}};
  std::map<std::string, std::string> titles_;
  std::map<std::string, std::pair<std::string, std::string>> meta_;
  __strong UIView *picker_overlay_{nil};
  __strong QuickAppPickerDelegate *picker_delegate_{nil};
  std::string picker_surface_;
  std::string picker_node_;
  NSInteger picker_pending_selection_{0};
};

}  // namespace quickapp::ios

namespace quickapp::ios {

std::shared_ptr<platform::Gateway> makeGateway(UIView *root_view) noexcept {
  try {
    return std::make_shared<IOSGateway>(root_view);
  } catch (...) {
    return nullptr;
  }
}

void bindGateway(const std::shared_ptr<platform::Gateway> &gateway,
                 const std::shared_ptr<RuntimeSpine> &spine) noexcept {
  if (gateway) std::static_pointer_cast<IOSGateway>(gateway)->bind(spine);
}

void closeGateway(const std::shared_ptr<platform::Gateway> &gateway) noexcept {
  if (gateway) std::static_pointer_cast<IOSGateway>(gateway)->close();
}

void setGatewayResources(
    const std::shared_ptr<platform::Gateway> &gateway,
    std::map<std::string, ResourceBytes> resources) noexcept {
  if (gateway) {
    std::static_pointer_cast<IOSGateway>(gateway)->setResources(std::move(resources));
  }
}

bool controlVideo(const std::shared_ptr<platform::Gateway> &gateway,
                  std::string surface_id, std::string node_id,
                  std::string action, double position_seconds) noexcept {
  if (!gateway) return false;
  return std::static_pointer_cast<IOSGateway>(gateway)->controlVideo(
      surface_id, node_id, action, position_seconds);
}

bool controlTabs(const std::shared_ptr<platform::Gateway> &gateway,
                 std::string surface_id, std::string node_id,
                 std::int64_t index) noexcept {
  if (!gateway) return false;
  return std::static_pointer_cast<IOSGateway>(gateway)->controlTabs(
      surface_id, node_id, index);
}

bool controlClick(const std::shared_ptr<platform::Gateway> &gateway,
                  std::string surface_id, std::string node_id) noexcept {
  if (!gateway) return false;
  return std::static_pointer_cast<IOSGateway>(gateway)->controlClick(
      surface_id, node_id);
}

bool controlInput(const std::shared_ptr<platform::Gateway> &gateway,
                  std::string surface_id, std::string node_id,
                  std::string value) noexcept {
  if (!gateway) return false;
  return std::static_pointer_cast<IOSGateway>(gateway)->controlInput(
      surface_id, node_id, value);
}

bool controlSwitch(const std::shared_ptr<platform::Gateway> &gateway,
                   std::string surface_id, std::string node_id,
                   bool checked) noexcept {
  if (!gateway) return false;
  return std::static_pointer_cast<IOSGateway>(gateway)->controlSwitch(
      surface_id, node_id, checked);
}

bool controlSlider(const std::shared_ptr<platform::Gateway> &gateway,
                   std::string surface_id, std::string node_id,
                   double value) noexcept {
  if (!gateway) return false;
  return std::static_pointer_cast<IOSGateway>(gateway)->controlSlider(
      surface_id, node_id, value);
}

bool controlPicker(const std::shared_ptr<platform::Gateway> &gateway,
                   std::string surface_id, std::string node_id,
                   std::int64_t index) noexcept {
  if (!gateway) return false;
  return std::static_pointer_cast<IOSGateway>(gateway)->controlPicker(
      surface_id, node_id, index);
}

bool controlScroll(const std::shared_ptr<platform::Gateway> &gateway,
                   std::string surface_id, std::string node_id,
                   double offset) noexcept {
  if (!gateway) return false;
  return std::static_pointer_cast<IOSGateway>(gateway)->controlScroll(
      surface_id, node_id, offset);
}

core::feature::Provider *featureProvider(
    const std::shared_ptr<platform::Gateway> &gateway) noexcept {
  if (!gateway) return nullptr;
  return dynamic_cast<IOSGateway *>(gateway.get());
}

}  // namespace quickapp::ios
