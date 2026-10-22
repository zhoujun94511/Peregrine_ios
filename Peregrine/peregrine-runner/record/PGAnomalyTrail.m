#import "PGAnomalyTrail.h"

static const NSUInteger PGAnomalyRecentLimit = 8;

@interface PGAnomalyTrail ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *counts;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *recent;
@property (nonatomic, assign) BOOL crashPending;
@end

@implementation PGAnomalyTrail

- (instancetype)init
{
    self = [super init];
    if(self != nil)
    {
        _counts = [@{
            @"suspected_crash": @0,
            @"suspected_crash_restart": @0,
            @"action_timeout": @0
        } mutableCopy];
        _recent = [NSMutableArray array];
    }
    return self;
}

+ (NSArray<NSString *> *)reportedKinds
{
    return @[@"suspected_crash", @"suspected_crash_restart", @"action_timeout"];
}

- (void)noteEvent:(NSDictionary *)event
{
    NSString *type = [event[@"event_type"] isKindOfClass:[NSString class]] ? event[@"event_type"] : @"";
    NSDictionary *action = [event[@"action"] isKindOfClass:[NSDictionary class]] ? event[@"action"] : @{};
    if([type isEqualToString:@"action_start"])
    {
        self.crashPending = NO;
        [self.recent addObject:@{
            @"time": event[@"timestamp"] ?: @"",
            @"act": action[@"type"] ?: @"",
            @"target": action[@"target"] ?: @"",
            @"activity": event[@"activity"] ?: @""
        }];
        if(self.recent.count > PGAnomalyRecentLimit)
        {
            [self.recent removeObjectAtIndex:0];
        }
        return;
    }
    NSString *kind = nil;
    if([type isEqualToString:@"action_timeout"])
    {
        kind = type;
    }
    else if([type isEqualToString:@"app_state_changed"] && [event[@"result"] isKindOfClass:[NSString class]])
    {
        kind = event[@"result"];
    }
    if(kind.length == 0)
    {
        return;
    }
    BOOL crash = [kind hasPrefix:@"suspected_crash"];
    // The app may still be down on the next step; that is the same exit, not another one.
    if(crash && self.crashPending)
    {
        return;
    }
    self.crashPending = crash || self.crashPending;
    NSInteger count = self.counts[kind].integerValue + 1;
    self.counts[kind] = @(count);
    if(![[PGAnomalyTrail reportedKinds] containsObject:kind])
    {
        return;
    }
    NSDictionary *head = @{
        @"kind": kind,
        @"time": event[@"timestamp"] ?: @"",
        @"count": @(count),
        @"steps": @(self.recent.count)
    };
    NSLog(@"peregrine anomaly %@", [self jsonLine:head]);
    for(NSDictionary *step in self.recent)
    {
        NSLog(@"peregrine anomaly step %@", [self jsonLine:step]);
    }
    if(crash)
    {
        [self.recent removeAllObjects];
    }
}

- (NSString *)jsonLine:(NSDictionary *)object
{
    NSData *data = [NSJSONSerialization isValidJSONObject:object] ? [NSJSONSerialization dataWithJSONObject:object options:0 error:nil] : nil;
    return data == nil ? @"{}" : [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

- (NSDictionary *)fields
{
    return @{@"anomalies": [self.counts copy]};
}

- (NSString *)line
{
    NSMutableArray<NSString *> *kinds = [[PGAnomalyTrail reportedKinds] mutableCopy];
    for(NSString *kind in [self.counts.allKeys sortedArrayUsingSelector:@selector(compare:)])
    {
        if(![kinds containsObject:kind])
        {
            [kinds addObject:kind];
        }
    }
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for(NSString *kind in kinds)
    {
        [parts addObject:[NSString stringWithFormat:@"%@ %@", kind, self.counts[kind] ?: @0]];
    }
    return [NSString stringWithFormat:@"anomaly summary %@", [parts componentsJoinedByString:@" "]];
}

@end
