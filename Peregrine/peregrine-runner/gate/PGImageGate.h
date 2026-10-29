#import <XCTest/XCTest.h>
#import "PGOverlayGate.h"
#import "PGStepScreen.h"

NS_ASSUME_NONNULL_BEGIN

// Full-screen image zoom / preview. Close, go back, then one foreground return.
// If that preview is still up, later steps belong to the model instead of activating again.
// The page text has to name a preview or gallery, unless the tree is only one or two nodes
// under a large image. A content page with a logo is left alone. The largest node must still
// cover most of the screen, so loading pages and splash screens with a small spinner are left alone.
@interface PGImageGate : NSObject
- (PGOverlayDecision *)decisionForScreen:(PGStepScreen *)screen application:(XCUIApplication *)application;
@end

NS_ASSUME_NONNULL_END
