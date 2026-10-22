#import <XCTest/XCTest.h>
#import "PGStepScreen.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PGOverlayAction) {
    PGOverlayActionNone = 0,
    PGOverlayActionOperate,
    PGOverlayActionForeground,
};

// What to do when a full-screen paywall or ad is covering the app.
@interface PGOverlayDecision : NSObject
@property (nonatomic, assign) PGOverlayAction action;
@property (nonatomic, strong, nullable) PGOperate *operate;
@end

// Recognizes a full-screen paywall (subscribe/purchase words covering the screen) or ad.
// Paywall close is named text or a top-corner control, not the bottom tab.
@interface PGOverlayGate : NSObject
- (PGOverlayDecision *)decisionForScreen:(PGStepScreen *)screen application:(XCUIApplication *)application;
@end

NS_ASSUME_NONNULL_END
