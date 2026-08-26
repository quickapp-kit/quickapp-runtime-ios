#import <UIKit/UIKit.h>

#include <cstdio>
#include <cstdlib>
#include <memory>
#include <string>

#include "quickapp/ios/ios_gateway.h"

@interface QuickAppRootViewController : UIViewController
@end

@implementation QuickAppRootViewController

- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = UIColor.whiteColor;
}

@end

@interface QuickAppAppDelegate : UIResponder <UIApplicationDelegate>
@end

@interface QuickAppSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, strong) QuickAppRootViewController *rootController;
@property(nonatomic, strong) UIView *runtimeHostView;
@property(nonatomic, assign) void *runtimeOpaque;
- (void)startRuntimeWithPath:(NSString *)path;
- (void)stopRuntime;
@end

@implementation QuickAppAppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  (void)application;
  (void)launchOptions;
  return YES;
}

- (UISceneConfiguration *)application:(UIApplication *)application
    configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession
                              options:(UISceneConnectionOptions *)options {
  (void)application;
  (void)connectingSceneSession;
  (void)options;
  UISceneConfiguration *configuration =
      [[UISceneConfiguration alloc] initWithName:@"QuickApp Configuration"
                                    sessionRole:UIWindowSceneSessionRoleApplication];
  configuration.delegateClass = QuickAppSceneDelegate.class;
  return configuration;
}

@end

@implementation QuickAppSceneDelegate

- (void)scene:(UIScene *)scene
    willConnectToSession:(UISceneSession *)session
                 options:(UISceneConnectionOptions *)connectionOptions {
  (void)session;
  (void)connectionOptions;
  UIWindowScene *windowScene = [scene isKindOfClass:UIWindowScene.class]
      ? static_cast<UIWindowScene *>(scene) : nil;
  if (windowScene == nil) return;
  self.rootController = [QuickAppRootViewController new];
  self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
  self.window.rootViewController = self.rootController;
  [self.window makeKeyAndVisible];

  self.runtimeHostView = [UIView new];
  self.runtimeHostView.translatesAutoresizingMaskIntoConstraints = NO;
  self.runtimeHostView.backgroundColor = UIColor.whiteColor;
  [self.rootController.view addSubview:self.runtimeHostView];
  UILayoutGuide *safeArea = self.rootController.view.safeAreaLayoutGuide;
  [NSLayoutConstraint activateConstraints:@[
    [self.runtimeHostView.leadingAnchor constraintEqualToAnchor:safeArea.leadingAnchor],
    [self.runtimeHostView.trailingAnchor constraintEqualToAnchor:safeArea.trailingAnchor],
    [self.runtimeHostView.topAnchor constraintEqualToAnchor:safeArea.topAnchor],
    [self.runtimeHostView.bottomAnchor constraintEqualToAnchor:safeArea.bottomAnchor],
  ]];

  const char *requestedName = std::getenv("QUICKAPP_RPK");
  NSString *resourceName = requestedName == nullptr
      ? @"tk-s12-lvgl-p0"
      : [NSString stringWithUTF8String:requestedName];
  NSString *path = [NSBundle.mainBundle pathForResource:resourceName ofType:@"rpk"];
  if (path == nil) {
    NSLog(@"ios.showcase.error missing RPK resource name=%@", resourceName);
    return;
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    [self startRuntimeWithPath:path];
  });
}

