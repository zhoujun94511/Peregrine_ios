#import "PGReuseModel.h"

@interface PGReuseModel ()
@property (nonatomic, copy, readwrite, nullable) NSString *filePath;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, NSNumber *> *> *actions;
@end

@implementation PGReuseModel

- (instancetype)init
{
    self = [super init];
    if(self != nil)
    {
        _actions = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)loadFromDirectory:(NSString *)directory bundleID:(NSString *)bundleID
{
    if(bundleID.length == 0)
    {
        self.filePath = nil;
        return;
    }
    NSString *folder = directory.length > 0 ? directory : NSTemporaryDirectory();
    NSString *safe = [bundleID stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    self.filePath = [folder stringByAppendingPathComponent:[NSString stringWithFormat:@"peregrine-%@.reuse.json", safe]];
    NSData *data = [NSData dataWithContentsOfFile:self.filePath];
    id json = data == nil ? nil : [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSDictionary *stored = [json isKindOfClass:[NSDictionary class]] ? ((NSDictionary *)json)[@"actions"] : nil;
    if(![stored isKindOfClass:[NSDictionary class]])
    {
        return;
    }
    [stored enumerateKeysAndObjectsUsingBlock:^(id key, id object, BOOL *stop) {
        if(![key isKindOfClass:[NSString class]] || ![object isKindOfClass:[NSDictionary class]])
        {
            return;
        }
        NSMutableDictionary<NSString *, NSNumber *> *counts = [NSMutableDictionary dictionary];
        [(NSDictionary *)object enumerateKeysAndObjectsUsingBlock:^(id activity, id times, BOOL *innerStop) {
            if([activity isKindOfClass:[NSString class]] && [times respondsToSelector:@selector(integerValue)])
            {
                counts[activity] = @([times integerValue]);
            }
        }];
        if(counts.count > 0)
        {
            self.actions[key] = counts;
        }
    }];
}

- (void)save
{
    if(self.filePath.length == 0)
    {
        return;
    }
    NSString *directory = [self.filePath stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    NSDictionary *body = @{@"version": @1, @"actions": self.actions ?: @{}};
    if(![NSJSONSerialization isValidJSONObject:body])
    {
        return;
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    [data writeToFile:self.filePath atomically:YES];
}

- (void)noteAction:(NSString *)actionID reachedActivity:(NSString *)activity
{
    if(actionID.length == 0 || activity.length == 0)
    {
        return;
    }
    NSMutableDictionary<NSString *, NSNumber *> *counts = self.actions[actionID];
    if(counts == nil)
    {
        counts = [NSMutableDictionary dictionary];
        self.actions[actionID] = counts;
    }
    counts[activity] = @(counts[activity].integerValue + 1);
}

- (BOOL)containsAction:(NSString *)actionID
{
    return actionID.length > 0 && self.actions[actionID] != nil;
}

- (double)fractionOfUnseenActivitiesForAction:(NSString *)actionID seen:(NSSet<NSString *> *)seen
{
    NSDictionary<NSString *, NSNumber *> *counts = self.actions[actionID];
    if(counts.count == 0)
    {
        return 0;
    }
    NSInteger total = 0;
    NSInteger unseen = 0;
    for(NSString *activity in counts)
    {
        NSInteger times = counts[activity].integerValue;
        total += times;
        if(seen == nil || ![seen containsObject:activity])
        {
            unseen += times;
        }
    }
    if(total <= 0 || unseen <= 0)
    {
        return 0;
    }
    return (double)unseen / (double)total;
}

@end
