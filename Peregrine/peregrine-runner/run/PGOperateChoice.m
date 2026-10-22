#import "PGOperateChoice.h"
#import "PGScreenGrab.h"

@implementation PGOperateChoice

+ (NSString *)activityInNodes:(NSArray<PGElementNode *> *)nodes
{
    for(PGElementNode *node in nodes)
    {
        NSString *name = [node contentController];
        if(name.length > 0)
        {
            return name;
        }
    }
    return @"";
}

+ (NSArray *)treeFromClient:(PGStubClient *)client port:(NSInteger)port
{
    dispatch_semaphore_t gate = dispatch_semaphore_create(0);
    __block NSArray *tree = nil;
    [client fetchTreeOnPort:port completion:^(NSArray *result, NSError *error) {
        tree = result;
        dispatch_semaphore_signal(gate);
    }];
    dispatch_semaphore_wait(gate, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
    return [tree isKindOfClass:[NSArray class]] ? tree : @[];
}

+ (PGOperate *)operateForNodes:(NSArray<PGElementNode *> *)nodes
                          tree:(NSString *)treeText
                         cycle:(PGActionCycle *)cycle
                         model:(PGModel *)model
                    preference:(PGPreference *)preference
                       session:(PGSession *)session
                      activity:(NSString *)activity
                  actionSource:(NSUInteger)actionSource
                        screen:(CGSize)screen
{
    model.selector.space = screen;
    PGPreferenceDecision *decision = [preference decisionForNodes:nodes activity:activity screenSize:screen];
    if(decision.kind == PGPreferenceDecisionSuppressModel)
    {
        [model discardLatestOperate];
        return [[PGOperate alloc] init];
    }
    if(decision.kind == PGPreferenceDecisionCommand)
    {
        [model discardLatestOperate];
        return [PGOperate operateFromCommand:decision.command] ?: [[PGOperate alloc] init];
    }
    if(treeText.length < 20)
    {
        PGActionCycleResult *result = [cycle evaluateStubTree:treeText
                                                customCommand:nil
                                                     activity:activity
                                                 actionSource:actionSource
                                                      context:@{
                                                          @"appid": session.bundleID ?: @"",
                                                          @"throttle": @(session.throttleMilliseconds)
                                                      }
                                                     selector:model.selector];
        [model discardLatestOperate];
        if(result.status == PGActionCycleStatusRetry)
        {
            return [[PGOperate alloc] init];
        }
        return result.operate ?: [[PGOperate alloc] init];
    }
    cycle.emptyTreeCount = 0;
    return [model operateForNodes:nodes activity:activity];
}

+ (PGOperate *)operateForScreenshotNodes:(NSArray<PGElementNode *> *)nodes
                                   model:(PGModel *)model
                              preference:(PGPreference *)preference
                                activity:(NSString *)activity
                                  pixels:(CGSize)pixels
                                  screen:(CGSize)screen
{
    model.selector.space = pixels;
    PGPreferenceDecision *decision = [preference decisionForNodes:nodes activity:activity screenSize:pixels];
    if(decision.kind == PGPreferenceDecisionSuppressModel)
    {
        [model discardLatestOperate];
        return [[PGOperate alloc] init];
    }
    if(decision.kind == PGPreferenceDecisionCommand)
    {
        [model discardLatestOperate];
        return [PGOperate operateFromCommand:decision.command] ?: [[PGOperate alloc] init];
    }
    PGOperate *operate = [model operateForNodes:nodes activity:activity];
    return [PGScreenGrab scaleOperate:operate fromPixels:pixels toScreen:screen];
}
@end
