#import "PGCommandPlayer.h"

@implementation PGCommandPlayer

+ (PGGesture *)gestureForOperate:(PGOperate *)operate
                          inNodes:(NSArray<PGElementNode *> *)nodes
                           screen:(CGSize)screen
{
    PGOperate *resolved = [self resolvedOperate:operate inNodes:nodes];
    if(resolved == nil)
    {
        PGGesture *miss = [[PGGesture alloc] init];
        miss.kind = PGGestureKindNone;
        miss.unresolved = operate.queryIdentifier.length > 0 || operate.queryText.length > 0;
        return miss;
    }
    NSString *act = resolved.act.uppercaseString ?: @"";
    if([act isEqualToString:@"SCHEMA"])
    {
        PGGesture *gesture = [[PGGesture alloc] init];
        gesture.kind = PGGestureKindNone;
        return gesture;
    }
    if([act isEqualToString:@"FORCE_BACK"])
    {
        PGGesture *gesture = [[PGGesture alloc] init];
        gesture.kind = PGGestureKindForceBack;
        return gesture;
    }
    if([act isEqualToString:@"LONG_PRESS"])
    {
        PGGesture *gesture = [self tapGestureForRect:[self pointInRect:resolved.rect preferRandom:NO]];
        gesture.duration = resolved.waitTime > 0 ? resolved.waitTime / 1000.0 : 1.0;
        return gesture;
    }
    if([act isEqualToString:@"DOUBLE_TAP"])
    {
        PGGesture *gesture = [self tapGestureForRect:[self pointInRect:resolved.rect preferRandom:YES]];
        gesture.kind = PGGestureKindDoubleTap;
        return gesture;
    }
    if([act isEqualToString:@"PINCH_OUT"] || [act isEqualToString:@"PINCH_IN"])
    {
        PGGesture *gesture = [[PGGesture alloc] init];
        gesture.kind = PGGestureKindPinch;
        gesture.scale = [act isEqualToString:@"PINCH_OUT"] ? 2.0 : 0.5;
        return gesture;
    }
    if([act isEqualToString:@"DRAG"])
    {
        return [self dragGestureForOperate:resolved];
    }
    if([act hasPrefix:@"SWIPE_"] || [act isEqualToString:@"SWIPE"])
    {
        if(resolved.path.count < 2 && (resolved.rect.width <= 0 || resolved.rect.height <= 0))
        {
            resolved.rect = (PGElementRect){0, 0, (NSInteger)screen.width, (NSInteger)screen.height};
        }
        return [self swipeGestureForAct:act operate:resolved];
    }
    if([act isEqualToString:@"TYPE"])
    {
        PGGesture *gesture = [self tapGestureForRect:[self pointInRect:resolved.rect preferRandom:NO]];
        gesture.kind = PGGestureKindType;
        gesture.text = resolved.text.length > 0 ? resolved.text : @"peregrine";
        return gesture;
    }
    if([act isEqualToString:@"CLICK"] || [act isEqualToString:@"CLICK_ID"] || [act isEqualToString:@"CLICK_TEXT"])
    {
        PGElementRect point = [self pointInRect:resolved.rect preferRandom:YES];
        if([self pointIsStatusBar:point])
        {
            PGGesture *skipped = [[PGGesture alloc] init];
            skipped.kind = PGGestureKindNone;
            return skipped;
        }
        resolved.rect = point;
        resolved.act = @"CLICK";
    }
    return [PGGesture gestureForOperate:resolved];
}

+ (PGOperate *)resolvedOperate:(PGOperate *)operate inNodes:(NSArray<PGElementNode *> *)nodes
{
    if(operate.queryIdentifier.length == 0 && operate.queryText.length == 0)
    {
        return operate;
    }
    PGElementNode *node = [PGElementNode nodeInNodes:nodes matchingIdentifier:operate.queryIdentifier text:operate.queryText];
    if(node == nil)
    {
        return nil;
    }
    PGOperate *resolved = [PGOperate clickOnNode:node];
    resolved.act = operate.act.length > 0 ? operate.act : @"CLICK";
    if([resolved.act caseInsensitiveCompare:@"CLICK_ID"] == NSOrderedSame || [resolved.act caseInsensitiveCompare:@"CLICK_TEXT"] == NSOrderedSame)
    {
        resolved.act = @"CLICK";
    }
    resolved.rect = [self pointInRect:node.rect preferRandom:YES];
    resolved.text = operate.text;
    return resolved;
}

