#import <XCTest/XCTest.h>
#import "PGBehavior.h"
#import "PGStepScreen.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PGStepShotsMode) {
    PGStepShotsModeOff = 0,
    PGStepShotsModeChange,
    PGStepShotsModeAll
};

// Optional per-step screenshots with the candidate blocks and the chosen target drawn on top.
// Written to peregrine-shots/ beside the event log, packed into peregrine-shots.zip at the end.
@interface PGStepShots : NSObject
@property (nonatomic, assign, readonly) PGStepShotsMode mode;
+ (PGStepShotsMode)modeFromText:(nullable NSString *)text;
// Only the newest limit shots stay on the phone.
- (instancetype)initWithMode:(PGStepShotsMode)mode directory:(NSString *)directory limit:(NSInteger)limit;
- (void)recordScreen:(PGStepScreen *)screen operate:(nullable PGOperate *)operate application:(XCUIApplication *)application;
- (void)finish;
@end

NS_ASSUME_NONNULL_END
