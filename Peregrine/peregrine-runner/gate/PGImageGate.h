#import <XCTest/XCTest.h>
#import "PGOverlayGate.h"
#import "PGStepScreen.h"

NS_ASSUME_NONNULL_BEGIN

// Full-screen image zoom / preview. Close, go back, then ask for a foreground return.
// The largest node must cover most of the screen even when the page has only one or two nodes,
// so loading pages and splash screens with a small spinner are left alone.
@interface PGImageGate : NSObject
- (PGOverlayDecision *)decisionForScreen:(PGStepScreen *)screen application:(XCUIApplication *)application;
@end

NS_ASSUME_NONNULL_END
