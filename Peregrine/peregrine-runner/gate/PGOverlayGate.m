#import "PGOverlayGate.h"
#import "PGSnapshotTree.h"
#import "PGOverlayRules.h"

static NSArray<NSString *> *PGCloseWords(void)
{
    return @[
        @"关闭", @"以后再说", @"暂不", @"取消", @"下次再说", @"不了",
        @"not now", @"no thanks", @"maybe later", @"later", @"cancel", @"dismiss", @"close",
        @"×", @"✕", @"✖"
    ];
}

static NSArray<NSString *> *PGPaywallAvoidWords(void)
{
    return @[
        @"订阅", @"开通", @"试用", @"购买", @"继续", @"恢复购买", @"会员",
        @"subscribe", @"subscription", @"trial", @"purchase", @"buy", @"continue", @"restore", @"premium", @"upgrade"
    ];
}

static NSArray<NSString *> *PGAdAvoidWords(void)
{
    return @[@"安装", @"下载", @"打开", @"了解更多", @"install", @"download", @"open", @"learn more", @"get app"];
}

static NSArray<NSString *> *PGAdCloseWords(void)
{
    return @[@"跳过", @"关闭广告", @"关闭", @"skip ad", @"skip", @"close ad", @"close", @"×", @"✕", @"✖"];
}

@implementation PGOverlayDecision
@end

@implementation PGOverlayGate
{
    uint64_t _fingerprint;
    NSInteger _repeats;
    NSInteger _streak;
    NSArray<PGElementNode *> *_snapshotNodes;
    uint64_t _snapshotFingerprint;
    NSInteger _snapshotSkip;
}

- (PGOverlayDecision *)decisionForScreen:(PGStepScreen *)screen application:(XCUIApplication *)application
{
    PGOverlayDecision *decision = [[PGOverlayDecision alloc] init];
    if(screen.fingerprint == 0)
    {
        return decision;
    }
    if(screen.fingerprint != _fingerprint)
    {
        _fingerprint = screen.fingerprint;
        _repeats = 1;
        _streak = 0;
    }
    else
    {
        _repeats += 1;
    }
    BOOL points = screen.usePoints;
    CGSize space = points ? screen.screenSize : screen.pixelSize;
    NSArray<PGElementNode *> *nodes = [PGElementNode flattenedNodes:screen.nodes];
    if(![self nodesHaveText:nodes] && _repeats >= 2)
    {
        nodes = [self snapshotNodesForScreen:screen application:application];
        points = YES;
        space = screen.screenSize;
    }
    space = [self space:space coveringNodes:nodes];
    PGOverlayKind overlay = [self kindOfNodes:nodes inSpace:space];
    if(overlay == PGOverlayKindNone)
    {
        _streak = 0;
        return decision;
    }
    BOOL paywall = overlay == PGOverlayKindPaywall;
    _streak += 1;
    NSString *kind = paywall ? @"paywall" : @"ad";
    if(_streak >= 3)
    {
        decision.action = PGOverlayActionForeground;
        NSLog(@"overlay %@ step %ld foreground", kind, (long)_streak);
        return decision;
    }
    decision.action = PGOverlayActionOperate;
    if(_streak == 2)
    {
        decision.operate = [self backOperate];
        NSLog(@"overlay %@ step %ld back repeat", kind, (long)_streak);
        return decision;
    }
    PGElementNode *close = [self closeNodeIn:nodes space:space paywall:paywall points:points];
    if(close != nil)
    {
        decision.operate = [PGOperate clickOnNode:close];
        NSLog(@"overlay %@ step %ld close %@ %@", kind, (long)_streak, [self cornerNameForRect:close.rect space:space], decision.operate.text ?: @"");
        return decision;
    }
    decision.operate = [self backOperate];
    NSLog(@"overlay %@ step %ld back no-close", kind, (long)_streak);
    return decision;
}

- (NSArray<PGElementNode *> *)snapshotNodesForScreen:(PGStepScreen *)screen application:(XCUIApplication *)application
{
    uint64_t fingerprint = screen.fingerprint;
    if(_snapshotSkip > 0)
    {
        _snapshotSkip -= 1;
        return @[];
    }
    if(_snapshotFingerprint == fingerprint && _snapshotNodes != nil)
    {
        return _snapshotNodes;
    }
    PGStepSnapshot *snapshot = [screen snapshotInApplication:application];
    if(snapshot.failure != nil)
    {
        NSLog(@"overlay snapshot failed %@", snapshot.failure);
        _snapshotSkip = 5;
        return @[];
    }
    NSArray<PGElementNode *> *nodes = snapshot.nodes;
    BOOL outside = snapshot.outside;
    NSInteger elapsed = snapshot.elapsedMillis;
    if(elapsed > 1500)
    {
        NSLog(@"overlay snapshot slow %ld", (long)elapsed);
        _snapshotSkip = 5;
        return @[];
    }
    if(outside)
    {
        NSLog(@"overlay snapshot outside");
        return @[];
    }
    _snapshotNodes = nodes ?: @[];
    _snapshotFingerprint = fingerprint;
    return _snapshotNodes;
}

