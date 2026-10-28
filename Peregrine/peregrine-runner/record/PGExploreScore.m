#import "PGExploreScore.h"

@implementation PGExploreScore
{
    NSInteger _steps;
    NSInteger _actions;
    NSInteger _screenChanges;
    NSInteger _maxStreak;
    NSInteger _streak;
    NSInteger _outsideSteps;
    NSInteger _clicks;
    NSInteger _namedClicks;
    NSInteger _stripClicks;
    NSInteger _repeatClicks;
    uint64_t _lastFingerprint;
    NSMutableSet<NSNumber *> *_screens;
    NSMutableSet<NSString *> *_targets;
    NSMutableArray<NSNumber *> *_heights;
    NSMutableDictionary<NSString *, NSNumber *> *_acts;
}

- (instancetype)init
{
    self = [super init];
    if(self != nil)
    {
        _screens = [NSMutableSet set];
        _targets = [NSMutableSet set];
        _heights = [NSMutableArray array];
        _acts = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)noteSource:(NSString *)source activity:(NSString *)activity fingerprint:(uint64_t)fingerprint operate:(PGOperate *)operate bundleID:(NSString *)bundleID
{
    _steps += 1;
    BOOL outside = [source containsString:@"outside"];
    if(outside)
    {
        _outsideSteps += 1;
    }
    if(fingerprint != 0)
    {
        [_screens addObject:@(fingerprint)];
        if(_lastFingerprint != 0 && fingerprint != _lastFingerprint)
        {
            _screenChanges += 1;
            _streak = 1;
        }
        else
        {
            _streak += 1;
        }
        _maxStreak = MAX(_maxStreak, _streak);
        _lastFingerprint = fingerprint;
    }
    if(operate.act.length == 0)
    {
        return;
    }
    _actions += 1;
    NSString *act = operate.act.uppercaseString;
    _acts[act] = @(_acts[act].integerValue + 1);
    if([operate.act caseInsensitiveCompare:@"CLICK"] != NSOrderedSame)
    {
        return;
    }
    _clicks += 1;
    if(operate.text.length > 0)
    {
        _namedClicks += 1;
    }
    if(operate.rect.height > 0 && operate.rect.height < 20)
    {
        _stripClicks += 1;
    }
    if(operate.rect.height > 0)
    {
        [_heights addObject:@(operate.rect.height)];
    }
    NSString *target = [NSString stringWithFormat:@"%@|%@|%ld,%ld", operate.name ?: @"", operate.text ?: @"", (long)(operate.rect.left / 40), (long)(operate.rect.top / 40)];
    if([_targets containsObject:target])
    {
        _repeatClicks += 1;
    }
    [_targets addObject:target];
}

- (NSInteger)medianHeight
{
    if(_heights.count == 0)
    {
        return 0;
    }
    NSArray<NSNumber *> *sorted = [_heights sortedArrayUsingSelector:@selector(compare:)];
    return sorted[sorted.count / 2].integerValue;
}

- (NSDictionary *)fields
{
    NSInteger chances = MAX(_steps - 1, 1);
    return @{
        @"steps": @(_steps),
        @"actions": @(_actions),
        @"screen_changes": @(_screenChanges),
        @"change_rate": @((double)_screenChanges / (double)chances),
        @"distinct_screens": @(_screens.count),
        @"max_same_streak": @(_maxStreak),
        @"outside_steps": @(_outsideSteps),
        @"clicks": @(_clicks),
        @"named_clicks": @(_namedClicks),
        @"strip_clicks": @(_stripClicks),
        @"repeat_clicks": @(_repeatClicks),
        @"distinct_targets": @(_targets.count),
        @"median_click_height": @([self medianHeight]),
        @"acts": [_acts copy]
    };
}

- (NSString *)line
{
    NSDictionary *fields = [self fields];
    return [NSString stringWithFormat:@"explore score steps %@ actions %@ screen_changes %@ change_rate %.2f distinct_screens %@ max_same_streak %@ outside_steps %@ clicks %@ named_clicks %@ strip_clicks %@ repeat_clicks %@ distinct_targets %@ median_click_height %@ acts %@",
            fields[@"steps"], fields[@"actions"], fields[@"screen_changes"], [fields[@"change_rate"] doubleValue], fields[@"distinct_screens"], fields[@"max_same_streak"], fields[@"outside_steps"], fields[@"clicks"], fields[@"named_clicks"], fields[@"strip_clicks"], fields[@"repeat_clicks"], fields[@"distinct_targets"], fields[@"median_click_height"], [self actsText]];
}

- (NSString *)actsText
{
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for(NSString *act in [_acts.allKeys sortedArrayUsingSelector:@selector(compare:)])
    {
        [parts addObject:[NSString stringWithFormat:@"%@:%@", act, _acts[act]]];
    }
    return parts.count > 0 ? [parts componentsJoinedByString:@","] : @"-";
}

@end
