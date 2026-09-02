#pragma once

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const QuickAppKitErrorDomain;

typedef NS_ERROR_ENUM(QuickAppKitErrorDomain, QuickAppKitErrorCode) {
  QuickAppKitErrorInvalidArgument = 1,
  QuickAppKitErrorInvalidState,
  QuickAppKitErrorPackageNotFound,
  QuickAppKitErrorPackageTooLarge,
  QuickAppKitErrorPackageRejected,
  QuickAppKitErrorPlatformRejected,
  QuickAppKitErrorUnsupported,
  QuickAppKitErrorRuntimeDestroyed,
};

typedef NS_ENUM(NSInteger, QuickAppKitInputKind) {
  QuickAppKitInputKindClick = 0,
  QuickAppKitInputKindInput,
  QuickAppKitInputKindChange,
  QuickAppKitInputKindFocus,
  QuickAppKitInputKindScroll,
  QuickAppKitInputKindScrollEnd,
  QuickAppKitInputKindScrollTop,
  QuickAppKitInputKindScrollBottom,
};

typedef NS_ENUM(NSInteger, QuickAppKitLifecycleSignal) {
  QuickAppKitLifecycleSignalForeground = 0,
  QuickAppKitLifecycleSignalBackground,
};

@interface QuickAppKitInput : NSObject <NSCopying>

@property(nonatomic, readonly) QuickAppKitInputKind kind;
@property(nonatomic, copy, readonly) NSString *surfaceIdentifier;
@property(nonatomic, copy, readonly) NSString *targetIdentifier;
@property(nonatomic, copy, readonly) NSDictionary<NSString *, id> *payload;

+ (instancetype)inputWithKind:(QuickAppKitInputKind)kind
             surfaceIdentifier:(NSString *)surfaceIdentifier
              targetIdentifier:(NSString *)targetIdentifier
                        payload:(NSDictionary<NSString *, id> *)payload;

@end

typedef void (^QuickAppKitLoadCompletion)(BOOL success, NSError *_Nullable error);

@interface QuickAppKitRuntime : NSObject

+ (nullable instancetype)createRuntimeWithViewportWidth:(CGFloat)width
                                                   height:(CGFloat)height
                                                    error:(NSError *_Nullable *_Nullable)error;
- (nullable instancetype)initWithViewportWidth:(CGFloat)width
                                          height:(CGFloat)height
                                           error:(NSError *_Nullable *_Nullable)error NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (BOOL)attachSurface:(UIView *)surface error:(NSError *_Nullable *_Nullable)error;
- (void)loadRPKFromURL:(NSURL *)url completion:(QuickAppKitLoadCompletion)completion;
- (BOOL)dispatchInput:(QuickAppKitInput *)input
                error:(NSError *_Nullable *_Nullable)error;
- (BOOL)updateLifecycle:(QuickAppKitLifecycleSignal)signal
                  error:(NSError *_Nullable *_Nullable)error;
- (void)destroyRuntime;

@property(nonatomic, readonly, getter=isDestroyed) BOOL destroyed;

@end

NS_ASSUME_NONNULL_END
