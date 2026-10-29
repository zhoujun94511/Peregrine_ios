#import "PGBlockRecovery.h"

static const NSInteger PGBlockStreakLimit = 4;
static const NSInteger PGCycleWindow = 8;
static const NSInteger PGCycleDistinctLimit = 3;
static const NSInteger PGCycleStagnantSteps = 8;
static const NSInteger PGCycleAvoidSteps = 3;
// Long enough that a screen left by restart is not killed again on the way back
// (the 20-minute StubDemo loop returned in well under a minute) and short enough
// that a later wedge can still restart. One step is one call into the guard.
static const NSInteger PGRestartCooldownSteps = 60;

@interface PGCycleGuard ()
@property (nonatomic, strong) NSMutableArray<NSString *> *window;
@property (nonatomic, assign, readwrite) NSInteger stepsSinceNewState;
@property (nonatomic, assign) NSInteger escapeStage;
@property (nonatomic, assign) NSInteger avoidRemaining;
@property (nonatomic, assign) BOOL waiting;
@property (nonatomic, copy, nullable) NSSet<NSString *> *stuckKeys;
// Each entry is @{ @"keys": NSSet, @"steps": NSNumber }. reset does not clear this:
// restart itself calls reset, and that is the moment the cooldown has to survive.
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *restartCooldowns;
// Keys from a RESTART this step. confirmRestartIssued arms the cooldown; the next
// noteStateKey drops the set when that restart never ran.
@property (nonatomic, copy, nullable) NSSet<NSString *> *pendingRestartKeys;
@end

@implementation PGCycleGuard

- (instancetype)init
{
    self = [super init];
    if(self != nil)
    {
        _window = [NSMutableArray array];
        _restartCooldowns = [NSMutableArray array];
    }
    return self;
}

- (void)tickRestartCooldowns
{
    NSMutableArray<NSMutableDictionary *> *alive = [NSMutableArray array];
    for(NSMutableDictionary *entry in self.restartCooldowns)
    {
        NSInteger steps = [entry[@"steps"] integerValue] - 1;
        if(steps > 0)
        {
            entry[@"steps"] = @(steps);
            [alive addObject:entry];
        }
    }
    [self.restartCooldowns removeAllObjects];
    [self.restartCooldowns addObjectsFromArray:alive];
}

- (BOOL)restartCoolingCoversKeys:(NSSet<NSString *> *)keys
{
    if(keys.count == 0)
    {
        return NO;
    }
    for(NSDictionary *entry in self.restartCooldowns)
    {
        NSSet<NSString *> *cooled = entry[@"keys"];
        if([cooled isKindOfClass:[NSSet class]] && [keys isSubsetOfSet:cooled])
        {
            return YES;
        }
    }
    return NO;
}

- (void)rememberRestartKeys:(NSSet<NSString *> *)keys
{
    if(keys.count == 0)
    {
        return;
    }
    [self.restartCooldowns addObject:[@{@"keys": [keys copy], @"steps": @(PGRestartCooldownSteps)} mutableCopy]];
    NSLog(@"cycle escape cooldown steps %ld", (long)PGRestartCooldownSteps);
}

- (void)confirmRestartIssued
{
    if(self.pendingRestartKeys.count == 0)
    {
        return;
    }
    [self rememberRestartKeys:self.pendingRestartKeys];
    self.pendingRestartKeys = nil;
}

- (NSArray<NSString *> *)recentStateKeys
{
    return self.window;
}

- (void)reset
{
    [self.window removeAllObjects];
    self.stepsSinceNewState = 0;
    self.escapeStage = 0;
    self.avoidRemaining = 0;
    self.waiting = NO;
    self.stuckKeys = nil;
}

