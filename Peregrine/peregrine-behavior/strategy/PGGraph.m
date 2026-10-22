#import "PGGraph.h"

@implementation PGState
@end

@implementation PGTransition
@end

static NSString *PGEdgeKey(PGState *from, NSString *actionID, PGState *to)
{
    return [NSString stringWithFormat:@"%@\n%@\n%@", from.key ?: @"", actionID ?: @"", to.key ?: @""];
}

@interface PGGraph ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, PGState *> *stateByKey;
@property (nonatomic, strong) NSMutableArray<PGTransition *> *edgeList;
@property (nonatomic, strong) NSMutableDictionary<NSString *, PGTransition *> *edgeByKey;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<PGTransition *> *> *edgesFrom;
@property (nonatomic, assign, readwrite) NSInteger observationCount;
@end

@implementation PGGraph

- (instancetype)init
{
    self = [super init];
    if(self != nil)
    {
        _stateByKey = [NSMutableDictionary dictionary];
        _edgeList = [NSMutableArray array];
        _edgeByKey = [NSMutableDictionary dictionary];
        _edgesFrom = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSArray<PGState *> *)states
{
    return self.stateByKey.allValues;
}

- (NSArray<PGTransition *> *)transitions
{
    return self.edgeList;
}

- (PGState *)stateForNodes:(NSArray<PGElementNode *> *)nodes
                  activity:(NSString *)activity
                   created:(BOOL *)created
{
    uint64_t hash = 1469598103934665603ULL;
    hash ^= (uint64_t)(activity ?: @"").hash;
    hash *= 1099511628211ULL;
    for(PGElementNode *node in nodes)
    {
        hash ^= [node structureHashMixingIndex:YES];
        hash *= 1099511628211ULL;
    }
    NSString *key = [NSString stringWithFormat:@"%@:%llx", activity ?: @"", hash];
    PGState *state = self.stateByKey[key];
    if(created != NULL)
    {
        *created = state == nil;
    }
    if(state == nil)
    {
        state = [[PGState alloc] init];
        state.key = key;
        state.activity = activity ?: @"";
        self.stateByKey[key] = state;
    }
    state.visits += 1;
    self.observationCount += 1;
    return state;
}

- (PGTransition *)transitionFrom:(PGState *)from actionID:(NSString *)actionID to:(PGState *)to
{
    return self.edgeByKey[PGEdgeKey(from, actionID, to)];
}

- (PGTransition *)addTransitionFrom:(PGState *)from actionID:(NSString *)actionID to:(PGState *)to
{
    NSString *key = PGEdgeKey(from, actionID, to);
    PGTransition *existing = self.edgeByKey[key];
    if(existing != nil)
    {
        return existing;
    }
    PGTransition *edge = [[PGTransition alloc] init];
    edge.from = from;
    edge.to = to;
    edge.actionID = actionID ?: @"";
    [self.edgeList addObject:edge];
    self.edgeByKey[key] = edge;
    NSString *fromKey = from.key ?: @"";
    NSMutableArray<PGTransition *> *outgoing = self.edgesFrom[fromKey];
    if(outgoing == nil)
    {
        outgoing = [NSMutableArray array];
        self.edgesFrom[fromKey] = outgoing;
    }
    [outgoing addObject:edge];
    return edge;
}

- (NSSet<NSString *> *)actionIDsTouchingStateKeys:(NSSet<NSString *> *)keys
{
    NSMutableSet<NSString *> *actions = [NSMutableSet set];
    for(NSString *fromKey in keys)
    {
        for(PGTransition *edge in self.edgesFrom[fromKey])
        {
            if(edge.actionID.length > 0 && [keys containsObject:edge.to.key])
            {
                [actions addObject:edge.actionID];
            }
        }
    }
    return actions;
}

@end
