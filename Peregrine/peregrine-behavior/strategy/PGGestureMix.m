#import "PGGestureMix.h"

static double PGUnit(void)
{
    return (double)arc4random_uniform(10000) / 10000.0;
}

@implementation PGGestureMix

+ (NSDictionary<NSString *, NSNumber *> *)defaultRatios
{
    return @{
        @"SWIPE": @0.10,
        @"LONG_PRESS": @0.06,
        @"DOUBLE_TAP": @0.03,
        @"PINCH": @0.02,
        @"DRAG": @0.02
    };
}

+ (NSArray<NSString *> *)gestureOrder
{
    return @[@"SWIPE", @"PINCH", @"LONG_PRESS", @"DOUBLE_TAP", @"DRAG"];
}

- (instancetype)initWithRatios:(NSDictionary *)ratios
{
    self = [super init];
    if(self != nil)
    {
        NSMutableDictionary<NSString *, NSNumber *> *merged = [[PGGestureMix defaultRatios] mutableCopy];
        double total = 0;
        for(NSString *name in [PGGestureMix gestureOrder])
        {
            id value = [ratios isKindOfClass:[NSDictionary class]] ? ratios[name] : nil;
            if([value respondsToSelector:@selector(doubleValue)])
            {
                merged[name] = @(MAX([value doubleValue], 0));
            }
            total += merged[name].doubleValue;
        }
        if(total > 1)
        {
            for(NSString *name in [PGGestureMix gestureOrder])
            {
                merged[name] = @(merged[name].doubleValue / total);
            }
        }
        _ratios = merged;
    }
    return self;
}

- (NSString *)nextGesture
{
    double roll = PGUnit();
    double cursor = 0;
    for(NSString *name in [PGGestureMix gestureOrder])
    {
        cursor += self.ratios[name].doubleValue;
        if(roll < cursor)
        {
            return name;
        }
    }
    return @"CLICK";
}

- (NSString *)scrollAct
{
    double roll = PGUnit();
    if(roll < 0.45)
    {
        return @"SWIPE_UP";
    }
    if(roll < 0.70)
    {
        return @"SWIPE_DOWN";
    }
    return roll < 0.85 ? @"SWIPE_LEFT" : @"SWIPE_RIGHT";
}

- (PGOperate *)screenOperate:(NSString *)gesture space:(CGSize)space
{
    PGOperate *operate = [[PGOperate alloc] init];
    // The middle of the screen, clear of navigation bars, tab bars and the home indicator.
    operate.rect = (PGElementRect){
        (NSInteger)(space.width * 0.1),
        (NSInteger)(space.height * 0.2),
        (NSInteger)(space.width * 0.8),
        (NSInteger)(space.height * 0.6)
    };
    if([gesture isEqualToString:@"PINCH"])
    {
        operate.act = PGUnit() < 0.5 ? @"PINCH_OUT" : @"PINCH_IN";
    }
    else
    {
        operate.act = [self scrollAct];
    }
    operate.actionID = operate.act;
    return operate;
}

- (void)applyGesture:(NSString *)gesture toOperate:(PGOperate *)operate space:(CGSize)space
{
    if([gesture isEqualToString:@"LONG_PRESS"] || [gesture isEqualToString:@"DOUBLE_TAP"])
    {
        operate.act = gesture;
        return;
    }
    if(![gesture isEqualToString:@"DRAG"] || space.width < 2 || space.height < 2)
    {
        return;
    }
    PGElementRect rect = operate.rect;
    double x = rect.left + rect.width / 2.0;
    double y = rect.top + rect.height / 2.0;
    double dx = (PGUnit() - 0.5) * space.width * 0.6;
    double dy = (PGUnit() - 0.5) * space.height * 0.4;
    double endX = MIN(MAX(x + dx, space.width * 0.05), space.width * 0.95);
    double endY = MIN(MAX(y + dy, space.height * 0.1), space.height * 0.9);
    operate.act = @"DRAG";
    operate.path = @[@{@"x": @(x), @"y": @(y)}, @{@"x": @(endX), @"y": @(endY)}];
}

@end
