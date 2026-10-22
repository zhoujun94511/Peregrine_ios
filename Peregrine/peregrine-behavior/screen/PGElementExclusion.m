#import "PGElementExclusion.h"

@implementation PGElementExclusion

- (instancetype)initWithNames:(NSArray<NSString *> *)names
{
    self = [super init];
    if(self)
    {
        _names = [names copy] ?: @[];
    }
    return self;
}

- (BOOL)matchesNode:(PGElementNode *)node
{
    if(self.names.count == 0 || node == nil)
    {
        return NO;
    }
    return (node.identifier.length > 0 && [self.names containsObject:node.identifier]) || (node.label.length > 0 && [self.names containsObject:node.label]);
}

- (NSArray<PGElementNode *> *)coversInNodes:(NSArray<PGElementNode *> *)nodes
{
    if(self.names.count == 0)
    {
        return @[];
    }
    NSMutableArray<PGElementNode *> *covers = [NSMutableArray array];
    for(PGElementNode *node in [PGElementNode flattenedNodes:nodes ?: @[]])
    {
        if([self matchesNode:node] && node.rect.width > 0 && node.rect.height > 0)
        {
            [covers addObject:node];
        }
    }
    return covers;
}

- (NSArray<PGElementNode *> *)nodes:(NSArray<PGElementNode *> *)nodes clearOfCovers:(NSArray<PGElementNode *> *)covers
{
    if(self.names.count == 0 || nodes.count == 0)
    {
        return nodes ?: @[];
    }
    NSMutableArray<PGElementNode *> *kept = [NSMutableArray arrayWithCapacity:nodes.count];
    for(PGElementNode *node in nodes)
    {
        if([self matchesNode:node])
        {
            continue;
        }
        if(node.children.count > 0)
        {
            node.children = [self nodes:node.children clearOfCovers:covers];
        }
        if(node.children.count == 0 && [self rect:node.rect centerInCovers:covers])
        {
            continue;
        }
        [kept addObject:node];
    }
    return kept;
}

- (BOOL)rect:(PGElementRect)rect centerInCovers:(NSArray<PGElementNode *> *)covers
{
    NSInteger x = rect.left + rect.width / 2;
    NSInteger y = rect.top + rect.height / 2;
    for(PGElementNode *cover in covers)
    {
        PGElementRect box = cover.rect;
        if(x >= box.left && y >= box.top && x < box.left + box.width && y < box.top + box.height)
        {
            return YES;
        }
    }
    return NO;
}

@end
