#import "PGCoverage.h"

@interface PGCoverage ()
@property (nonatomic, strong) NSMutableOrderedSet<NSString *> *activities;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *visits;
@end

@implementation PGCoverage

- (instancetype)init
{
    self = [super init];
    if(self != nil)
    {
        _activities = [NSMutableOrderedSet orderedSet];
        _visits = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSInteger)count
{
    return (NSInteger)self.activities.count;
}

- (void)recordActivity:(NSString *)activity
{
    if(activity.length == 0)
    {
        return;
    }
    [self.activities addObject:activity];
    self.visits[activity] = @(self.visits[activity].integerValue + 1);
}

- (NSString *)summary
{
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for(NSString *activity in self.activities)
    {
        [parts addObject:[NSString stringWithFormat:@"%@ x%ld", activity, (long)self.visits[activity].integerValue]];
    }
    return [NSString stringWithFormat:@"coverage %ld: %@",
            (long)self.count,
            [parts componentsJoinedByString:@", "]];
}

- (BOOL)writeSummaryToDirectory:(NSString *)directory error:(NSError **)error
{
    NSString *folder = directory.length > 0 ? directory : NSTemporaryDirectory();
    NSString *path = [folder stringByAppendingPathComponent:@"peregrine-coverage.txt"];
    NSString *body = [NSString stringWithFormat:@"%@\n%@\n", [NSDate date].description, [self summary]];
    return [body writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:error];
}

@end