+ (PGElementRect)pointInRect:(PGElementRect)rect preferRandom:(BOOL)preferRandom
{
    if(rect.width <= 0 || rect.height <= 0)
    {
        return rect;
    }
    BOOL randomPoint = preferRandom && (double)arc4random_uniform(1000) / 1000.0 >= 0.3;
    NSInteger x = rect.left + rect.width / 2;
    NSInteger y = rect.top + rect.height / 2;
    if(randomPoint)
    {
        x = rect.left + (NSInteger)arc4random_uniform((uint32_t)MAX(rect.width, 1));
        y = rect.top + (NSInteger)arc4random_uniform((uint32_t)MAX(rect.height, 1));
    }
    return (PGElementRect){x, y, 1, 1};
}

+ (BOOL)pointIsStatusBar:(PGElementRect)point
{
    double unit = (double)arc4random_uniform(1000) / 1000.0;
    return point.left > 60 && point.top <= 28 && unit < 0.7;
}

+ (PGGesture *)tapGestureForRect:(PGElementRect)point
{
    PGGesture *gesture = [[PGGesture alloc] init];
    gesture.kind = PGGestureKindTap;
    gesture.start = point;
    gesture.end = point;
    gesture.duration = 0.05;
    return gesture;
}

+ (PGGesture *)dragGestureForOperate:(PGOperate *)operate
{
    PGGesture *gesture = [[PGGesture alloc] init];
    NSDictionary *first = [operate.path.firstObject isKindOfClass:[NSDictionary class]] ? operate.path.firstObject : nil;
    NSDictionary *last = [operate.path.lastObject isKindOfClass:[NSDictionary class]] ? operate.path.lastObject : nil;
    if(operate.path.count < 2 || first == nil || last == nil)
    {
        gesture.kind = PGGestureKindNone;
        return gesture;
    }
    gesture.kind = PGGestureKindDrag;
    gesture.start = (PGElementRect){(NSInteger)[first[@"x"] doubleValue], (NSInteger)[first[@"y"] doubleValue], 1, 1};
    gesture.end = (PGElementRect){(NSInteger)[last[@"x"] doubleValue], (NSInteger)[last[@"y"] doubleValue], 1, 1};
    gesture.duration = operate.waitTime > 0 ? operate.waitTime / 1000.0 : 0.8;
    return gesture;
}

+ (PGGesture *)swipeGestureForAct:(NSString *)act operate:(PGOperate *)operate
{
    PGGesture *gesture = [[PGGesture alloc] init];
    if(operate.path.count >= 2)
    {
        gesture.kind = PGGestureKindPath;
        NSMutableArray<NSValue *> *points = [NSMutableArray array];
        for(id item in operate.path)
        {
            if(![item isKindOfClass:[NSDictionary class]])
            {
                continue;
            }
            CGPoint point = CGPointMake([item[@"x"] doubleValue], [item[@"y"] doubleValue]);
            [points addObject:[NSValue valueWithCGPoint:point]];
        }
        gesture.points = points;
        gesture.duration = operate.waitTime > 0 ? operate.waitTime / 1000.0 : 0.3;
        return gesture;
    }
    PGElementRect rect = operate.rect;
    if([act isEqualToString:@"SWIPE"] && rect.width > 0 && rect.height > 0)
    {
        gesture.kind = PGGestureKindSwipe;
        gesture.start = (PGElementRect){rect.left, rect.top, 1, 1};
        gesture.end = (PGElementRect){rect.left + rect.width, rect.top + rect.height, 1, 1};
        return gesture;
    }
    NSInteger centerX = rect.left + MAX(rect.width, 1) / 2;
    NSInteger centerY = rect.top + MAX(rect.height, 1) / 2;
    NSInteger dx = MAX((NSInteger)(rect.width * 0.3), 40);
    NSInteger dy = MAX((NSInteger)(rect.height * 0.25), 40);
    gesture.kind = PGGestureKindSwipe;
    gesture.start = (PGElementRect){centerX, centerY, 1, 1};
    gesture.end = gesture.start;
    if([act isEqualToString:@"SWIPE_LEFT"])
    {
        gesture.start = (PGElementRect){centerX + dx, centerY, 1, 1};
        gesture.end = (PGElementRect){centerX - dx, centerY, 1, 1};
    }
    else if([act isEqualToString:@"SWIPE_RIGHT"])
    {
        gesture.start = (PGElementRect){centerX - dx, centerY, 1, 1};
        gesture.end = (PGElementRect){centerX + dx, centerY, 1, 1};
    }
    else if([act isEqualToString:@"SWIPE_UP"])
    {
        gesture.start = (PGElementRect){centerX, centerY + dy, 1, 1};
        gesture.end = (PGElementRect){centerX, centerY - dy, 1, 1};
    }
    else
    {
        gesture.start = (PGElementRect){centerX, centerY - dy, 1, 1};
        gesture.end = (PGElementRect){centerX, centerY + dy, 1, 1};
    }
    return gesture;
}

@end
