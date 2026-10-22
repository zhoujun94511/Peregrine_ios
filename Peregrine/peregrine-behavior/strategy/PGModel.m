#import "PGModel.h"
#import "PGBlockRecovery.h"
#import "PGReuseModel.h"

static const double PGRestartDecay = 0.5;
static const NSTimeInterval PGReuseSaveInterval = 600;

@interface PGModel ()
@property (nonatomic, strong, readwrite) PGGraph *graph;
@property (nonatomic, strong, readwrite) PGOperateSelector *selector;
@property (nonatomic, assign, readwrite) NSInteger decisionCount;
@property (nonatomic, strong, nullable) PGState *previousState;
@property (nonatomic, copy, nullable) NSString *previousActionID;
@property (nonatomic, strong) NSMutableSet<NSString *> *seenActivities;
@property (nonatomic, strong) PGCycleGuard *cycles;
@property (nonatomic, strong) PGReuseModel *reuse;
@property (nonatomic, strong) NSDate *lastReuseSave;
@end

@implementation PGModel

- (instancetype)initWithAgent:(PGAgentKind)kind
{
    self = [super init];
    if(self != nil)
    {
        _graph = [[PGGraph alloc] init];
        _selector = [[PGOperateSelector alloc] initWithKind:kind == PGAgentKindUnspecified ? PGAgentKindNStepQ : kind];
        _restartMeter = 101;
        _seenActivities = [NSMutableSet set];
        _cycles = [[PGCycleGuard alloc] init];
        _reuse = [[PGReuseModel alloc] init];
        _selector.reuseModel = _reuse;
    }
    return self;
}

- (instancetype)init
{
    return [self initWithAgent:PGAgentKindNStepQ];
}

- (PGOperate *)operateForTreeText:(NSString *)treeText activity:(NSString *)activity
{
    if(treeText.length == 0)
    {
        return [[PGOperate alloc] init];
    }
    NSArray<PGElementNode *> *nodes = [PGElementNode nodesFromResult:[self parsedTree:treeText]];
    if(nodes.count == 0)
    {
        return [[PGOperate alloc] init];
    }
    return [self operateForNodes:nodes activity:activity];
}

- (PGOperate *)operateForNodes:(NSArray<PGElementNode *> *)nodes activity:(NSString *)activity
{
    self.decisionCount += 1;
    BOOL created = NO;
    NSString *page = activity ?: @"";
    PGState *state = [self.graph stateForNodes:nodes activity:page created:&created];
    if(self.previousState != nil)
    {
        [self.graph addTransitionFrom:self.previousState actionID:self.previousActionID to:state];
    }
    if(page.length > 0)
    {
        [self.seenActivities addObject:page];
    }
    self.selector.reuseModel = self.reuse;
    self.selector.seenActivities = self.seenActivities;
    double reward = [self.selector reuseRewardForNodes:nodes stateVisits:state.visits];
    if(self.previousActionID.length > 0 && page.length > 0)
    {
        [self.reuse noteAction:self.previousActionID reachedActivity:page];
    }
    [self saveReuseIfDue];
    PGCycleEscape escape = [self.cycles noteStateKey:state.key created:created];
    if(escape == PGCycleEscapeRestart && self.skipRestart)
    {
        escape = PGCycleEscapeBack;
    }
    double stalled = MIN(self.cycles.stepsSinceNewState / (double)15, 1.0);
    self.selector.stallExploration = 0.05 + 0.25 * stalled;
    self.selector.graphObservations = self.graph.observationCount;
    PGOperate *operate = nil;
    BOOL meterRestart = !self.skipRestart && self.decisionCount >= self.restartMeter;
    if(meterRestart || escape == PGCycleEscapeRestart)
    {
        [self.selector absorbReward:reward];
        [self.selector resetLearningWindow];
        [self.selector decayActionValues:PGRestartDecay];
        [self.selector clearBlockedActions];
        [self.cycles reset];
        if(meterRestart)
        {
            self.decisionCount = 0;
        }
        operate = [PGOperate restart];
        if(escape == PGCycleEscapeRestart)
        {
            NSLog(@"cycle escape restart");
        }
    }
    else if(escape == PGCycleEscapeBack || escape == PGCycleEscapeCorner || escape == PGCycleEscapeDismiss)
    {
        [self.selector absorbReward:reward];
        [self.selector forgetLatestAction];
        operate = [self escapeOperate:escape nodes:nodes activity:page];
    }
    else if(escape == PGCycleEscapeAvoid)
    {
        NSSet<NSString *> *banned = [self.graph actionIDsTouchingStateKeys:[NSSet setWithArray:self.cycles.recentStateKeys]];
        operate = [self.selector operateForNodes:nodes activity:page reward:reward avoiding:banned forceRandom:YES];
    }
    else
    {
        operate = [self.selector operateForNodes:nodes activity:page reward:reward];
    }
    if(operate.act.length == 0)
    {
        operate = [[PGOperate alloc] init];
    }
    self.previousState = state;
    self.previousActionID = operate.actionID;
    return operate;
}

- (PGOperate *)escapeOperate:(PGCycleEscape)escape nodes:(NSArray<PGElementNode *> *)nodes activity:(NSString *)activity
{
    CGSize space = self.selector.space;
    PGOperate *operate = escape == PGCycleEscapeCorner ? [self.selector cornerOperateForNodes:nodes activity:activity] : nil;
    if(operate == nil && escape != PGCycleEscapeBack && space.width >= 2 && space.height >= 2)
    {
        operate = [[PGOperate alloc] init];
        operate.act = @"SWIPE";
        operate.rect = (PGElementRect){(NSInteger)(space.width / 2), (NSInteger)(space.height * 0.2), MAX((NSInteger)(space.width / 100), 4), (NSInteger)(space.height * 0.5)};
        operate.actionID = @"DISMISS";
    }
    if(operate == nil)
    {
        operate = [[PGOperate alloc] init];
        operate.act = @"BACK";
        operate.actionID = @"BACK";
    }
    NSLog(@"cycle escape %@ %@", escape == PGCycleEscapeBack ? @"back" : (escape == PGCycleEscapeCorner ? @"corner" : @"dismiss"), operate.act);
    return operate;
}

- (void)loadReuseFromDirectory:(NSString *)directory bundleID:(NSString *)bundleID
{
    [self.reuse loadFromDirectory:directory bundleID:bundleID];
    self.selector.reuseModel = self.reuse;
    self.lastReuseSave = [NSDate date];
}

- (void)saveReuse
{
    [self.reuse save];
    self.lastReuseSave = [NSDate date];
}

- (void)saveReuseIfDue
{
    if(self.reuse.filePath.length == 0)
    {
        return;
    }
    if(self.lastReuseSave != nil && [[NSDate date] timeIntervalSinceDate:self.lastReuseSave] < PGReuseSaveInterval)
    {
        return;
    }
    [self saveReuse];
}

- (void)blacklistLastAction
{
    [self.selector blacklistActionID:self.previousActionID];
}

- (void)discardLatestOperate
{
    self.previousState = nil;
    self.previousActionID = nil;
    [self.selector forgetLatestAction];
}

- (void)confirmCycleRestart
{
    [self.cycles confirmRestartIssued];
}

- (id)parsedTree:(NSString *)treeText
{
    NSData *data = [treeText dataUsingEncoding:NSUTF8StringEncoding];
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if([json isKindOfClass:[NSDictionary class]])
    {
        return ((NSDictionary *)json)[@"result"] ?: json[@"tree"] ?: @[];
    }
    if([json isKindOfClass:[NSArray class]])
    {
        return json;
    }
    return @[];
}

@end
