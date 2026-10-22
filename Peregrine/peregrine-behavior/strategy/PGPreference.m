#import "PGPreference.h"
#import "PGBehavior.h"

@interface PGPreferenceRule : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSString *command;
@end

@implementation PGPreferenceRule
@end

@interface PGPreference ()
@property (nonatomic, strong) NSMutableArray<PGPreferenceRule *> *rules;
@property (nonatomic, copy) NSArray<NSDictionary *> *events;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *commandsByName;
@property (nonatomic, copy) NSDictionary<NSString *, NSDictionary *> *actionByName;
@property (nonatomic, strong) NSMutableArray<NSString *> *pendingCommands;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *remainingTimes;
@property (nonatomic, assign) BOOL pendingSuppressesModel;
@end

@implementation PGPreference

- (instancetype)init
{
    self = [super init];
    if(self != nil)
    {
        _rules = [NSMutableArray array];
        _events = @[];
        _commandsByName = @{};
        _actionByName = @{};
        _pendingCommands = [NSMutableArray array];
        _remainingTimes = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)addCommand:(NSString *)command matchingText:(NSString *)text
{
    if(command.length == 0 || text.length == 0)
    {
        return;
    }
    PGPreferenceRule *rule = [[PGPreferenceRule alloc] init];
    rule.text = text;
    rule.command = command;
    [self.rules addObject:rule];
}

- (void)loadEvents:(NSArray *)events actions:(NSArray *)actions
{
    self.events = [events isKindOfClass:[NSArray class]] ? events : @[];
    NSMutableDictionary<NSString *, NSNumber *> *limits = [NSMutableDictionary dictionary];
    [self.events enumerateObjectsUsingBlock:^(id item, NSUInteger index, BOOL *stop) {
        if(![item isKindOfClass:[NSDictionary class]] || ![item[@"times"] respondsToSelector:@selector(integerValue)])
        {
            return;
        }
        limits[[self timesKeyForEvent:item index:index]] = @([item[@"times"] integerValue]);
    }];
    self.remainingTimes = limits;
    NSMutableDictionary<NSString *, NSString *> *catalog = [NSMutableDictionary dictionary];
    for(id item in actions)
    {
        if(![item isKindOfClass:[NSDictionary class]])
        {
            continue;
        }
        NSString *name = ((NSDictionary *)item)[@"name"];
        NSString *command = ((NSDictionary *)item)[@"cmd"];
        if([name isKindOfClass:[NSString class]] && [command isKindOfClass:[NSString class]] && command.length > 0)
        {
            catalog[name.lowercaseString] = command;
        }
    }
    self.commandsByName = catalog;
    NSMutableDictionary<NSString *, NSDictionary *> *definitions = [NSMutableDictionary dictionary];
    for(id item in actions)
    {
        if(![item isKindOfClass:[NSDictionary class]])
        {
            continue;
        }
        NSString *name = ((NSDictionary *)item)[@"name"];
        if([name isKindOfClass:[NSString class]] && name.length > 0)
        {
            definitions[name.lowercaseString] = item;
        }
    }
    self.actionByName = definitions;
}

- (void)loadSequences:(NSArray *)sequences
{
    for(id item in [sequences isKindOfClass:[NSArray class]] ? sequences : @[])
    {
        NSArray *steps = nil;
        if([item isKindOfClass:[NSDictionary class]])
        {
            steps = [item[@"steps"] isKindOfClass:[NSArray class]] ? item[@"steps"] : @[];
        }
        else if([item isKindOfClass:[NSArray class]])
        {
            steps = item;
        }
        for(id step in steps)
        {
            NSString *command = [self commandForSequenceStep:step];
            if(command.length > 0)
            {
                [self.pendingCommands addObject:command];
            }
        }
    }
}

- (NSString *)commandForSequenceStep:(id)step
{
    if([step isKindOfClass:[NSString class]])
    {
        NSString *named = [self commandStringForActionNamed:step];
        return named.length > 0 ? named : step;
    }
    if([step isKindOfClass:[NSDictionary class]])
    {
        NSData *data = [NSJSONSerialization dataWithJSONObject:step options:0 error:nil];
        return data == nil ? nil : [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    return nil;
}

- (NSString *)commandMatchingScreenText:(NSString *)screenText
{
    PGPreferenceDecision *decision = [self decisionForScreenText:screenText nodes:@[] screenSize:CGSizeZero];
    return decision.kind == PGPreferenceDecisionCommand ? decision.command : nil;
}

- (PGPreferenceDecision *)decisionForNodes:(NSArray<PGElementNode *> *)nodes
                                 activity:(NSString *)activity
                               screenSize:(CGSize)screenSize
{
    return [self decisionForScreenText:[self screenTextForNodes:nodes activity:activity]
                                 nodes:nodes
                            screenSize:screenSize];
}

- (PGPreferenceDecision *)decisionForScreenText:(NSString *)screenText
                                         nodes:(NSArray<PGElementNode *> *)nodes
                                    screenSize:(CGSize)screenSize
{
    PGPreferenceDecision *decision = [[PGPreferenceDecision alloc] init];
    if(self.pendingSuppressesModel)
    {
        self.pendingSuppressesModel = NO;
        decision.kind = PGPreferenceDecisionSuppressModel;
        return decision;
    }
    if(self.pendingCommands.count > 0)
    {
        decision.kind = PGPreferenceDecisionCommand;
        decision.command = self.pendingCommands.firstObject;
        [self.pendingCommands removeObjectAtIndex:0];
        return decision;
    }
    [self enqueueMatchingEventForText:screenText nodes:nodes screenSize:screenSize];
    if(self.pendingSuppressesModel)
    {
        self.pendingSuppressesModel = NO;
        decision.kind = PGPreferenceDecisionSuppressModel;
        return decision;
    }
    if(self.pendingCommands.count > 0)
    {
        decision.kind = PGPreferenceDecisionCommand;
        decision.command = self.pendingCommands.firstObject;
        [self.pendingCommands removeObjectAtIndex:0];
        return decision;
    }
    for(PGPreferenceRule *rule in self.rules)
    {
        if(screenText.length > 0 && [screenText containsString:rule.text])
        {
            decision.kind = PGPreferenceDecisionCommand;
            decision.command = rule.command;
            return decision;
        }
    }
    decision.kind = PGPreferenceDecisionNone;
    return decision;
}

- (void)enqueueMatchingEventForText:(NSString *)screenText
                              nodes:(NSArray<PGElementNode *> *)nodes
                         screenSize:(CGSize)screenSize
{
    for(NSDictionary *event in self.events)
    {
        if(![event isKindOfClass:[NSDictionary class]] || ![self event:event matchesText:screenText nodes:nodes screenSize:screenSize])
        {
            continue;
        }
        [self consumeEvent:event];
        NSArray *names = [event[@"actions"] isKindOfClass:[NSArray class]] ? event[@"actions"] : @[];
        for(id name in names)
        {
            if(![name isKindOfClass:[NSString class]])
            {
                continue;
            }
            NSString *command = [self commandStringForActionNamed:name];
            if(command == nil)
            {
                if(self.pendingSuppressesModel)
                {
                    return;
                }
                continue;
            }
            if(command.length > 0)
            {
                [self.pendingCommands addObject:command];
            }
        }
        if(self.pendingCommands.count > 0 || self.pendingSuppressesModel)
        {
            return;
        }
    }
}

- (NSString *)commandStringForActionNamed:(NSString *)name
{
    NSDictionary *action = self.actionByName[name.lowercaseString];
    NSString *type = [action[@"type"] isKindOfClass:[NSString class]] ? [action[@"type"] lowercaseString] : @"xaction";
    NSString *command = [action[@"cmd"] isKindOfClass:[NSString class]] ? action[@"cmd"] : self.commandsByName[name.lowercaseString];
    if(command.length == 0)
    {
        command = name;
    }
    if([type isEqualToString:@"noaction"] || [command caseInsensitiveCompare:@"NO_CLICK"] == NSOrderedSame)
    {
        self.pendingSuppressesModel = YES;
        return nil;
    }
    if([type isEqualToString:@"posaction"] || [type isEqualToString:@"maction"])
    {
        NSMutableDictionary *body = [@{@"act": command.length > 0 ? command : @"CLICK"} mutableCopy];
        if([type isEqualToString:@"posaction"] && action[@"pos"] != nil)
        {
            body[@"pos"] = action[@"pos"];
        }
        if([type isEqualToString:@"maction"])
        {
            body[@"text"] = [action[@"text"] isKindOfClass:[NSString class]] ? action[@"text"] : @"";
            body[@"id"] = [action[@"id"] isKindOfClass:[NSString class]] ? action[@"id"] : @"";
        }
        [self applyDurationOfAction:action toBody:body];
        NSData *data = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
        return data == nil ? command : [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    NSMutableDictionary *body = [@{@"act": command} mutableCopy];
    [self applyDurationOfAction:action toBody:body];
    if(body[@"throttle"] == nil)
    {
        return command;
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    return data == nil ? command : [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

- (void)applyDurationOfAction:(NSDictionary *)action toBody:(NSMutableDictionary *)body
{
    if(![action[@"duration"] respondsToSelector:@selector(doubleValue)])
    {
        return;
    }
    double seconds = [action[@"duration"] doubleValue];
    if(seconds > 0)
    {
        body[@"throttle"] = @(seconds * 1000.0);
    }
}

- (BOOL)event:(NSDictionary *)event
  matchesText:(NSString *)screenText
        nodes:(NSArray<PGElementNode *> *)nodes
   screenSize:(CGSize)screenSize
{
    if([event[@"times"] respondsToSelector:@selector(integerValue)])
    {
        NSUInteger index = [self.events indexOfObjectIdenticalTo:event];
        NSInteger left = index == NSNotFound ? 0 : [self.remainingTimes[[self timesKeyForEvent:event index:index]] integerValue];
        if(left <= 0)
        {
            return NO;
        }
    }
    double rate = event[@"rate"] == nil ? 1.0 : [event[@"rate"] doubleValue];
    if(rate < 1.0)
    {
        double unit = (double)arc4random_uniform(1000) / 1000.0;
        if(unit >= rate)
        {
            return NO;
        }
    }
    NSString *text = screenText ?: @"";
    for(id excluded in [event[@"exclude"] isKindOfClass:[NSArray class]] ? event[@"exclude"] : @[])
    {
        if([excluded isKindOfClass:[NSString class]] && [(NSString *)excluded length] > 0 && [text containsString:excluded])
        {
            return NO;
        }
    }
    for(id required in [event[@"require"] isKindOfClass:[NSArray class]] ? event[@"require"] : @[])
    {
        if([required isKindOfClass:[NSString class]] && [(NSString *)required length] > 0 && ![text containsString:required])
        {
            return NO;
        }
    }
    return [self nodes:nodes satisfyROI:event[@"roi"] screenSize:screenSize];
}

- (NSString *)timesKeyForEvent:(NSDictionary *)event index:(NSUInteger)index
{
    id name = event[@"name"];
    if([name isKindOfClass:[NSString class]] && [(NSString *)name length] > 0)
    {
        return name;
    }
    return [NSString stringWithFormat:@"event-%lu", (unsigned long)index];
}

- (void)consumeEvent:(NSDictionary *)event
{
    if(![event[@"times"] respondsToSelector:@selector(integerValue)])
    {
        return;
    }
    NSUInteger index = [self.events indexOfObjectIdenticalTo:event];
    if(index == NSNotFound)
    {
        return;
    }
    NSString *key = [self timesKeyForEvent:event index:index];
    NSInteger left = [self.remainingTimes[key] integerValue];
    if(left > 0)
    {
        self.remainingTimes[key] = @(left - 1);
    }
}

- (BOOL)nodes:(NSArray<PGElementNode *> *)nodes satisfyROI:(id)roi screenSize:(CGSize)screenSize
{
    if(![roi isKindOfClass:[NSArray class]] || [(NSArray *)roi count] < 4 || screenSize.width <= 0 || screenSize.height <= 0)
    {
        return YES;
    }
    NSArray *box = roi;
    CGFloat left = [box[0] doubleValue] * screenSize.width;
    CGFloat top = [box[1] doubleValue] * screenSize.height;
    CGFloat right = [box[2] doubleValue] * screenSize.width;
    CGFloat bottom = [box[3] doubleValue] * screenSize.height;
    for(PGElementNode *node in [PGElementNode flattenedNodes:nodes])
    {
        CGFloat centerX = node.rect.left + node.rect.width / 2.0;
        CGFloat centerY = node.rect.top + node.rect.height / 2.0;
        if(centerX >= left && centerY >= top && centerX <= right && centerY <= bottom)
        {
            return YES;
        }
    }
    return NO;
}

- (NSString *)screenTextForNodes:(NSArray<PGElementNode *> *)nodes activity:(NSString *)activity
{
    NSMutableString *text = [NSMutableString string];
    if(activity.length > 0)
    {
        [text appendString:activity];
        [text appendString:@"\n"];
    }
    for(PGElementNode *node in nodes)
    {
        [self appendNode:node to:text];
    }
    return text;
}

- (void)appendNode:(PGElementNode *)node to:(NSMutableString *)text
{
    for(NSString *piece in @[node.type ?: @"", node.identifier ?: @"", node.label ?: @"", node.value ?: @"", node.controller ?: @""])
    {
        if(piece.length > 0)
        {
            [text appendString:piece];
            [text appendString:@"\n"];
        }
    }
    for(PGElementNode *child in node.children)
    {
        [self appendNode:child to:text];
    }
}

@end

@implementation PGPreferenceDecision
@end
