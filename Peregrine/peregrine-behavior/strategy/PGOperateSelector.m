#import "PGOperateSelector.h"
#import "PGActionFilter.h"
#import "PGExploreStrategy.h"
#import "PGReuseModel.h"
#import "PGGestureMix.h"
#import <math.h>

static const NSInteger PGSarsaWindow = 5;

static double PGGumbelNoise(void)
{
    double unit = (double)arc4random_uniform(10) / 10.0;
    if(unit < 0.001)
    {
        unit = 0.001;
    }
    return -log(-log(unit));
}

static NSString * PGNodeKey(PGElementNode *node)
{
    return [NSString stringWithFormat:@"%@|%@|%@|%@",
            node.controller ?: @"",
            node.path ?: @"",
            node.type ?: @"",
            node.identifier ?: @""];
}

@interface PGActionMemory : NSObject
@property (nonatomic, assign) NSInteger visits;
@property (nonatomic, assign) double value;
@property (nonatomic, strong) NSDate *lastVisit;
@end

@implementation PGActionMemory
@end

@interface PGOperateSelector ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, PGActionMemory *> *memory;
@property (nonatomic, assign, readwrite) NSInteger storedStepCount;
@property (nonatomic, copy) NSString *activity;
@property (nonatomic, copy) NSString *latestKey;
@property (nonatomic, strong) NSMutableSet<NSString *> *blockedActionIDs;
@property (nonatomic, strong) NSMutableArray<NSString *> *sarsaActions;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *sarsaRewards;
@end

@implementation PGOperateSelector

- (instancetype)initWithKind:(PGAgentKind)kind
{
    self = [super init];
    if(self != nil)
    {
        _kind = kind == PGAgentKindUnspecified ? PGAgentKindNStepQ : kind;
        _memory = [NSMutableDictionary dictionary];
        _blockedActionIDs = [NSMutableSet set];
        _sarsaActions = [NSMutableArray array];
        _sarsaRewards = [NSMutableArray array];
        _discount = 0.8;
        _inputTexts = @[@"peregrine", @"1", @"test"];
    }
    return self;
}

- (instancetype)init
{
    return [self initWithKind:PGAgentKindNStepQ];
}

- (PGOperate *)operateForNodes:(NSArray<PGElementNode *> *)roots
                      activity:(NSString *)activity
                        reward:(double)reward
{
    return [self operateForNodes:roots activity:activity reward:reward avoiding:nil forceRandom:NO];
}

- (PGOperate *)operateForNodes:(NSArray<PGElementNode *> *)roots
                      activity:(NSString *)activity
                        reward:(double)reward
                      avoiding:(NSSet<NSString *> *)banned
                   forceRandom:(BOOL)forceRandom
{
    self.activity = activity ?: @"";
    [self noteReward:reward];
    NSArray<PGElementNode *> *eligible = [self eligibleNodesIn:roots];
    if(eligible.count == 0)
    {
        [self updateSarsaBootstrappingKey:nil];
        [self blacklistActionID:self.latestKey];
        self.latestKey = nil;
        return [self backOperateFor:roots activity:activity];
    }
    NSArray<PGElementNode *> *pool = [self poolFrom:eligible avoiding:banned];
    if(pool.count == 0)
    {
        [self updateSarsaBootstrappingKey:nil];
        self.latestKey = nil;
        return [self backOperateFor:roots activity:activity];
    }
    NSString *gesture = self.gestures != nil ? [self.gestures nextGesture] : @"CLICK";
    BOOL spaced = self.space.width >= 2 && self.space.height >= 2;
    if(spaced && ([gesture isEqualToString:@"SWIPE"] || [gesture isEqualToString:@"PINCH"]))
    {
        [self updateSarsaBootstrappingKey:nil];
        self.latestKey = nil;
        PGOperate *screen = [self.gestures screenOperate:gesture space:self.space];
        screen.stateID = [self stateIDFor:roots activity:activity];
        return screen;
    }
    PGElementNode *chosen = forceRandom ? pool[arc4random_uniform((uint32_t)pool.count)] : [self chooseFrom:pool];
    NSString *key = [self keyForNode:chosen];
    [self updateSarsaBootstrappingKey:key];
    [self rememberChoice:key];
    PGOperate *operate = [PGOperate clickOnNode:chosen];
    NSString *type = chosen.type.lowercaseString ?: @"";
    if(chosen.scrollable || [type containsString:@"scroll"] || [type containsString:@"table"] || [type containsString:@"collection"])
    {
        operate.act = self.gestures != nil ? [self.gestures scrollAct] : @"SWIPE_UP";
    }
    else if([type containsString:@"field"] || [type containsString:@"textview"] || [type containsString:@"search"])
    {
        operate.act = @"TYPE";
        NSArray<NSString *> *texts = self.inputTexts.count > 0 ? self.inputTexts : @[@"peregrine"];
        operate.text = texts[arc4random_uniform((uint32_t)texts.count)];
    }
    else
    {
        [self.gestures applyGesture:gesture toOperate:operate space:self.space];
    }
    operate.stateID = [self stateIDFor:roots activity:activity];
    operate.actionID = key;
    return operate;
}

