#import "PGStubWatch.h"

static const NSInteger PGStubEmptyTreeLimit = 5;
static const NSTimeInterval PGStubReprobeSeconds = 4;

@implementation PGStubWatch
{
    PGStubClient *_client;
    NSInteger _port;
    NSString *_bundleID;
    NSInteger _emptyTrees;
}

- (instancetype)initWithClient:(PGStubClient *)client port:(NSInteger)port bundleID:(NSString *)bundleID
{
    self = [super init];
    if(self != nil)
    {
        _client = client;
        _port = port;
        _bundleID = [bundleID copy];
    }
    return self;
}

- (BOOL)probeAtLaunch
{
    _alive = _port > 0 && [self probeWithin:8] && [self ownedByTarget];
    _emptyTrees = 0;
    return _alive;
}

- (BOOL)ownedByTarget
{
    dispatch_semaphore_t gate = dispatch_semaphore_create(0);
    __block NSDictionary *info = nil;
    [_client fetchAppInfoOnPort:_port completion:^(NSDictionary *result) {
        info = result;
        dispatch_semaphore_signal(gate);
    }];
    dispatch_semaphore_wait(gate, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6 * NSEC_PER_SEC)));
    NSString *owner = [info[@"bundle_id"] isKindOfClass:[NSString class]] ? info[@"bundle_id"] : @"";
    if(owner.length == 0)
    {
        NSLog(@"stub app_info unavailable on port %ld, port trusted", (long)_port);
        return YES;
    }
    if(_bundleID.length > 0 && ![owner isEqualToString:_bundleID])
    {
        NSLog(@"stub port %ld belongs to %@, not %@; stub not used", (long)_port, owner, _bundleID);
        return NO;
    }
    NSLog(@"stub app_info success %@", owner);
    return YES;
}

- (PGStubTreeVerdict)noteTree:(NSArray *)tree
{
    if(!_alive)
    {
        return PGStubTreeKeep;
    }
    if(tree.count > 0)
    {
        _emptyTrees = 0;
        return PGStubTreeKeep;
    }
    _emptyTrees += 1;
    if(_emptyTrees == 1)
    {
        if([self probeWithin:PGStubReprobeSeconds])
        {
            NSLog(@"stub empty tree, probe alive, fetch again");
            return PGStubTreeRetry;
        }
        return PGStubTreeKeep;
    }
    if(_emptyTrees < PGStubEmptyTreeLimit)
    {
        return PGStubTreeKeep;
    }
    _emptyTrees = 0;
    if([self probeWithin:PGStubReprobeSeconds])
    {
        NSLog(@"stub empty tree x%ld, probe alive, keep stub", (long)PGStubEmptyTreeLimit);
        return PGStubTreeKeep;
    }
    _alive = NO;
    NSLog(@"stub lost on port %ld", (long)_port);
    return PGStubTreeLost;
}

- (BOOL)probeWithin:(NSTimeInterval)seconds
{
    dispatch_semaphore_t gate = dispatch_semaphore_create(0);
    __block BOOL alive = NO;
    [_client probeOnPort:_port within:seconds completion:^(BOOL ok) {
        alive = ok;
        dispatch_semaphore_signal(gate);
    }];
    dispatch_semaphore_wait(gate, dispatch_time(DISPATCH_TIME_NOW, (int64_t)((seconds + 4) * NSEC_PER_SEC)));
    return alive;
}

@end
