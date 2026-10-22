#import "PGOutsideGate.h"

@implementation PGOutsideGate
{
    NSInteger _streak;
}

- (PGOverlayDecision *)decisionForScreen:(PGStepScreen *)screen
{
    PGOverlayDecision *decision = [[PGOverlayDecision alloc] init];
    if(!screen.outside)
    {
        _streak = 0;
        return decision;
    }
    _streak += 1;
    if(_streak >= 3)
    {
        decision.action = PGOverlayActionForeground;
        NSLog(@"outside %@ step %ld foreground", screen.activity ?: @"", (long)_streak);
        return decision;
    }
    decision.action = PGOverlayActionOperate;
    decision.operate = _streak == 1 ? [self backOperate] : [self dismissOperateForScreen:screen.screenSize];
    NSLog(@"outside %@ step %ld %@", screen.activity ?: @"", (long)_streak, decision.operate.actionID.lowercaseString);
    return decision;
}

- (PGOperate *)backOperate
{
    PGOperate *back = [[PGOperate alloc] init];
    back.act = @"BACK";
    back.actionID = @"BACK";
    return back;
}

// The photo picker and share sheet are sheets inside the app: edge back and foreground leave them open,
// only a downward drag from the sheet's top closes them.
- (PGOperate *)dismissOperateForScreen:(CGSize)screen
{
    if(screen.width <= 0 || screen.height <= 0)
    {
        return [self backOperate];
    }
    PGOperate *dismiss = [[PGOperate alloc] init];
    dismiss.act = @"SWIPE";
    dismiss.rect = (PGElementRect){(NSInteger)(screen.width / 2), (NSInteger)(screen.height * 0.12), 1, (NSInteger)(screen.height * 0.65)};
    dismiss.actionID = @"DISMISS";
    return dismiss;
}

@end
