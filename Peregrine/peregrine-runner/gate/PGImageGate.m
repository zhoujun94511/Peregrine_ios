#import "PGImageGate.h"
#import "PGSnapshotTree.h"

static NSArray<NSString *> *PGImageWords(void)
{
    return @[
        @"预览", @"大图", @"缩放", @"图片", @"相册",
        @"preview", @"zoom", @"lightbox", @"gallery", @"photo viewer", @"qlpreview", @"imageviewer"
    ];
}

static NSArray<NSString *> *PGImageCloseWords(void)
{
    return @[
        @"关闭", @"完成", @"返回", @"取消", @"收起",
        @"close", @"done", @"back", @"cancel", @"dismiss",
        @"×", @"✕", @"✖"
    ];
}

static NSArray<NSString *> *PGImageAvoidWords(void)
{
    return @[
        @"分享", @"保存", @"删除", @"收藏", @"编辑", @"下载", @"发送",
        @"share", @"save", @"delete", @"favorite", @"edit", @"download", @"send", @"like"
    ];
}

@implementation PGImageGate
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
    BOOL sparse = _repeats >= 2 && nodes.count <= 2;
    BOOL named = [self nodesNamedImage:nodes];
    if(!sparse && !named && ![self nodesHaveText:nodes] && _repeats >= 2)
    {
        nodes = [self snapshotNodesForScreen:screen application:application];
        points = YES;
        space = screen.screenSize;
        named = [self nodesNamedImage:nodes];
    }
    space = [self space:space coveringNodes:nodes];
    if(!named && !sparse && _repeats < 2)
    {
        return decision;
    }
    if(![self nodes:nodes inSpace:space lookLikeZoom:named])
    {
        _streak = 0;
        return decision;
    }
    _streak += 1;
    if(_streak >= 3)
    {
        decision.action = PGOverlayActionForeground;
        NSLog(@"image zoom step %ld foreground", (long)_streak);
        return decision;
    }
    decision.action = PGOverlayActionOperate;
    if(_streak == 2)
    {
        decision.operate = [self backOperate];
        NSLog(@"image zoom step %ld back repeat", (long)_streak);
        return decision;
    }
    PGElementNode *close = [self closeNodeIn:nodes space:space points:points];
    if(close != nil)
    {
        decision.operate = [PGOperate clickOnNode:close];
        NSLog(@"image zoom step %ld close %@", (long)_streak, decision.operate.text ?: @"");
        return decision;
    }
    decision.operate = [self backOperate];
    NSLog(@"image zoom step %ld back no-close", (long)_streak);
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
        NSLog(@"image zoom snapshot failed %@", snapshot.failure);
        _snapshotSkip = 5;
        return @[];
    }
    NSArray<PGElementNode *> *nodes = snapshot.nodes;
    BOOL outside = snapshot.outside;
    NSInteger elapsed = snapshot.elapsedMillis;
    if(elapsed > 1500)
    {
        NSLog(@"image zoom snapshot slow %ld", (long)elapsed);
        _snapshotSkip = 5;
        return @[];
    }
    if(outside)
    {
        return @[];
    }
    _snapshotNodes = nodes ?: @[];
    _snapshotFingerprint = fingerprint;
    return _snapshotNodes;
}

- (BOOL)nodes:(NSArray<PGElementNode *> *)nodes inSpace:(CGSize)space lookLikeZoom:(BOOL)named
{
    if(space.width < 2 || space.height < 2 || nodes.count == 0)
    {
        return NO;
    }
    PGElementNode *largest = nil;
    CGFloat maxArea = 0;
    NSInteger clickable = 0;
    NSInteger labeled = 0;
    for(PGElementNode *node in nodes)
    {
        CGRect rect = [self rect:node.rect inSpace:space];
        CGFloat area = rect.size.width * rect.size.height;
        if(largest == nil || area > maxArea)
        {
            largest = node;
            maxArea = area;
        }
        if(node.clickable)
        {
            clickable += 1;
        }
        if([self textOfNode:node].length > 0)
        {
            labeled += 1;
        }
    }
    if(maxArea < (named ? 0.55 : 0.70) || labeled >= 8)
    {
        return NO;
    }
    NSInteger extras = clickable;
    if(largest.clickable && extras > 0)
    {
        extras -= 1;
    }
    if(extras > 4)
    {
        return NO;
    }
    if(named)
    {
        return YES;
    }
    return [self nodeLooksLikeImage:largest];
}

- (BOOL)nodesNamedImage:(NSArray<PGElementNode *> *)nodes
{
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for(PGElementNode *node in nodes)
    {
        NSString *text = [self textOfNode:node];
        if(text.length > 0)
        {
            [parts addObject:text];
        }
    }
    return [self text:[parts componentsJoinedByString:@" "] hasAny:PGImageWords()];
}

- (BOOL)nodeLooksLikeImage:(PGElementNode *)node
{
    NSString *type = [node.type lowercaseString] ?: @"";
    return [type containsString:@"image"] || [type containsString:@"photo"] || [type containsString:@"preview"] || [type containsString:@"scroll"] || [type containsString:@"area"] || [type containsString:@"container"];
}

- (PGElementNode *)closeNodeIn:(NSArray<PGElementNode *> *)nodes space:(CGSize)space points:(BOOL)points
{
    if(!points || space.width < 2 || space.height < 2)
    {
        return nil;
    }
    PGElementNode *best = nil;
    NSInteger bestScore = 0;
    CGFloat bestArea = 2;
    for(PGElementNode *node in nodes)
    {
        if(!node.clickable || [self nodeLooksLikeImage:node])
        {
            continue;
        }
        NSString *text = [self textOfNode:node];
        if([self text:text hasAny:PGImageAvoidWords()])
        {
            continue;
        }
        NSInteger score = 0;
        if([self text:text hasAny:PGImageCloseWords()] || [self textIsMark:text])
        {
            score = 100;
        }
        else if([self rectIsCorner:node.rect inSpace:space])
        {
            score = 80;
        }
        if(score == 0)
        {
            continue;
        }
        CGRect rect = [self rect:node.rect inSpace:space];
        if(rect.size.width > 0.28 || rect.size.height > 0.18)
        {
            continue;
        }
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
    if(node.controller.length > 0)
    {
        [parts addObject:node.controller];
    }
    return [parts componentsJoinedByString:@" "];
}

- (BOOL)text:(NSString *)text hasAny:(NSArray<NSString *> *)words
{
    for(NSString *word in words)
    {
        if(text.length == 0 || word.length == 0)
        {
            continue;
        }
        if([text rangeOfString:word options:NSCaseInsensitiveSearch].location != NSNotFound)
        {
            return YES;
        }
    }
    return NO;
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
