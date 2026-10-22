#import "PGSceneQueue.h"
#import "PGSceneLimit.h"

@interface PGQueuedScene : NSObject
@property (nonatomic, copy) NSString *scheme;
@property (nonatomic, copy) NSArray<NSString *> *allow;
@property (nonatomic, copy) NSArray<NSString *> *block;
@property (nonatomic, assign) NSTimeInterval start;
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, assign) BOOL finished;
@end

@implementation PGQueuedScene
@end

@interface PGSceneQueue ()
@property (nonatomic, copy) NSArray<PGQueuedScene *> *scenes;
@property (nonatomic, strong) NSDate *startedAt;
@property (nonatomic, assign) NSUInteger index;
@property (nonatomic, assign, readwrite) NSUInteger actionSource;
@property (nonatomic, copy, readwrite) NSString *activeScheme;
@property (nonatomic, copy, readwrite) NSArray<NSString *> *activeAllow;
@property (nonatomic, copy, readwrite) NSArray<NSString *> *activeBlock;
@end

@implementation PGSceneQueue

- (instancetype)initWithScenes:(NSArray *)scenes
{
    self = [super init];
    if(self != nil)
    {
        NSMutableArray<PGQueuedScene *> *parsed = [NSMutableArray array];
        for(id item in scenes)
        {
            if(![item isKindOfClass:[NSDictionary class]])
            {
                continue;
            }
            NSDictionary *raw = item;
            PGQueuedScene *scene = [[PGQueuedScene alloc] init];
            scene.scheme = [raw[@"scheme"] isKindOfClass:[NSString class]] ? raw[@"scheme"] : @"";
            scene.allow = [self names:raw[@"allow"]];
            scene.block = [self names:raw[@"block"]];
            scene.start = [raw[@"start"] doubleValue];
            scene.duration = [raw[@"duration"] doubleValue];
            if(scene.scheme.length > 0 || scene.allow.count > 0 || scene.block.count > 0 || scene.duration > 0)
            {
                [parsed addObject:scene];
            }
        }
        _scenes = parsed;
        _startedAt = [NSDate date];
        _actionSource = 1;
        _activeScheme = @"";
        _activeAllow = @[];
        _activeBlock = @[];
    }
    return self;
}

- (PGOperate *)restrictionForActivity:(NSString *)activity at:(NSDate *)now
{
    self.actionSource = 1;
    if(self.index >= self.scenes.count)
    {
        return nil;
    }
    PGQueuedScene *scene = self.scenes[self.index];
    NSTimeInterval elapsed = [now timeIntervalSinceDate:self.startedAt];
    if(elapsed < scene.start)
    {
        return nil;
    }
    if(scene.duration > 0 && elapsed > scene.start + scene.duration)
    {
        scene.finished = YES;
        self.index += 1;
        return [self restrictionForActivity:activity at:now];
    }
    self.actionSource = 3;
    self.activeScheme = scene.scheme ?: @"";
    self.activeAllow = scene.allow ?: @[];
    self.activeBlock = scene.block ?: @[];
    if(activity.length == 0)
    {
        return nil;
    }
    if([scene.block containsObject:activity])
    {
        return [self backOperate];
    }
    if(scene.allow.count > 0 && ![scene.allow containsObject:activity])
    {
        return [self backOperate];
    }
    return nil;
}

- (PGOperate *)backOperate
{
    PGOperate *back = [[PGOperate alloc] init];
    back.act = @"BACK";
    return back;
}

- (NSArray<NSString *> *)names:(id)value
{
    if(![value isKindOfClass:[NSArray class]])
    {
        return @[];
    }
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for(id item in (NSArray *)value)
    {
        if([item isKindOfClass:[NSString class]] && [(NSString *)item length] > 0)
        {
            [names addObject:item];
        }
    }
    return names;
}

@end
