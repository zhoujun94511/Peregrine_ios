#import "PGOutsideGate.h"

@implementation PGOutsideGate

- (PGOverlayDecision *)decisionForScreen:(PGStepScreen *)screen
{
    // A covering sheet is timed by PGAppWatch. Acting here would swipe or activate on the first sighting.
    (void)screen;
    return [[PGOverlayDecision alloc] init];
}

- (PGOperate *)dismissCoveringScreen:(CGSize)screen
{
    return [self dismissOperateForScreen:screen];
}

// The photo picker and share sheet are sheets inside the app: edge back and foreground leave them open,
// only a downward drag from the sheet's top closes them.
- (PGOperate *)dismissOperateForScreen:(CGSize)screen
{
    if(screen.width <= 0 || screen.height <= 0)
    {
        return [[PGOperate alloc] init];
    }
    PGOperate *dismiss = [[PGOperate alloc] init];
    dismiss.act = @"SWIPE";
    dismiss.rect = (PGElementRect){(NSInteger)(screen.width / 2), (NSInteger)(screen.height * 0.12), 1, (NSInteger)(screen.height * 0.65)};
    dismiss.actionID = @"DISMISS";
    return dismiss;
}

@end
