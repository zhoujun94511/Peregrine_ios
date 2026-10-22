#import <Foundation/Foundation.h>
#import "PGBehavior.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PGSessionStep) {
    PGSessionStepLoadConfig = 0,
    PGSessionStepStartCommandServer,
    PGSessionStepPrepareApps,
    PGSessionStepHome,
    PGSessionStepLaunchApp,
    PGSessionStepProbeStub,
    PGSessionStepRun,
    PGSessionStepStop,
};

typedef NS_ENUM(NSInteger, PGGestureKind) {
    PGGestureKindNone = 0,
    PGGestureKindTap,
    PGGestureKindSwipe,
    PGGestureKindBack,
    PGGestureKindHome,
    PGGestureKindRestart,
    PGGestureKindLaunch,
    PGGestureKindTerminate,
    PGGestureKindForceBack,
    PGGestureKindPath,
    PGGestureKindType,
    PGGestureKindDoubleTap,
    // Two fingers around the app's center; scale above 1 spreads them.
    PGGestureKindPinch,
    // Hold at start for duration, then move to end without lifting.
    PGGestureKindDrag,
};

// A gesture the runner can hand to XCTest. Coordinates are in screen points.
@interface PGGesture : NSObject
@property (nonatomic, assign) PGGestureKind kind;
@property (nonatomic, assign) PGElementRect start;
@property (nonatomic, assign) PGElementRect end;
@property (nonatomic, copy) NSArray<NSValue *> *points;
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, assign) double scale;
@property (nonatomic, copy, nullable) NSString *text;
@property (nonatomic, assign) BOOL unresolved;
+ (PGGesture *)gestureForOperate:(PGOperate *)operate;
@end

@interface PGSession : NSObject
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, assign) NSInteger durationMinutes;
@property (nonatomic, assign) NSInteger throttleMilliseconds;
@property (nonatomic, assign) NSInteger dataPort;
@property (nonatomic, assign) BOOL algorithmNative;
@property (nonatomic, strong) NSDate *startedAt;

// Order used when a run begins. Stub probe is included only when dataPort > 0.
// A non-native algorithm stops after launch instead of entering the action loop.
- (NSArray<NSNumber *> *)startupSteps;

- (BOOL)timeIsUp;

// Nil when PEREGRINE_BUNDLEID is missing. duration defaults to 1 minute, throttle to 300 ms.
+ (nullable instancetype)sessionFromEnvironment:(NSDictionary *)environment;
+ (NSDictionary<NSString *, NSString *> *)launchEnvironmentFromEncoded:(nullable NSString *)encoded;
@end

NS_ASSUME_NONNULL_END