- (PGOperate *)cornerOperateForNodes:(NSArray<PGElementNode *> *)roots activity:(NSString *)activity
{
    CGSize space = self.space;
    if(space.width < 2 || space.height < 2)
    {
        return nil;
    }
    PGElementNode *best = nil;
    double bestArea = 0;
    for(PGElementNode *node in [self eligibleNodesIn:roots])
    {
        PGElementRect rect = node.rect;
        double width = rect.width / space.width;
        double height = rect.height / space.height;
        double midX = (rect.left + rect.width / 2.0) / space.width;
        double midY = (rect.top + rect.height / 2.0) / space.height;
        // Status-bar items start within the top 5%.
        if(rect.top < space.height * 0.05 || width > 0.25 || height > 0.12 || midY > 0.2 || (midX > 0.25 && midX < 0.75))
        {
            continue;
        }
        double area = width * height;
        if(best == nil || area < bestArea)
        {
            best = node;
            bestArea = area;
        }
    }
    if(best == nil)
    {
        return nil;
    }
    self.activity = activity ?: @"";
    [self updateSarsaBootstrappingKey:nil];
    self.latestKey = nil;
    PGOperate *operate = [PGOperate clickOnNode:best];
    operate.stateID = [self stateIDFor:roots activity:activity];
    operate.actionID = [self keyForNode:best];
    return operate;
}

- (PGOperate *)backOperateFor:(NSArray<PGElementNode *> *)roots activity:(NSString *)activity
{
    PGOperate *back = [[PGOperate alloc] init];
    back.act = @"BACK";
    back.actionID = @"BACK";
    back.stateID = [self stateIDFor:roots activity:activity];
    return back;
}

- (NSArray<PGElementNode *> *)poolFrom:(NSArray<PGElementNode *> *)eligible avoiding:(NSSet<NSString *> *)banned
{
    NSMutableArray<PGElementNode *> *pool = [NSMutableArray array];
    for(PGElementNode *node in eligible)
    {
        NSString *key = [self keyForNode:node];
        if([self.blockedActionIDs containsObject:key] || [banned containsObject:key])
        {
            continue;
        }
        [pool addObject:node];
    }
    return pool;
}

- (void)forgetLatestAction
{
    if(self.sarsaActions.count > self.sarsaRewards.count)
    {
        [self.sarsaActions removeLastObject];
    }
    self.latestKey = nil;
}

- (void)resetLearningWindow
{
    [self.sarsaActions removeAllObjects];
    [self.sarsaRewards removeAllObjects];
    self.latestKey = nil;
}

- (void)blacklistActionID:(NSString *)actionID
{
    if(actionID.length > 0)
    {
        [self.blockedActionIDs addObject:actionID];
    }
}

- (void)clearBlockedActions
{
    [self.blockedActionIDs removeAllObjects];
}

- (void)decayActionValues:(double)factor
{
    for(PGActionMemory *memory in self.memory.allValues)
    {
        memory.value *= factor;
    }
}

- (NSArray<PGElementNode *> *)eligibleNodesIn:(NSArray<PGElementNode *> *)roots
{
    NSMutableArray<PGElementNode *> *eligible = [NSMutableArray array];
    for(PGElementNode *root in roots)
    {
        [self collectEligible:root into:eligible];
    }
    return eligible;
}

- (void)collectEligible:(PGElementNode *)node into:(NSMutableArray<PGElementNode *> *)eligible
{
    if([self nodeCanBeOperated:node] && [PGActionFilter includeNode:node kind:PGActionFilterEnabled visits:0 target:self.target])
    {
        [eligible addObject:node];
    }
    for(PGElementNode *child in node.children)
    {
        [self collectEligible:child into:eligible];
    }
}

