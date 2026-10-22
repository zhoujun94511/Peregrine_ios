#import "PGClickCorrector.h"
#import "PGSnapshotTree.h"

static const NSInteger PGSnapshotCorrectBudgetMillis = 1500;
static const NSInteger PGSnapshotCorrectCooldownSteps = 5;

@implementation PGClickCorrection
@end

@implementation PGClickCorrector
{
    NSInteger _cooldown;
}

- (BOOL)allowsCorrectionForOperate:(PGOperate *)operate modelClick:(BOOL)modelClick usePoints:(BOOL)usePoints correctionDone:(BOOL)correctionDone
{
    if(!modelClick || usePoints || correctionDone || ![self clickNeedsCorrection:operate])
    {
        return NO;
    }
    if(_cooldown > 0)
    {
        _cooldown -= 1;
        NSLog(@"snapshot correct cooldown %ld", (long)_cooldown);
        return NO;
    }
    return YES;
}

- (PGClickCorrection *)correctOperate:(PGOperate *)operate
                         application:(XCUIApplication *)application
                              screen:(PGStepScreen *)screen
                          pixelNodes:(NSArray<PGElementNode *> *)pixelNodes
                           pixelSize:(CGSize)pixelSize
{
    PGClickCorrection *result = [[PGClickCorrection alloc] init];
    result.operate = operate;
    PGStepSnapshot *snapshot = [screen snapshotInApplication:application];
    if(snapshot.failure != nil)
    {
        NSLog(@"snapshot correct failed %@", snapshot.failure);
        result.slow = YES;
        _cooldown = PGSnapshotCorrectCooldownSteps;
        return result;
    }
    NSString *pageName = snapshot.pageName;
    BOOL outside = snapshot.outside;
    NSArray<PGElementNode *> *snapshotNodes = snapshot.nodes;
    NSInteger elapsed = snapshot.elapsedMillis;
    result.pageName = pageName;
    result.outside = outside;
    if(outside)
    {
        NSLog(@"snapshot correct outside page %@ elapsed %ld", pageName, (long)elapsed);
        return result;
    }
    if(elapsed > PGSnapshotCorrectBudgetMillis)
    {
        result.slow = YES;
        _cooldown = PGSnapshotCorrectCooldownSteps;
        NSLog(@"snapshot correct slow %ld", (long)elapsed);
        return result;
    }
    if(snapshotNodes.count == 0)
    {
        NSLog(@"snapshot correct miss empty elapsed %ld", (long)elapsed);
        return result;
    }
    PGElementNode *control = [PGSnapshotTree controlCoveringRect:operate.rect inNodes:snapshotNodes];
    if(control != nil)
    {
        operate.name = control.type ?: @"";
        operate.text = control.label.length > 0 ? control.label : control.value;
        operate.rect = control.rect;
        NSLog(@"snapshot correct hit %@ %@ elapsed %ld", control.type, operate.text ?: @"", (long)elapsed);
    }
    else
    {
        NSLog(@"snapshot correct miss no-control elapsed %ld", (long)elapsed);
    }
    result.nodes = [PGSnapshotTree nodesByAddingHoles:[self tallHoles:pixelNodes pixelSize:pixelSize screenSize:screen.screenSize] toSnapshotNodes:snapshotNodes pixelSize:pixelSize screenSize:screen.screenSize];
    result.corrected = result.nodes.count > 0;
    return result;
}

- (BOOL)clickNeedsCorrection:(PGOperate *)operate
{
    if(operate == nil || [operate.act caseInsensitiveCompare:@"CLICK"] != NSOrderedSame)
    {
        return NO;
    }
    if(operate.text.length == 0)
    {
        return YES;
    }
    return operate.rect.height > 0 && operate.rect.height < 20;
}

- (NSArray<PGElementNode *> *)tallHoles:(NSArray<PGElementNode *> *)holes pixelSize:(CGSize)pixelSize screenSize:(CGSize)screenSize
{
    if(holes.count == 0 || pixelSize.height < 2 || screenSize.height < 2)
    {
        return @[];
    }
    NSMutableArray<PGElementNode *> *kept = [NSMutableArray array];
    for(PGElementNode *hole in holes)
    {
        if(!hole.clickable)
        {
            continue;
        }
        NSInteger height = (NSInteger)(hole.rect.height * screenSize.height / pixelSize.height);
        if(height < 20)
        {
            continue;
        }
        [kept addObject:hole];
    }
    return kept;
}

@end