- (PGOverlayKind)kindOfNodes:(NSArray<PGElementNode *> *)nodes inSpace:(CGSize)space
{
    if(space.width < 2 || space.height < 2)
    {
        return PGOverlayKindNone;
    }
    NSInteger clickable = 0;
    CGFloat maxArea = 0;
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    for(PGElementNode *node in nodes)
    {
        CGRect rect = [self rect:node.rect inSpace:space];
        maxArea = MAX(maxArea, rect.size.width * rect.size.height);
        if(node.clickable)
        {
            clickable += 1;
        }
        NSString *text = [self textOfNode:node];
        if(text.length > 0)
        {
            [texts addObject:text];
        }
    }
    return [PGOverlayRules kindForTexts:texts clickable:clickable largestArea:maxArea];
}

- (PGElementNode *)closeNodeIn:(NSArray<PGElementNode *> *)nodes space:(CGSize)space paywall:(BOOL)paywall points:(BOOL)points
{
    if(!points || space.width < 2 || space.height < 2)
    {
        return nil;
    }
    NSArray<NSString *> *safe = paywall ? PGCloseWords() : PGAdCloseWords();
    NSArray<NSString *> *avoid = paywall ? PGPaywallAvoidWords() : PGAdAvoidWords();
    PGElementNode *best = nil;
    NSInteger bestScore = 0;
    CGFloat bestArea = 2;
    for(PGElementNode *node in nodes)
    {
        if(!node.clickable)
        {
            continue;
        }
        NSString *text = [self textOfNode:node];
        if([PGOverlayRules textIsCountdown:text] || [PGOverlayRules text:text hasAny:avoid])
        {
            continue;
        }
        NSInteger score = 0;
        if([PGOverlayRules text:text hasAny:safe] || [self textIsMark:text])
        {
            score = 100;
        }
        else if([self rectIsCorner:node.rect inSpace:space])
        {
            if(paywall && ![self rectIsTopCorner:node.rect inSpace:space])
            {
                continue;
            }
            score = 80;
        }
        if(score == 0)
        {
            continue;
        }
        CGRect rect = [self rect:node.rect inSpace:space];
        CGFloat area = rect.size.width * rect.size.height;
        if(score > bestScore || (score == bestScore && area < bestArea))
        {
            best = node;
            bestScore = score;
            bestArea = area;
        }
    }
    return best;
}

- (BOOL)nodesHaveText:(NSArray<PGElementNode *> *)nodes
{
    for(PGElementNode *node in nodes)
    {
        if([self textOfNode:node].length > 0)
        {
            return YES;
        }
    }
    return NO;
}

- (NSString *)textOfNode:(PGElementNode *)node
{
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if(node.label.length > 0)
    {
        [parts addObject:node.label];
    }
    if(node.value.length > 0)
    {
        [parts addObject:node.value];
    }
    if(node.identifier.length > 0)
    {
        [parts addObject:node.identifier];
    }
    return [parts componentsJoinedByString:@" "];
}

- (BOOL)textIsMark:(NSString *)text
{
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [trimmed isEqualToString:@"x"] || [trimmed isEqualToString:@"X"] || [trimmed isEqualToString:@"×"] || [trimmed isEqualToString:@"✕"] || [trimmed isEqualToString:@"✖"];
}

- (CGRect)rect:(PGElementRect)rect inSpace:(CGSize)space
{
    return CGRectMake(rect.left / space.width, rect.top / space.height, rect.width / space.width, rect.height / space.height);
}

- (NSString *)cornerNameForRect:(PGElementRect)rect space:(CGSize)space
{
    if(![self rectIsCorner:rect inSpace:space])
    {
        return @"text";
    }
    CGRect normal = [self rect:rect inSpace:space];
    BOOL top = CGRectGetMidY(normal) <= 0.50;
    BOOL left = CGRectGetMidX(normal) <= 0.50;
    if(top && left)
    {
        return @"top-left";
    }
    if(top)
    {
        return @"top-right";
    }
    return left ? @"bottom-left" : @"bottom-right";
}

- (BOOL)rectIsCorner:(PGElementRect)rect inSpace:(CGSize)space
{
    CGRect normal = [self rect:rect inSpace:space];
    if(normal.size.width <= 0 || normal.size.height <= 0 || normal.size.width > 0.28 || normal.size.height > 0.18)
    {
        return NO;
    }
    CGFloat midX = CGRectGetMidX(normal);
    CGFloat midY = CGRectGetMidY(normal);
    BOOL top = midY <= 0.28;
    BOOL bottom = midY >= 0.72;
    BOOL left = midX <= 0.30;
    BOOL right = midX >= 0.70;
    return (top || bottom) && (left || right);
}

- (BOOL)rectIsTopCorner:(PGElementRect)rect inSpace:(CGSize)space
{
    CGRect normal = [self rect:rect inSpace:space];
    return CGRectGetMidY(normal) <= 0.28 && [self rectIsCorner:rect inSpace:space];
}

- (CGSize)space:(CGSize)space coveringNodes:(NSArray<PGElementNode *> *)nodes
{
    if(space.width >= 2 && space.height >= 2)
    {
        return space;
    }
    NSInteger width = 0;
    NSInteger height = 0;
    for(PGElementNode *node in nodes)
    {
        width = MAX(width, node.rect.left + node.rect.width);
        height = MAX(height, node.rect.top + node.rect.height);
    }
    return CGSizeMake(MAX(width, 2), MAX(height, 2));
}

- (PGOperate *)backOperate
{
    PGOperate *operate = [[PGOperate alloc] init];
    operate.act = @"BACK";
    return operate;
}

@end
