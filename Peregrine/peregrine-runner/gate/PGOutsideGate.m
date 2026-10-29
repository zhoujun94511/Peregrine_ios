#import "PGOutsideGate.h"
#import "PGActionFilter.h"
#import "PGOverlayRules.h"
#import "PGElementTree.h"
#import "PGOperate.h"

@implementation PGOutsideGate

- (PGOverlayDecision *)decisionForScreen:(PGStepScreen *)screen
{
    if(![self screenIsShare:screen])
    {
        // A covering sheet is timed by PGAppWatch. Acting here would swipe or activate on the first sighting.
        return [[PGOverlayDecision alloc] init];
    }
    [PGActionFilter noteShareSheetSeen];
    PGOverlayDecision *decision = [[PGOverlayDecision alloc] init];
    decision.action = PGOverlayActionOperate;
    PGElementNode *close = [self closeNodeIn:screen.nodes];
    if(close != nil)
    {
        decision.operate = [PGOperate clickOnNode:close];
        NSLog(@"share sheet dismiss %@", decision.operate.text ?: @"");
        return decision;
    }
    decision.operate = [self dismissOperateForScreen:screen.screenSize];
    NSLog(@"share sheet dismiss swipe");
    return decision;
}

- (BOOL)screenIsShare:(PGStepScreen *)screen
{
    NSString *activity = screen.activity ?: @"";
    if([activity rangeOfString:@"UIActivity" options:NSCaseInsensitiveSearch].location != NSNotFound
        || [activity rangeOfString:@"SLCompose" options:NSCaseInsensitiveSearch].location != NSNotFound)
    {
        return YES;
    }
    for(PGElementNode *node in [PGElementNode flattenedNodes:screen.nodes])
    {
        NSString *identifier = node.identifier ?: @"";
        if([identifier rangeOfString:@"UIActivity" options:NSCaseInsensitiveSearch].location != NSNotFound
            || [identifier rangeOfString:@"shareCell" options:NSCaseInsensitiveSearch].location != NSNotFound)
        {
            return YES;
        }
    }
    return NO;
}

- (PGElementNode *)closeNodeIn:(NSArray<PGElementNode *> *)nodes
{
    NSArray<NSString *> *words = @[
        @"close", @"cancel", @"dismiss",
        @"关闭", @"取消",
        @"cerrar", @"cancelar", @"fechar", @"fermer", @"annuler",
        @"schließen", @"schliessen", @"abbrechen",
        @"閉じる", @"キャンセル", @"닫기", @"취소",
        @"chiudi", @"annulla", @"закрыть", @"отмена",
        @"إغلاق", @"إلغاء", @"tutup", @"batal", @"kapat", @"iptal",
        @"đóng", @"hủy", @"ปิด", @"ยกเลิก", @"बंद", @"रद्द"
    ];
    PGElementNode *best = nil;
    NSInteger bestArea = NSIntegerMax;
    for(PGElementNode *node in [PGElementNode flattenedNodes:nodes])
    {
        if(!node.clickable)
        {
            continue;
        }
        NSString *text = [NSString stringWithFormat:@"%@ %@ %@", node.label ?: @"", node.value ?: @"", node.identifier ?: @""];
        if([PGOverlayRules textIsShareEntry:text] || ![PGOverlayRules text:text hasAny:words])
        {
            continue;
        }
        NSInteger area = node.rect.width * node.rect.height;
        if(best == nil || area < bestArea)
        {
            best = node;
            bestArea = area;
        }
    }
    return best;
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