- (PGCycleEscape)noteStateKey:(NSString *)key created:(BOOL)created
{
    self.pendingRestartKeys = nil;
    [self tickRestartCooldowns];
    NSString *current = key ?: @"";
    if(created || (self.stuckKeys != nil && ![self.stuckKeys containsObject:current]))
    {
        [self reset];
        [self.window addObject:current];
        return PGCycleEscapeNone;
    }
    [self.window addObject:current];
    while(self.window.count > PGCycleWindow)
    {
        [self.window removeObjectAtIndex:0];
    }
    self.stepsSinceNewState += 1;
    if(self.avoidRemaining > 0)
    {
        self.avoidRemaining -= 1;
        return PGCycleEscapeAvoid;
    }
    if(self.stuckKeys == nil)
    {
        NSSet<NSString *> *distinct = [NSSet setWithArray:self.window];
        if(self.stepsSinceNewState < PGCycleStagnantSteps || self.window.count < PGCycleWindow || distinct.count > PGCycleDistinctLimit)
        {
            return PGCycleEscapeNone;
        }
        if([self restartCoolingCoversKeys:distinct])
        {
            return PGCycleEscapeNone;
        }
        self.stuckKeys = distinct;
        self.escapeStage = 1;
        self.avoidRemaining = PGCycleAvoidSteps - 1;
        return PGCycleEscapeAvoid;
    }
    if(self.waiting)
    {
        self.waiting = NO;
        return PGCycleEscapeNone;
    }
    self.waiting = YES;
    self.escapeStage += 1;
    switch(self.escapeStage)
    {
        case 2:
            return PGCycleEscapeBack;
        case 3:
            return PGCycleEscapeCorner;
        case 4:
            return PGCycleEscapeDismiss;
        default:
            if([self restartCoolingCoversKeys:self.stuckKeys])
            {
                [self reset];
                [self.window addObject:current];
                return PGCycleEscapeNone;
            }
            self.pendingRestartKeys = [self.stuckKeys copy];
            [self reset];
            return PGCycleEscapeRestart;
    }
}

@end

@interface PGBlockRecovery ()
@property (nonatomic, copy) NSString *signature;
@property (nonatomic, assign) NSInteger streak;
@property (nonatomic, assign) NSInteger stage;
@property (nonatomic, strong) NSMutableSet<NSString *> *exhausted;
// Set when the RESTART operate actually runs. Armed into restartCooldown only after
// a different signature shows the restart left. Staying put still takes the gave-up path.
@property (nonatomic, copy) NSString *restartedSignature;
// Set when this step asks for RESTART. Dropped on the next step unless confirmRestartIssued
// runs, so a restart that was replaced by another command does not cool the screen.
@property (nonatomic, copy) NSString *pendingRestartSignature;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *restartCooldown;
// Identified controls of the screen the current signature belongs to.
@property (nonatomic, copy, nullable) NSSet<NSString *> *controlAnchor;
@end

// The last escalation has run; seeing the same screen once more means recovery cannot leave it.
static const NSInteger PGBlockStageDone = 3;

@implementation PGBlockRecovery