- (BOOL)nodeCanBeOperated:(PGElementNode *)node
{
    return [PGActionFilter includeNode:node kind:PGActionFilterEnabled visits:0];
}

- (PGElementNode *)chooseFrom:(NSArray<PGElementNode *> *)eligible
{
    PGAgentKind kind = self.kind == PGAgentKindUnspecified ? PGAgentKindNStepQ : self.kind;
    if(kind == PGAgentKindSataRL && [self shouldExplore])
    {
        return eligible[arc4random_uniform((uint32_t)eligible.count)];
    }
    NSArray<PGElementNode *> *unvisited = [self unvisitedIn:eligible];
    NSArray<PGElementNode *> *fresh = [self nodes:unvisited knownToReuse:NO];
    if(fresh.count > 0)
    {
        return [self weightedNode:fresh];
    }
    NSArray<PGElementNode *> *promising = [self promisingReuseNodes:unvisited];
    if(promising.count > 0)
    {
        return [self nodeWithHighestScore:promising score:^double(PGElementNode *node) {
            double chance = [self.reuseModel fractionOfUnseenActivitiesForAction:[self keyForNode:node] seen:self.seenActivities];
            return 10.0 * chance - PGGumbelNoise();
        }];
    }
    if(unvisited.count > 0)
    {
        return unvisited[arc4random_uniform((uint32_t)unvisited.count)];
    }
    if(self.stallExploration > 0 && (double)arc4random_uniform(1000) / 1000.0 < self.stallExploration)
    {
        return eligible[arc4random_uniform((uint32_t)eligible.count)];
    }
    return [self nodeWithHighestScore:eligible score:^double(PGElementNode *node) {
        NSString *key = [self keyForNode:node];
        PGActionMemory *memory = self.memory[key];
        double value = memory.value;
        if(memory.visits < 1 && [self.reuseModel containsAction:key])
        {
            value += [self.reuseModel fractionOfUnseenActivitiesForAction:key seen:self.seenActivities];
        }
        return value / 0.1 - PGGumbelNoise();
    }];
}

- (NSArray<PGElementNode *> *)nodes:(NSArray<PGElementNode *> *)nodes knownToReuse:(BOOL)known
{
    NSMutableArray<PGElementNode *> *matched = [NSMutableArray array];
    for(PGElementNode *node in nodes)
    {
        BOOL contains = [self.reuseModel containsAction:[self keyForNode:node]];
        if(contains == known)
        {
            [matched addObject:node];
        }
    }
    return matched;
}

- (NSArray<PGElementNode *> *)promisingReuseNodes:(NSArray<PGElementNode *> *)nodes
{
    NSMutableArray<PGElementNode *> *matched = [NSMutableArray array];
    for(PGElementNode *node in nodes)
    {
        NSString *key = [self keyForNode:node];
        if(![self.reuseModel containsAction:key])
        {
            continue;
        }
        if([self.reuseModel fractionOfUnseenActivitiesForAction:key seen:self.seenActivities] > 0.0001)
        {
            [matched addObject:node];
        }
    }
    return matched;
}

- (PGElementNode *)weightedNode:(NSArray<PGElementNode *> *)nodes
{
    NSInteger total = 0;
    for(PGElementNode *node in nodes)
    {
        total += MAX([PGActionFilter priorityForNode:node], 1);
    }
    if(total <= 0)
    {
        return nodes.firstObject;
    }
    NSInteger ticket = (NSInteger)arc4random_uniform((uint32_t)total);
    NSInteger cursor = 0;
    for(PGElementNode *node in nodes)
    {
        cursor += MAX([PGActionFilter priorityForNode:node], 1);
        if(ticket < cursor)
        {
            return node;
        }
    }
    return nodes.lastObject;
}

- (PGElementNode *)nodeWithHighestScore:(NSArray<PGElementNode *> *)nodes
                                  score:(double (^)(PGElementNode *node))score
{
    PGElementNode *best = nodes.firstObject;
    double bestScore = score(best);
    for(PGElementNode *node in nodes)
    {
        double value = score(node);
        if(value > bestScore)
        {
            best = node;
            bestScore = value;
        }
    }
    return best;
}

