#import <XCTest/XCTest.h>
#import "PGOverlayGate.h"
#import "PGStepScreen.h"

NS_ASSUME_NONNULL_BEGIN

// A sheet covering the target is closed by dragging it down, after the foreground watch has waited.
// Edge back leaves it open. decisionForScreen does not swipe on the first sighting of that sheet.
// A share sheet is different: its destinations are not explored. Close and cancel are tapped;
// Done is left alone because it sends the share, and the sheet is dragged down when neither is
// present. After the sheet has been seen once, share controls in the app are left out.
@interface PGOutsideGate : NSObject
- (PGOverlayDecision *)decisionForScreen:(PGStepScreen *)screen;
- (PGOperate *)dismissCoveringScreen:(CGSize)screen;
@end

NS_ASSUME_NONNULL_END