- (void)startRuntimeWithPath:(NSString *)path {
  [self.window layoutIfNeeded];
  [self.rootController.view layoutIfNeeded];
  [self.runtimeHostView layoutIfNeeded];
  auto gateway = quickapp::ios::makeGateway(self.runtimeHostView);
  const auto bounds = self.runtimeHostView.bounds;
  NSLog(@"ios.showcase.window.bounds=<%.1f,%.1f> root.bounds=<%.1f,%.1f>",
        self.window.bounds.size.width, self.window.bounds.size.height,
        bounds.size.width, bounds.size.height);
  auto spine = quickapp::ios::RuntimeSpine::create(
      gateway, bounds.size.width, bounds.size.height);
  if (!gateway || !spine) {
    NSLog(@"ios.a1.error runtime composition failed");
    return;
  }
  quickapp::ios::bindGateway(gateway, spine);
  self.runtimeOpaque = new std::shared_ptr<quickapp::ios::RuntimeSpine>(std::move(spine));
  (*static_cast<std::shared_ptr<quickapp::ios::RuntimeSpine> *>(self.runtimeOpaque))
      ->start(std::string(path.UTF8String));
  const char *probeModule = std::getenv("QUICKAPP_IOS_FEATURE_MODULE");
  const char *probeMethod = std::getenv("QUICKAPP_IOS_FEATURE_METHOD");
  const char *probeValue = std::getenv("QUICKAPP_IOS_FEATURE_VALUE");
  if (probeModule != nullptr && probeMethod != nullptr) {
    const std::string module(probeModule);
    const std::string method(probeMethod);
    const std::string value = probeValue == nullptr ? "" : probeValue;
    auto runtime = *static_cast<std::shared_ptr<quickapp::ios::RuntimeSpine> *>(self.runtimeOpaque);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
      const bool accepted = runtime->dispatchFeature(module, method, value);
      NSLog(@"ios.feature.probe.queued module=%s method=%s accepted=%d",
            module.c_str(), method.c_str(), accepted ? 1 : 0);
    });
  }
  if (std::getenv("QUICKAPP_IOS_FEATURE_TEARDOWN") != nullptr) {
    auto runtime = *static_cast<std::shared_ptr<quickapp::ios::RuntimeSpine> *>(self.runtimeOpaque);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
      NSLog(@"ios.feature.probe.teardown.begin");
      dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSLog(@"ios.feature.probe.teardown.worker");
        runtime->destroy();
        dispatch_async(dispatch_get_main_queue(), ^{
          NSLog(@"ios.feature.probe.teardown completed=1");
        });
      });
    });
  }
  if (std::getenv("QUICKAPP_IOS_VIDEO_ACTIONS") != nullptr) {
    const char *videoNodeValue = std::getenv("QUICKAPP_IOS_VIDEO_NODE");
    const std::string videoNode = videoNodeValue == nullptr ? "node:3" : videoNodeValue;
    auto videoGateway = gateway;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
      const bool accepted = quickapp::ios::controlVideo(
          videoGateway, "srf:1", videoNode, "play");
      NSLog(@"ios.video.probe.queued action=play accepted=%d", accepted ? 1 : 0);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
      const bool accepted = quickapp::ios::controlVideo(
          videoGateway, "srf:1", videoNode, "pause");
      NSLog(@"ios.video.probe.queued action=pause accepted=%d", accepted ? 1 : 0);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
      const bool accepted = quickapp::ios::controlVideo(
          videoGateway, "srf:1", videoNode, "seek", 1.0);
      NSLog(@"ios.video.probe.queued action=seek position=1.000 accepted=%d",
            accepted ? 1 : 0);
    });
  }
  if (std::getenv("QUICKAPP_IOS_VIDEO_FORCE_FAILURE") != nullptr) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
      NSLog(@"ios.video.probe.failure expected=1");
    });
  }
  if (std::getenv("QUICKAPP_IOS_TABS_ACTIONS") != nullptr) {
    const char *tabsNodeValue = std::getenv("QUICKAPP_IOS_TABS_NODE");
    const std::string tabsNode = tabsNodeValue == nullptr ? "node:4" : tabsNodeValue;
    auto tabsGateway = gateway;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
      const bool accepted = quickapp::ios::controlTabs(
          tabsGateway, "srf:1", tabsNode, 1);
      NSLog(@"ios.tabs.probe.queued index=1 accepted=%d", accepted ? 1 : 0);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
      const bool accepted = quickapp::ios::controlTabs(
          tabsGateway, "srf:1", tabsNode, 1);
      NSLog(@"ios.tabs.probe.queued index=1 repeat=1 accepted=%d", accepted ? 1 : 0);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
      const bool accepted = quickapp::ios::controlTabs(
          tabsGateway, "srf:1", tabsNode, 2);
      NSLog(@"ios.tabs.probe.queued index=2 accepted=%d", accepted ? 1 : 0);
    });
  }
  if (std::getenv("QUICKAPP_IOS_CONTROLS_ACTIONS") != nullptr) {
    auto controlsGateway = gateway;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
      const bool accepted = quickapp::ios::controlInput(
          controlsGateway, "srf:1", "node:4", "Agent");
      NSLog(@"ios.controls.probe.input accepted=%d", accepted ? 1 : 0);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
      const bool accepted = quickapp::ios::controlSwitch(
          controlsGateway, "srf:1", "node:7", false);
      NSLog(@"ios.controls.probe.switch accepted=%d", accepted ? 1 : 0);
    });
  }
  if (std::getenv("QUICKAPP_IOS_CONTROLS_002_ACTIONS") != nullptr) {
    auto controlsGateway = gateway;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
      const bool accepted = quickapp::ios::controlSlider(
          controlsGateway, "srf:1", "node:4", 75.0);
      NSLog(@"ios.controls-002.probe.slider accepted=%d", accepted ? 1 : 0);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
      const bool accepted = quickapp::ios::controlPicker(
          controlsGateway, "srf:1", "node:7", 2);
      NSLog(@"ios.controls-002.probe.picker accepted=%d", accepted ? 1 : 0);
    });
  }
  if (std::getenv("QUICKAPP_IOS_LIST_ACTIONS") != nullptr) {
    auto listGateway = gateway;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
      const bool accepted = quickapp::ios::controlScroll(
          listGateway, "srf:1", "node:4", 180.0);
      NSLog(@"ios.list.probe.scroll accepted=%d", accepted ? 1 : 0);
    });
  }
  if (std::getenv("QUICKAPP_IOS_COMMERCE_TABS_ALL") != nullptr) {
    const char *commerceTabsNodeValue =
        std::getenv("QUICKAPP_IOS_COMMERCE_TABS_NODE");
    const std::string commerceTabsNode = commerceTabsNodeValue == nullptr
        ? "node:8"
        : commerceTabsNodeValue;
    auto commerceTabsGateway = gateway;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
      const bool accepted = quickapp::ios::controlTabs(
          commerceTabsGateway, "srf:1", commerceTabsNode, 1);
      NSLog(@"ios.commerce.probe.tabs.all index=1 accepted=%d",
            accepted ? 1 : 0);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
      const bool accepted = quickapp::ios::controlTabs(
          commerceTabsGateway, "srf:1", commerceTabsNode, 2);
      NSLog(@"ios.commerce.probe.tabs.all index=2 accepted=%d",
            accepted ? 1 : 0);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 6 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
      const bool accepted = quickapp::ios::controlTabs(
          commerceTabsGateway, "srf:1", commerceTabsNode, 3);
      NSLog(@"ios.commerce.probe.tabs.all index=3 accepted=%d",
            accepted ? 1 : 0);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
      const bool accepted = quickapp::ios::controlTabs(
          commerceTabsGateway, "srf:1", commerceTabsNode, 0);
      NSLog(@"ios.commerce.probe.tabs.all index=0 accepted=%d",
            accepted ? 1 : 0);
    });
  }
  if (std::getenv("QUICKAPP_IOS_COMMERCE_ACTIONS") != nullptr) {
    const char *commerceTabsNodeValue =
        std::getenv("QUICKAPP_IOS_COMMERCE_TABS_NODE");
    const std::string commerceTabsNode = commerceTabsNodeValue == nullptr
        ? "node:8"
        : commerceTabsNodeValue;
    const char *commerceStateNodeValue =
        std::getenv("QUICKAPP_IOS_COMMERCE_STATE_NODE");
    const std::string commerceStateNode = commerceStateNodeValue == nullptr
        ? "node:10"
        : commerceStateNodeValue;
    const char *commerceProductNodeValue =
        std::getenv("QUICKAPP_IOS_COMMERCE_PRODUCT_NODE");
    const std::string commerceProductNode = commerceProductNodeValue == nullptr
        ? "node:23"
        : commerceProductNodeValue;
    auto commerceGateway = gateway;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
      const bool accepted = quickapp::ios::controlTabs(
          commerceGateway, "srf:1", commerceTabsNode, 1);
      NSLog(@"ios.commerce.probe.tabs index=1 accepted=%d", accepted ? 1 : 0);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
      const bool accepted = quickapp::ios::controlTabs(
          commerceGateway, "srf:1", commerceTabsNode, 1);
      NSLog(@"ios.commerce.probe.tabs index=1 repeat=1 accepted=%d", accepted ? 1 : 0);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
      const bool accepted = quickapp::ios::controlClick(
          commerceGateway, "srf:1", commerceStateNode);
      NSLog(@"ios.commerce.probe.state node=%s accepted=%d",
            commerceStateNode.c_str(), accepted ? 1 : 0);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
      const bool accepted = quickapp::ios::controlClick(
          commerceGateway, "srf:1", commerceProductNode);
      NSLog(@"ios.commerce.probe.product node=%s accepted=%d",
            commerceProductNode.c_str(), accepted ? 1 : 0);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 7 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
      const bool accepted = quickapp::ios::controlClick(
          commerceGateway, "srf:2", "node:8");
      NSLog(@"ios.commerce.probe.back surface=srf:2 node=node:8 accepted=%d",
            accepted ? 1 : 0);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 9 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
      const bool accepted = quickapp::ios::controlClick(
          commerceGateway, "srf:1", commerceProductNode);
      NSLog(@"ios.commerce.probe.product.repeat node=%s accepted=%d",
            commerceProductNode.c_str(),
            accepted ? 1 : 0);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 11 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
      const bool accepted = quickapp::ios::controlClick(
          commerceGateway, "srf:3", "node:8");
      NSLog(@"ios.commerce.probe.back.repeat surface=srf:3 node=node:8 accepted=%d",
            accepted ? 1 : 0);
    });
  }
  if (std::getenv("QUICKAPP_IOS_COMMERCE_PRODUCT_ACTIONS") != nullptr) {
    const char *commerceProductNodeValue =
        std::getenv("QUICKAPP_IOS_COMMERCE_PRODUCT_NODE");
    const std::string commerceProductNode = commerceProductNodeValue == nullptr
        ? "node:23"
        : commerceProductNodeValue;
    auto commerceGateway = gateway;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
      const bool accepted = quickapp::ios::controlClick(
          commerceGateway, "srf:1", commerceProductNode);
      NSLog(@"ios.commerce.probe.product.first node=%s accepted=%d",
            commerceProductNode.c_str(), accepted ? 1 : 0);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 6 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
      const bool accepted = quickapp::ios::controlClick(
          commerceGateway, "srf:2", "node:8");
      NSLog(@"ios.commerce.probe.back.first surface=srf:2 node=node:8 accepted=%d",
            accepted ? 1 : 0);
    });
  }
  if (std::getenv("QUICKAPP_IOS_COMMERCE_TEARDOWN") != nullptr) {
    auto runtime = *static_cast<std::shared_ptr<quickapp::ios::RuntimeSpine> *>(
        self.runtimeOpaque);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 13 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
      NSLog(@"ios.commerce.probe.teardown.begin");
      dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        runtime->destroy();
        dispatch_async(dispatch_get_main_queue(), ^{
          NSLog(@"ios.commerce.probe.teardown.completed=1");
        });
      });
    });
  }
  NSLog(@"ios.a1.runtime.started rpk=%@", path);
}

- (void)stopRuntime {
  if (self.runtimeOpaque != nullptr) {
    auto *spine = static_cast<std::shared_ptr<quickapp::ios::RuntimeSpine> *>(self.runtimeOpaque);
    (*spine)->destroy();
    delete spine;
    self.runtimeOpaque = nullptr;
  }
}

- (void)sceneDidDisconnect:(UIScene *)scene {
  (void)scene;
  [self stopRuntime];
}

@end

int main(int argc, char *argv[]) {
  @autoreleasepool {
    return UIApplicationMain(argc, argv, nil, NSStringFromClass([QuickAppAppDelegate class]));
  }
}