- (BOOL)shouldExplore
{
    double unit = (double)(arc4random_uniform(100)) / 100.0;
    return unit < self.epsilon;
}

- (NSArray<PGElementNode *> *)unvisitedIn:(NSArray<PGElementNode *> *)nodes
{
    NSMutableArray<PGElementNode *> *unvisited = [NSMutableArray array];
    for(PGElementNode *node in nodes)
    {
        if(self.memory[[self keyForNode:node]].visits < 1)
        {
            [unvisited addObject:node];
        }
    }
    return unvisited;
}

- (void)absorbReward:(double)reward
{
    [self noteReward:reward];
    [self updateSarsaBootstrappingKey:nil];
}

- (void)noteReward:(double)reward
{
    if(self.latestKey.length == 0)
    {
        return;
    }
    [self.sarsaRewards addObject:@(reward)];
}

- (void)updateSarsaBootstrappingKey:(NSString *)newKey
{
    NSInteger count = MIN(self.sarsaActions.count, self.sarsaRewards.count);
    if(count == 0)
    {
        return;
    }
    double value = newKey.length > 0 ? self.memory[newKey].value : 0;
    for(NSInteger index = count - 1; index >= 0; index--)
    {
        value = self.sarsaRewards[index].doubleValue + self.discount * value;
        if(index == 0)
        {
            PGActionMemory *memory = self.memory[self.sarsaActions[index]];
            if(memory != nil)
            {
                double rate = self.learningRate > 0 ? self.learningRate : [PGExploreStrategy learningRateForObservations:self.graphObservations];
                memory.value += rate * (value - memory.value);
            }
        }
    }
}

- (double)reuseRewardForNodes:(NSArray<PGElementNode *> *)nodes stateVisits:(NSInteger)stateVisits
{
    if(self.latestKey.length == 0)
    {
        return 0;
    }
    double base = 1;
    if([self.reuseModel containsAction:self.latestKey])
    {
        base = [self.reuseModel fractionOfUnseenActivitiesForAction:self.latestKey seen:self.seenActivities];
    }
    base /= sqrt((double)[self memoryFor:self.latestKey].visits + 1.0);
    double expectation = 0;
    for(PGElementNode *node in [self eligibleNodesIn:nodes])
    {
        NSString *key = [self keyForNode:node];
        if(![self.reuseModel containsAction:key])
        {
            expectation += 1;
        }
        else if(self.memory[key].visits >= 1)
        {
            expectation += 0.5;
        }
        expectation += [self.reuseModel fractionOfUnseenActivitiesForAction:key seen:self.seenActivities];
    }
    NSInteger observed = stateVisits < 0 ? 0 : stateVisits;
    return base + expectation / sqrt((double)observed + 1.0);
}

- (void)rememberChoice:(NSString *)key
{
    PGActionMemory *chosen = [self memoryFor:key];
    self.storedStepCount += 1;
    chosen.visits += 1;
    chosen.lastVisit = [NSDate date];
    self.latestKey = key;
    [self.sarsaActions addObject:key ?: @""];
    while(self.sarsaActions.count > PGSarsaWindow)
    {
        [self.sarsaActions removeObjectAtIndex:0];
        if(self.sarsaRewards.count > 0)
        {
            [self.sarsaRewards removeObjectAtIndex:0];
        }
    }
}

- (NSString *)keyForNode:(PGElementNode *)node
{
    return [NSString stringWithFormat:@"%@|%@", self.activity ?: @"", PGNodeKey(node)];
}

- (PGActionMemory *)memoryFor:(NSString *)key
{
    if(key.length == 0)
    {
        key = @"";
    }
    PGActionMemory *memory = self.memory[key];
    if(memory == nil)
    {
        memory = [[PGActionMemory alloc] init];
        self.memory[key] = memory;
    }
    return memory;
}

- (NSString *)stateIDFor:(NSArray<PGElementNode *> *)roots activity:(NSString *)activity
{
    uint64_t hash = 1469598103934665603ULL;
    hash ^= (uint64_t)(activity ?: @"").hash;
    hash *= 1099511628211ULL;
    for(PGElementNode *root in roots)
    {
        hash ^= [root structureHashMixingIndex:YES];
        hash *= 1099511628211ULL;
    }
    return [NSString stringWithFormat:@"%llx", hash];
}

@end
