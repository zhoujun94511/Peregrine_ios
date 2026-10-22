#import "PGSession.h"

@implementation PGGesture

+ (PGGesture *)gestureForOperate:(PGOperate *)operate
{
    PGGesture *gesture = [[PGGesture alloc] init];
    gesture.duration = operate.throttle > 0 ? operate.throttle / 1000.0 : 0.3;
    NSString *act = operate.act.uppercaseString ?: @"";
    if([act isEqualToString:@"RESTART"])
    {
        gesture.kind = PGGestureKindRestart;
        return gesture;
    }
    if([act isEqualToString:@"BACK"])
    {
        gesture.kind = PGGestureKindBack;
        return gesture;
    }
    if([act isEqualToString:@"HOME"])
    {
        gesture.kind = PGGestureKindHome;
        return gesture;
    }
    if([act isEqualToString:@"START"])
    {
        gesture.kind = PGGestureKindLaunch;
        return gesture;
    }
    if([act isEqualToString:@"TERMINATE"])
    {
        gesture.kind = PGGestureKindTerminate;
        return gesture;
    }
    if([act isEqualToString:@"SWIPE"])
    {
        gesture.kind = PGGestureKindSwipe;
        gesture.start = operate.rect;
        PGElementRect end = operate.rect;
        end.top = operate.rect.top + MAX(operate.rect.height / 2, 1);
        gesture.end = end;
        return gesture;
    }
    if([act isEqualToString:@"CLICK"] && operate.rect.width > 0 && operate.rect.height > 0)
    {
        gesture.kind = PGGestureKindTap;
        PGElementRect point = operate.rect;
        point.left = operate.rect.left + operate.rect.width / 2;
        point.top = operate.rect.top + operate.rect.height / 2;
        point.width = 1;
        point.height = 1;
        gesture.start = point;
        gesture.end = point;
        return gesture;
    }
    gesture.kind = PGGestureKindNone;
    return gesture;
}

@end

@implementation PGSession

- (NSArray<NSNumber *> *)startupSteps
{
    NSMutableArray<NSNumber *> *steps = [NSMutableArray arrayWithObjects:
        @(PGSessionStepLoadConfig),
        @(PGSessionStepStartCommandServer),
        @(PGSessionStepPrepareApps),
        @(PGSessionStepHome),
        @(PGSessionStepLaunchApp),
        nil];
    if(self.dataPort > 0)
    {
        [steps addObject:@(PGSessionStepProbeStub)];
    }
    if(self.algorithmNative)
    {
        [steps addObject:@(PGSessionStepRun)];
    }
    else
    {
        [steps addObject:@(PGSessionStepStop)];
    }
    return steps;
}

+ (instancetype)sessionFromEnvironment:(NSDictionary *)environment
{
    id bundleValue = environment[@"PEREGRINE_BUNDLEID"];
    if(![bundleValue isKindOfClass:[NSString class]] || [(NSString *)bundleValue length] == 0)
    {
        return nil;
    }
    PGSession *session = [[PGSession alloc] init];
    session.bundleID = bundleValue;
    session.durationMinutes = [self integerFromEnvironment:environment key:@"PEREGRINE_DURATION" fallback:1];
    session.throttleMilliseconds = [self integerFromEnvironment:environment key:@"PEREGRINE_THROTTLE" fallback:300];
    session.dataPort = [self integerFromEnvironment:environment key:@"PEREGRINE_DATAPORT" fallback:0];
    session.algorithmNative = YES;
    session.startedAt = [NSDate date];
    return session;
}

+ (NSDictionary<NSString *, NSString *> *)launchEnvironmentFromEncoded:(NSString *)encoded
{
    NSMutableDictionary<NSString *, NSString *> *environment = [NSMutableDictionary dictionary];
    for(NSString *pair in [encoded componentsSeparatedByString:@":"])
    {
        NSRange split = [pair rangeOfString:@"="];
        if(split.location == NSNotFound || split.location == 0)
        {
            continue;
        }
        environment[[pair substringToIndex:split.location]] = [pair substringFromIndex:split.location + 1];
    }
    return environment;
}

+ (NSInteger)integerFromEnvironment:(NSDictionary *)environment key:(NSString *)key fallback:(NSInteger)fallback
{
    id value = environment[key];
    if(![value respondsToSelector:@selector(integerValue)])
    {
        return fallback;
    }
    NSInteger number = [value integerValue];
    return number > 0 ? number : fallback;
}

- (BOOL)timeIsUp
{
    if(self.startedAt == nil || self.durationMinutes <= 0)
    {
        return NO;
    }
    NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:self.startedAt];
    return elapsed >= (NSTimeInterval)self.durationMinutes * 60.0;
}

@end
