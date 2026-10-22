#import "PGCaseSchedule.h"

static const NSInteger PGCaseFailLimit = 3;

@interface PGScheduledCase : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *schema;
@property (nonatomic, assign) NSTimeInterval timeout;
@property (nonatomic, assign) BOOL restart;
@property (nonatomic, copy) NSArray *steps;
@property (nonatomic, assign) NSUInteger stepIndex;
@property (nonatomic, assign) BOOL schemaSent;
@property (nonatomic, assign) NSInteger failCount;
@property (nonatomic, strong) NSDate *startedAt;
@end

@implementation PGScheduledCase
@end

@interface PGCaseSchedule ()
@property (nonatomic, copy) NSArray<PGScheduledCase *> *cases;
@property (nonatomic, assign) NSUInteger index;
@property (nonatomic, assign, readwrite) NSInteger failCount;
@end

@implementation PGCaseSchedule

- (instancetype)initWithCases:(NSArray *)cases
{
    self = [super init];
    if(self != nil)
    {
        NSMutableArray<PGScheduledCase *> *parsed = [NSMutableArray array];
        for(id item in cases)
        {
            if(![item isKindOfClass:[NSDictionary class]])
            {
                continue;
            }
            NSDictionary *raw = item;
            PGScheduledCase *scheduled = [[PGScheduledCase alloc] init];
            scheduled.name = [raw[@"name"] isKindOfClass:[NSString class]] ? raw[@"name"] : @"";
            scheduled.schema = [raw[@"schema"] isKindOfClass:[NSString class]] ? raw[@"schema"] : @"";
            scheduled.timeout = [raw[@"timeout"] doubleValue];
            scheduled.restart = [raw[@"restart"] boolValue];
            scheduled.steps = [raw[@"steps"] isKindOfClass:[NSArray class]] ? raw[@"steps"] : @[];
            scheduled.startedAt = [NSDate date];
            if(scheduled.timeout > 0 || scheduled.steps.count > 0 || scheduled.schema.length > 0)
            {
                [parsed addObject:scheduled];
            }
        }
        _cases = parsed;
    }
    return self;
}

- (PGOperate *)dueOperateAt:(NSDate *)now allowsRestart:(BOOL)allowsRestart
{
    if(self.index >= self.cases.count)
    {
        return nil;
    }
    PGScheduledCase *current = self.cases[self.index];
    self.failCount = current.failCount;
    if(current.failCount >= PGCaseFailLimit)
    {
        [self advanceAt:now];
        return [self dueOperateAt:now allowsRestart:allowsRestart];
    }
    if(current.schema.length > 0 && !current.schemaSent)
    {
        current.schemaSent = YES;
        PGOperate *enter = [[PGOperate alloc] init];
        enter.act = @"SCHEMA";
        enter.name = current.schema;
        enter.text = current.name;
        return enter;
    }
    if(current.stepIndex < current.steps.count)
    {
        id raw = current.steps[current.stepIndex];
        current.stepIndex += 1;
        if(![raw isKindOfClass:[NSDictionary class]])
        {
            current.failCount += 1;
            return [self dueOperateAt:now allowsRestart:allowsRestart];
        }
        PGOperate *step = [PGOperate operateFromDictionary:raw];
        step.name = step.name.length > 0 ? step.name : current.name;
        return step;
    }
    if(current.timeout <= 0)
    {
        [self advanceAt:now];
        return nil;
    }
    NSTimeInterval elapsed = [now timeIntervalSinceDate:current.startedAt];
    if(elapsed < current.timeout)
    {
        return nil;
    }
    BOOL restart = current.restart && allowsRestart;
    NSString *name = current.name;
    [self advanceAt:now];
    if(!restart)
    {
        return nil;
    }
    PGOperate *operate = [PGOperate restart];
    operate.name = name;
    return operate;
}

- (void)noteStepFailed
{
    if(self.index >= self.cases.count)
    {
        return;
    }
    self.cases[self.index].failCount += 1;
    self.failCount = self.cases[self.index].failCount;
}

- (void)advanceAt:(NSDate *)now
{
    self.index += 1;
    if(self.index < self.cases.count)
    {
        self.cases[self.index].startedAt = now;
    }
}

@end
