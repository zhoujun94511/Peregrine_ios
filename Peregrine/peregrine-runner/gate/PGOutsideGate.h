#import <XCTest/XCTest.h>
#import "PGOverlayGate.h"
#import "PGStepScreen.h"

NS_ASSUME_NONNULL_BEGIN

// A sheet covering the target is closed by dragging it down, after the foreground watch has waited.
// Edge back leaves it open. decisionForScreen does not swipe on the first sighting.
@interface PGOutsideGate : NSObject
- (PGOverlayDecision *)decisionForScreen:(PGStepScreen *)screen;
- (PGOperate *)dismissCoveringScreen:(CGSize)screen;
@end

NS_ASSUME_NONNULL_END
