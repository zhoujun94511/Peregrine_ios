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
// A page whose only clickable controls are purchase controls is also a paywall: edge back leaves it up.
// A wide close bar is tapped at both ends. Separate left and right close controls are both tapped.
// A side that has no named close yet waits up to 8 seconds. An unlabeled corner is used only after
// that wait, so it does not take the place of a close button that appears later. Restart starts the wait over.
// A candidate covering more than a quarter of the screen is ignored.
// A short give-up label taps that control and does not tap continue-watching or a corner.
// Continue-watching does not start that path. Give-up copy keeps an ad round already open.
@interface PGOverlayGate : NSObject
- (PGOverlayDecision *)decisionForScreen:(PGStepScreen *)screen application:(XCUIApplication *)application;
@end

NS_ASSUME_NONNULL_END
