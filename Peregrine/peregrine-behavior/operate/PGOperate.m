#import "PGOperate.h"

@implementation PGOperate

- (NSDictionary *)dictionary
{
    return @{
        @"act": self.act ?: @"",
        @"pos": @[@(self.rect.left), @(self.rect.top), @(self.rect.width), @(self.rect.height)],
        @"sid": self.stateID ?: @"",
        @"aid": self.actionID ?: @"",
        @"waitTime": @(self.waitTime),
        @"throttle": @(self.throttle),
        @"name": self.name ?: @"",
        @"text": self.text ?: @""
    };
}

- (NSString *)jsonString
{
    NSData *data = [NSJSONSerialization dataWithJSONObject:[self dictionary] options:0 error:nil];
    if(data == nil)
    {
        return @"";
    }
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    if(json.length > 2000)
    {
        return @"";
    }
    return json;
}

+ (PGOperate *)restart
{
    PGOperate *operate = [[PGOperate alloc] init];
    operate.act = @"RESTART";
    operate.stateID = @"g0s2";
    operate.actionID = @"g0a9";
    return operate;
}

+ (PGOperate *)clickOnNode:(PGElementNode *)node
{
    PGOperate *operate = [[PGOperate alloc] init];
    operate.act = @"CLICK";
    operate.rect = node.rect;
    operate.name = node.type;
    operate.text = node.label.length > 0 ? node.label : node.value;
    return operate;
}

+ (PGOperate *)operateFromCommand:(NSString *)command
{
    if(command.length == 0)
    {
        return nil;
    }
    NSData *data = [command dataUsingEncoding:NSUTF8StringEncoding];
    id json = data == nil ? nil : [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if([json isKindOfClass:[NSDictionary class]])
    {
        return [self operateFromDictionary:json];
    }
    PGOperate *operate = [[PGOperate alloc] init];
    operate.act = command;
    return operate;
}

+ (PGOperate *)operateFromDictionary:(NSDictionary *)json
{
    if(![json isKindOfClass:[NSDictionary class]])
    {
        return nil;
    }
    PGOperate *operate = [[PGOperate alloc] init];
    operate.act = [json[@"act"] isKindOfClass:[NSString class]] ? json[@"act"] : @"";
    operate.name = [json[@"name"] isKindOfClass:[NSString class]] ? json[@"name"] : @"";
    NSString *text = [json[@"text"] isKindOfClass:[NSString class]] ? json[@"text"] : @"";
    if([operate.act caseInsensitiveCompare:@"TYPE"] == NSOrderedSame)
    {
        // For TYPE, text is what to enter; the field is located by id or pos.
        operate.text = text;
        operate.queryText = @"";
    }
    else
    {
        operate.queryText = text;
    }
    operate.queryIdentifier = [json[@"id"] isKindOfClass:[NSString class]] ? json[@"id"] : @"";
    operate.waitTime = [json[@"duration"] integerValue];
    if([json[@"throttle"] respondsToSelector:@selector(doubleValue)])
    {
        operate.throttle = [json[@"throttle"] doubleValue];
    }
    NSArray *pos = json[@"pos"];
    if([pos isKindOfClass:[NSArray class]] && pos.count >= 4)
    {
        operate.rect = (PGElementRect){
            .left = [pos[0] integerValue],
            .top = [pos[1] integerValue],
            .width = [pos[2] integerValue],
            .height = [pos[3] integerValue]
        };
    }
    operate.path = [json[@"path"] isKindOfClass:[NSArray class]] ? json[@"path"] : nil;
    return operate;
}

@end
