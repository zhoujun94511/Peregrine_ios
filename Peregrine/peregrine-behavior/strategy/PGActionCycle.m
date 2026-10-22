#import "PGActionCycle.h"

static const NSInteger PGMinimumTreeLength = 20;
static const NSInteger PGEmptyTreeRestartLimit = 50;

@implementation PGActionCycleResult
@end

@implementation PGActionCycle

- (PGActionCycleResult *)evaluateStubTree:(NSString *)tree
                            customCommand:(NSString *)customCommand
                                 activity:(NSString *)activity
                             actionSource:(NSUInteger)actionSource
                                  context:(NSDictionary *)context
                                 selector:(PGOperateSelector *)selector
{
    PGActionCycleResult *result = [[PGActionCycleResult alloc] init];
    if(customCommand.length > 0)
    {
        result.status = PGActionCycleStatusCustomCommand;
        result.customCommand = customCommand;
        return result;
    }
    if(tree.length < PGMinimumTreeLength)
    {
        self.emptyTreeCount += 1;
        if(self.emptyTreeCount > PGEmptyTreeRestartLimit)
        {
            self.emptyTreeCount = 0;
            result.status = PGActionCycleStatusOperate;
            result.operate = [PGOperate restart];
            return result;
        }
        result.status = PGActionCycleStatusRetry;
        return result;
    }
    self.emptyTreeCount = 0;
    PGAgentKind kind = self.agentKind == PGAgentKindUnspecified ? PGAgentKindNStepQ : self.agentKind;
    if(selector.kind == PGAgentKindUnspecified)
    {
        selector.kind = kind;
    }
    NSArray<PGElementNode *> *roots = [PGElementNode nodesFromResult:[self resultArrayFromTree:tree]];
    result.status = PGActionCycleStatusOperate;
    result.operate = [selector operateForNodes:roots activity:activity reward:0];
    result.modelRequest = [self requestWithTree:tree
                                       activity:activity
                                   actionSource:actionSource
                                        context:context
                                           kind:kind];
    return result;
}

- (id)resultArrayFromTree:(NSString *)tree
{
    id json = [NSJSONSerialization JSONObjectWithData:[tree dataUsingEncoding:NSUTF8StringEncoding]
                                              options:0
                                                error:nil];
    if([json isKindOfClass:[NSDictionary class]])
    {
        return ((NSDictionary *)json)[@"result"] ?: ((NSDictionary *)json)[@"tree"];
    }
    return json;
}

- (NSDictionary *)requestWithTree:(NSString *)tree
                         activity:(NSString *)activity
                     actionSource:(NSUInteger)actionSource
                          context:(NSDictionary *)context
                             kind:(PGAgentKind)kind
{
    return @{
        @"tree": tree ?: @"",
        @"deviceid": context[@"deviceid"] ?: @"",
        @"appid": context[@"appid"] ?: @"",
        @"taskid": context[@"taskid"] ?: @0,
        @"agentType": @(kind),
        @"timestamp": @( (NSInteger)[NSDate date].timeIntervalSince1970 ),
        @"activity": activity ?: @"",
        @"cases": @"",
        @"throttle": context[@"throttle"] ?: @0,
        @"actionSource": @(actionSource)
    };
}

@end
