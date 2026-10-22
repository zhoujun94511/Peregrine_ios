#import "PGSceneLimit.h"

@implementation PGSceneLimit

- (BOOL)shouldCheck
{
    return self.state != PGSceneLimitStateIdle && self.state != PGSceneLimitStateStopped;
}

- (BOOL)allowsViewController:(NSString *)name
{
    if(![self shouldCheck])
    {
        return YES;
    }
    if(name.length == 0)
    {
        return NO;
    }
    if([self.blockViewControllers containsObject:name])
    {
        return NO;
    }
    if(self.allowViewControllers.count > 0 && ![self.allowViewControllers containsObject:name])
    {
        return NO;
    }
    if(self.duration > 0 && self.startedAt != nil)
    {
        NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:self.startedAt];
        if(elapsed > self.duration)
        {
            return NO;
        }
    }
    return YES;
}

- (NSUInteger)actionSource
{
    return self.state == PGSceneLimitStateInside ? 3 : 1;
}

@end
