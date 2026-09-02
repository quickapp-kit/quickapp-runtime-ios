#import "QuickAppKit/QuickAppKit.h"

#include "quickapp/ios/ios_gateway.h"

#include <cmath>
#include <cstring>
#include <limits>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <variant>

NSErrorDomain const QuickAppKitErrorDomain = @"dev.quickappkit.runtime";

namespace {

NSError *makeError(QuickAppKitErrorCode code, NSString *message) {
  return [NSError errorWithDomain:QuickAppKitErrorDomain
                             code:code
                         userInfo:@{NSLocalizedDescriptionKey: message}];
}

void setError(NSError **error, NSError *value) {
  if (error != nullptr) *error = value;
}

std::optional<quickapp::core::RuntimeValue> toRuntimeValue(id value) {
  if (value == nil || value == NSNull.null) return quickapp::core::RuntimeValue::null();
  if ([value isKindOfClass:NSString.class]) {
    auto result = quickapp::core::RuntimeValue::utf8_string(
        std::string(static_cast<NSString *>(value).UTF8String));
    return result ? std::optional<quickapp::core::RuntimeValue>(std::move(result).value())
                  : std::nullopt;
  }
  if ([value isKindOfClass:NSNumber.class]) {
    NSNumber *number = static_cast<NSNumber *>(value);
    const char *type = number.objCType;
    if (std::strcmp(type, @encode(BOOL)) == 0) {
      return quickapp::core::RuntimeValue::boolean(number.boolValue);
    }
    if (std::strcmp(type, @encode(char)) == 0 ||
        std::strcmp(type, @encode(short)) == 0 ||
        std::strcmp(type, @encode(int)) == 0 ||
        std::strcmp(type, @encode(long)) == 0 ||
        std::strcmp(type, @encode(long long)) == 0 ||
        std::strcmp(type, @encode(unsigned char)) == 0 ||
        std::strcmp(type, @encode(unsigned short)) == 0 ||
        std::strcmp(type, @encode(unsigned int)) == 0 ||
        std::strcmp(type, @encode(unsigned long)) == 0 ||
        std::strcmp(type, @encode(unsigned long long)) == 0) {
      const long long integer = number.longLongValue;
      auto result = quickapp::core::RuntimeValue::safe_integer(integer);
      return result ? std::optional<quickapp::core::RuntimeValue>(std::move(result).value())
                    : std::nullopt;
    }
    const double floating = number.doubleValue;
    auto result = quickapp::core::RuntimeValue::finite_number(floating);
    return result ? std::optional<quickapp::core::RuntimeValue>(std::move(result).value())
                  : std::nullopt;
  }
  if ([value isKindOfClass:NSArray.class]) {
    quickapp::core::RuntimeValue::Array result;
    for (id item in static_cast<NSArray *>(value)) {
      auto converted = toRuntimeValue(item);
      if (!converted) return std::nullopt;
      result.push_back(std::move(*converted));
    }
    auto array = quickapp::core::RuntimeValue::array(std::move(result));
    return array ? std::optional<quickapp::core::RuntimeValue>(std::move(array).value())
                 : std::nullopt;
  }
  if ([value isKindOfClass:NSDictionary.class]) {
    quickapp::core::RuntimeValue::Object result;
    for (id key in static_cast<NSDictionary *>(value)) {
      if (![key isKindOfClass:NSString.class]) return std::nullopt;
      auto converted = toRuntimeValue(static_cast<NSDictionary *>(value)[key]);
      if (!converted) return std::nullopt;
      result.emplace(std::string(static_cast<NSString *>(key).UTF8String),
                     std::move(*converted));
    }
    auto object = quickapp::core::RuntimeValue::object(std::move(result));
    return object ? std::optional<quickapp::core::RuntimeValue>(std::move(object).value())
                  : std::nullopt;
  }
  return std::nullopt;
}

std::optional<quickapp::core::package::EventType> eventType(QuickAppKitInputKind kind) {
  using Type = quickapp::core::package::EventType;
  switch (kind) {
    case QuickAppKitInputKindClick: return Type::kClick;
    case QuickAppKitInputKindInput: return Type::kInput;
    case QuickAppKitInputKindChange: return Type::kChange;
    case QuickAppKitInputKindFocus: return Type::kFocus;
    case QuickAppKitInputKindScroll: return Type::kScroll;
    case QuickAppKitInputKindScrollEnd: return Type::kScrollEnd;
    case QuickAppKitInputKindScrollTop: return Type::kScrollTop;
    case QuickAppKitInputKindScrollBottom: return Type::kScrollBottom;
  }
  return std::nullopt;
}

class RuntimeBox;

}  // namespace

