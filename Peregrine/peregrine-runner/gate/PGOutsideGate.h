#import <XCTest/XCTest.h>
#import "PGOverlayGate.h"
#import "PGStepScreen.h"

NS_ASSUME_NONNULL_BEGIN

// Photos and other system screens: back, then drag the sheet down, then ask for a foreground return.
@interface PGOutsideGate : NSObject
- (PGOverlayDecision *)decisionForScreen:(PGStepScreen *)screen;
@end

NS_ASSUME_NONNULL_END