- (instancetype)init
{
    self = [super init];
    if(self != nil)
    {
        _exhausted = [NSMutableSet set];
        _restartCooldown = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)tickRestartCooldown
{
    NSMutableDictionary<NSString *, NSNumber *> *next = [NSMutableDictionary dictionary];
    for(NSString *key in self.restartCooldown)
    {
        NSInteger steps = self.restartCooldown[key].integerValue - 1;
        if(steps > 0)
        {
            next[key] = @(steps);
        }
    }
    self.restartCooldown = next;
}

- (void)armRestartCooldownLeavingTo:(NSString *)current
{
    if(self.restartedSignature.length == 0 || [self.restartedSignature isEqualToString:current])
    {
        return;
    }
    self.restartCooldown[self.restartedSignature] = @(PGRestartCooldownSteps);
    NSLog(@"block recovery cooldown %@ steps %ld", self.restartedSignature, (long)PGRestartCooldownSteps);
    self.restartedSignature = nil;
}

+ (NSString *)signatureForActivity:(NSString *)activity fingerprint:(uint64_t)fingerprint
{
    if(fingerprint != 0)
    {
        return [NSString stringWithFormat:@"%llx", fingerprint];
    }
    return activity ?: @"";
}

+ (NSSet<NSString *> *)controlKeysInNodes:(NSArray<PGElementNode *> *)nodes
{
    NSMutableSet<NSString *> *keys = [NSMutableSet set];
    for(PGElementNode *node in [PGElementNode flattenedNodes:nodes])
    {
        if(!node.clickable || node.identifier.length == 0)
        {
            continue;
        }
        [keys addObject:[NSString stringWithFormat:@"%@|%@", node.type ?: @"", node.identifier]];
    }
    return keys;
}

+ (NSString *)controlSignatureForKeys:(NSSet<NSString *> *)keys
                               anchor:(NSSet<NSString *> *)anchor
                             keptKeys:(NSSet<NSString *> * _Nullable *)keptKeys
{
    NSSet<NSString *> *current = keys ?: [NSSet set];
    // Two or three named controls also occur on unrelated screens, so a smaller set stays on the pixel hash.
    if(current.count < 4)
    {
        if(keptKeys != NULL)
        {
            *keptKeys = nil;
        }
        return nil;
    }
    NSSet<NSString *> *basis = current;
    if(anchor.count >= 4)
    {
        NSInteger shared = 0;
        for(NSString *key in current)
        {
            if([anchor containsObject:key])
            {
                shared += 1;
            }
        }
        NSInteger added = current.count - shared;
        NSInteger removed = anchor.count - shared;
        // One animated control can appear or disappear. A tab change replaces more than that.
        if(added + removed <= 1 && shared >= 4)
        {
            basis = anchor;
        }
    }
    if(keptKeys != NULL)
    {
        *keptKeys = basis;
    }
    NSArray<NSString *> *ordered = [basis.allObjects sortedArrayUsingSelector:@selector(compare:)];
    uint64_t hash = 1469598103934665603ULL;
    for(NSString *key in ordered)
    {
        NSData *bytes = [key dataUsingEncoding:NSUTF8StringEncoding];
        const uint8_t *raw = bytes.bytes;
        for(NSUInteger index = 0; index < bytes.length; index++)
        {
            hash ^= raw[index];
            hash *= 1099511628211ULL;
        }
        hash ^= 0x1f;
        hash *= 1099511628211ULL;
    }
    return [NSString stringWithFormat:@"c:%llx", hash];
}

- (NSString *)signatureForNodes:(NSArray<PGElementNode *> *)nodes fingerprint:(uint64_t)fingerprint activity:(NSString *)activity
{
    NSSet<NSString *> *kept = nil;
    NSString *signature = [PGBlockRecovery controlSignatureForKeys:[PGBlockRecovery controlKeysInNodes:nodes] anchor:self.controlAnchor keptKeys:&kept];
    self.controlAnchor = kept;
    if(signature.length > 0)
    {
        return signature;
    }
    return [PGBlockRecovery signatureForActivity:activity fingerprint:fingerprint];
}

- (BOOL)matchesSignature:(NSString *)signature
{
    return self.signature.length > 0 && [self.signature isEqualToString:signature ?: @""];
}

- (PGOperate *)noteSignature:(NSString *)signature allowsRestart:(BOOL)allowsRestart
{
    NSString *current = signature ?: @"";
    self.pendingRestartSignature = nil;
    [self tickRestartCooldown];
    if(![self.signature isEqualToString:current])
    {
        [self armRestartCooldownLeavingTo:current];
    }
    if([self.exhausted containsObject:current] || self.restartCooldown[current] != nil)
    {
        self.signature = current;
        self.streak = 0;
        self.stage = 0;
        return nil;
    }
    if([self.signature isEqualToString:current])
    {
        self.streak += 1;
    }
    else
    {
        self.signature = current;
        self.streak = 1;
        self.stage = 0;
        return nil;
    }
    if(self.stage == PGBlockStageDone)
    {
        NSLog(@"block recovery gave up on %@", current);
        [self.exhausted addObject:current];
        self.restartedSignature = nil;
        self.streak = 0;
        self.stage = 0;
        return nil;
    }
    if(self.stage == 0 && self.streak < PGBlockStreakLimit)
    {
        return nil;
    }
    self.streak = 0;
    PGOperate *operate = [[PGOperate alloc] init];
    if(self.stage == 0)
    {
        operate.act = @"SWIPE_UP";
        self.stage = 1;
    }
    else if(self.stage == 1)
    {
        operate.act = @"FORCE_BACK";
        self.stage = allowsRestart ? 2 : PGBlockStageDone;
    }
    else
    {
        operate = [PGOperate restart];
        self.stage = PGBlockStageDone;
        self.pendingRestartSignature = current;
    }
    return operate;
}

- (void)confirmRestartIssued
{
    if(self.pendingRestartSignature.length == 0)
    {
        return;
    }
    self.restartedSignature = self.pendingRestartSignature;
    self.pendingRestartSignature = nil;
}

@end