@interface QuickAppKitInput ()
@property(nonatomic, readwrite) QuickAppKitInputKind kind;
@property(nonatomic, copy, readwrite) NSString *surfaceIdentifier;
@property(nonatomic, copy, readwrite) NSString *targetIdentifier;
@property(nonatomic, copy, readwrite) NSDictionary<NSString *, id> *payload;
@end

@implementation QuickAppKitInput

+ (instancetype)inputWithKind:(QuickAppKitInputKind)kind
             surfaceIdentifier:(NSString *)surfaceIdentifier
              targetIdentifier:(NSString *)targetIdentifier
                        payload:(NSDictionary<NSString *, id> *)payload {
  QuickAppKitInput *input = [QuickAppKitInput new];
  input.kind = kind;
  input.surfaceIdentifier = surfaceIdentifier.copy;
  input.targetIdentifier = targetIdentifier.copy;
  input.payload = payload.copy;
  return input;
}

- (id)copyWithZone:(NSZone *)zone {
  return [QuickAppKitInput inputWithKind:self.kind
                       surfaceIdentifier:self.surfaceIdentifier
                        targetIdentifier:self.targetIdentifier
                                  payload:self.payload];
}

@end

@interface QuickAppKitRuntimeBox : NSObject {
 @public
  std::shared_ptr<quickapp::ios::platform::Gateway> gateway;
  std::shared_ptr<quickapp::ios::RuntimeSpine> spine;
  CGFloat viewportWidth;
  CGFloat viewportHeight;
  BOOL attached;
  BOOL loading;
  BOOL destroyed;
  QuickAppKitLoadCompletion loadCompletion;
}
- (void)runtimeStarted:(NSString *)surfaceIdentifier;
- (void)runtimeFailed:(NSError *)error;
@end

@implementation QuickAppKitRuntimeBox

- (void)runtimeStarted:(NSString *)surfaceIdentifier {
  (void)surfaceIdentifier;
  loading = NO;
  QuickAppKitLoadCompletion completion = loadCompletion;
  loadCompletion = nil;
  if (completion) completion(YES, nil);
}

- (void)runtimeFailed:(NSError *)error {
  loading = NO;
  QuickAppKitLoadCompletion completion = loadCompletion;
  loadCompletion = nil;
  if (completion) completion(NO, error);
}

- (void)dealloc {
  if (spine) spine->destroy();
  if (gateway) quickapp::ios::closeGateway(gateway);
}

@end

@interface QuickAppKitRuntime ()
@property(nonatomic, strong) QuickAppKitRuntimeBox *box;
@end

@implementation QuickAppKitRuntime

+ (instancetype)createRuntimeWithViewportWidth:(CGFloat)width
                                          height:(CGFloat)height
                                           error:(NSError **)error {
  return [[self alloc] initWithViewportWidth:width height:height error:error];
}

- (instancetype)initWithViewportWidth:(CGFloat)width
                                 height:(CGFloat)height
                                  error:(NSError **)error {
  if (width <= 0 || height <= 0 || !std::isfinite(width) || !std::isfinite(height)) {
    setError(error, makeError(QuickAppKitErrorInvalidArgument,
                              @"viewport dimensions must be finite and positive"));
    return nil;
  }
  self = [super init];
  if (self) {
    _box = [QuickAppKitRuntimeBox new];
    _box->viewportWidth = width;
    _box->viewportHeight = height;
  }
  return self;
}

- (BOOL)attachSurface:(UIView *)surface error:(NSError **)error {
  if (!NSThread.isMainThread) {
    setError(error, makeError(QuickAppKitErrorPlatformRejected,
                              @"UIKit surface operations require the main thread"));
    return NO;
  }
  if (self.destroyed) {
    setError(error, makeError(QuickAppKitErrorRuntimeDestroyed, @"runtime is destroyed"));
    return NO;
  }
  if (surface == nil || self.box->attached) {
    setError(error, makeError(QuickAppKitErrorInvalidState,
                              @"surface is missing or already attached"));
    return NO;
  }
  self.box->gateway = quickapp::ios::makeGateway(surface);
  self.box->spine = quickapp::ios::RuntimeSpine::create(
      self.box->gateway, self.box->viewportWidth, self.box->viewportHeight);
  if (!self.box->gateway || !self.box->spine) {
    self.box->gateway.reset();
    self.box->spine.reset();
    setError(error, makeError(QuickAppKitErrorPlatformRejected,
                              @"failed to create iOS runtime composition"));
    return NO;
  }
  quickapp::ios::bindGateway(self.box->gateway, self.box->spine);
  __weak QuickAppKitRuntimeBox *weakBox = self.box;
  quickapp::ios::setGatewayRuntimeCallbacks(
      self.box->gateway,
      [weakBox](std::string surfaceIdentifier) {
        dispatch_async(dispatch_get_main_queue(), ^{
          QuickAppKitRuntimeBox *box = weakBox;
          if (box && !box->destroyed) {
            [box runtimeStarted:[NSString stringWithUTF8String:surfaceIdentifier.c_str()]];
          }
        });
      },
      [weakBox](std::string code, std::string message) {
        (void)code;
        dispatch_async(dispatch_get_main_queue(), ^{
          QuickAppKitRuntimeBox *box = weakBox;
          if (box && !box->destroyed) {
            NSString *description = [NSString stringWithUTF8String:message.c_str()];
            [box runtimeFailed:makeError(QuickAppKitErrorPackageRejected, description)];
          }
        });
      });
  self.box->attached = YES;
  return YES;
}

- (void)loadRPKFromURL:(NSURL *)url completion:(QuickAppKitLoadCompletion)completion {
  if (!completion) return;
  if (!NSThread.isMainThread) {
    completion(NO, makeError(QuickAppKitErrorPlatformRejected,
                             @"RPK loading must be initiated on the main thread"));
    return;
  }
  if (self.destroyed) {
    completion(NO, makeError(QuickAppKitErrorRuntimeDestroyed, @"runtime is destroyed"));
    return;
  }
  if (!self.box->attached || self.box->loading || self.box->spine == nullptr) {
    completion(NO, makeError(QuickAppKitErrorInvalidState,
                             @"runtime must have one attached surface and no active load"));
    return;
  }
  if (![url isFileURL] || url.path.length == 0 ||
      [url.path containsString:@".."] ||
      ![NSFileManager.defaultManager fileExistsAtPath:url.path]) {
    completion(NO, makeError(QuickAppKitErrorPackageNotFound,
                             @"RPK must be an existing local file"));
    return;
  }
  NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:url.path error:nil];
  NSNumber *sizeValue = attributes[NSFileSize];
  unsigned long long size = sizeValue.unsignedLongLongValue;
  if (size == 0 || size > 64ULL * 1024ULL * 1024ULL) {
    completion(NO, makeError(QuickAppKitErrorPackageTooLarge,
                             @"RPK size is outside the permitted range"));
    return;
  }
  self.box->loading = YES;
  self.box->loadCompletion = [completion copy];
  self.box->spine->start(std::string(url.path.UTF8String));
}

- (BOOL)dispatchInput:(QuickAppKitInput *)input error:(NSError **)error {
  if (self.destroyed) {
    setError(error, makeError(QuickAppKitErrorRuntimeDestroyed, @"runtime is destroyed"));
    return NO;
  }
  if (!input.surfaceIdentifier.length || !input.targetIdentifier.length) {
    setError(error, makeError(QuickAppKitErrorInvalidArgument,
                              @"input requires opaque surface and target identifiers"));
    return NO;
  }
  auto type = eventType(input.kind);
  auto payload = toRuntimeValue(input.payload);
  using ObjectPointer = std::shared_ptr<const quickapp::core::RuntimeValue::Object>;
  const auto object = payload
      ? std::get_if<ObjectPointer>(&payload->storage())
      : nullptr;
  if (!type || !object || !*object) {
    setError(error, makeError(QuickAppKitErrorInvalidArgument,
                              @"input payload is not a supported typed object"));
    return NO;
  }
  const bool accepted = self.box->spine && self.box->spine->dispatchInput(
      std::string(input.surfaceIdentifier.UTF8String),
      std::string(input.targetIdentifier.UTF8String), *type,
      **object,
      0);
  if (!accepted) {
    setError(error, makeError(QuickAppKitErrorPlatformRejected, @"input queue rejected"));
  }
  return accepted;
}

- (BOOL)updateLifecycle:(QuickAppKitLifecycleSignal)signal error:(NSError **)error {
  (void)signal;
  if (self.destroyed) {
    setError(error, makeError(QuickAppKitErrorRuntimeDestroyed, @"runtime is destroyed"));
    return NO;
  }
  setError(error, makeError(QuickAppKitErrorUnsupported,
                            @"foreground/background lifecycle is not implemented by this Runtime"));
  return NO;
}

- (void)destroyRuntime {
  if (self.destroyed) return;
  self.box->destroyed = YES;
  self.box->loadCompletion = nil;
  quickapp::ios::setGatewayRuntimeCallbacks(self.box->gateway, {}, {});
  if (self.box->spine) self.box->spine->destroy();
  if (self.box->gateway) quickapp::ios::closeGateway(self.box->gateway);
  self.box->spine.reset();
  self.box->gateway.reset();
  self.box->attached = NO;
}

- (BOOL)isDestroyed {
  return self.box->destroyed;
}

@end
