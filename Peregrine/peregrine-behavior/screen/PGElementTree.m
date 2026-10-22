#import "PGElementTree.h"

static BOOL PGControllerIsChrome(NSString *name)
{
    if(name.length == 0)
    {
        return YES;
    }
    if([name isEqualToString:@"UINavigationController"]
        || [name isEqualToString:@"UITabBarController"]
        || [name isEqualToString:@"UISplitViewController"]
        || [name isEqualToString:@"UIPageViewController"]
        || [name isEqualToString:@"UIInputWindowController"]
        || [name isEqualToString:@"UICompatibilityInputViewController"]
        || [name isEqualToString:@"UIEditingOverlayViewController"]
        || [name isEqualToString:@"UISystemInputAssistantViewController"]
        || [name isEqualToString:@"UIPredictionViewController"])
    {
        return YES;
    }
    return [name hasPrefix:@"_UICursor"] || [name hasPrefix:@"UIInput"] || [name containsString:@"Keyboard"];
}

static const NSInteger PGQueryIndexAny = -1;
static const NSInteger PGRectGrid = 40;
static const uint64_t PGHashOffset = 1469598103934665603ULL;
static const uint64_t PGHashPrime = 1099511628211ULL;

@implementation PGElementNode

+ (NSArray<PGElementNode *> *)nodesFromResult:(id)result
{
    if(![result isKindOfClass:[NSArray class]])
    {
        return @[];
    }
    NSMutableArray<PGElementNode *> *nodes = [NSMutableArray array];
    for(id item in (NSArray *)result)
    {
        PGElementNode *node = [self nodeFromDictionary:item];
        if(node != nil)
        {
            [nodes addObject:node];
        }
    }
    [self assignPaths:nodes parentPath:@""];
    return nodes;
}

+ (PGElementNode *)nodeFromDictionary:(id)item
{
    if(![item isKindOfClass:[NSDictionary class]])
    {
        return nil;
    }
    NSDictionary *info = ((NSDictionary *)item)[@"elem_info"];
    if(![info isKindOfClass:[NSDictionary class]])
    {
        return nil;
    }
    PGElementNode *node = [[PGElementNode alloc] init];
    node.type = [info[@"type"] isKindOfClass:[NSString class]] ? info[@"type"] : @"";
    node.identifier = [info[@"identifier"] isKindOfClass:[NSString class]] ? info[@"identifier"] : @"";
    node.label = [info[@"label"] isKindOfClass:[NSString class]] ? info[@"label"] : @"";
    node.value = [info[@"value"] isKindOfClass:[NSString class]] ? info[@"value"] : @"";
    node.controller = [info[@"controller"] isKindOfClass:[NSString class]] ? info[@"controller"] : @"";
    node.visible = [info[@"visible"] boolValue];
    node.interactive = [info[@"interactive"] boolValue];
    node.scrollable = [info[@"scrollable"] boolValue];
    node.clickable = [info[@"clickable"] boolValue];
    NSDictionary *rect = [info[@"rect"] isKindOfClass:[NSDictionary class]] ? info[@"rect"] : @{};
    node.rect = (PGElementRect){
        .left = [rect[@"left"] integerValue],
        .top = [rect[@"top"] integerValue],
        .width = [rect[@"width"] integerValue],
        .height = [rect[@"height"] integerValue]
    };
    NSMutableArray<PGElementNode *> *children = [NSMutableArray array];
    id rawChildren = ((NSDictionary *)item)[@"children"];
    if([rawChildren isKindOfClass:[NSArray class]])
    {
        for(id child in (NSArray *)rawChildren)
        {
            PGElementNode *parsed = [self nodeFromDictionary:child];
            if(parsed != nil)
            {
                [children addObject:parsed];
            }
        }
    }
    node.children = children;
    return node;
}

- (NSString *)firstController
{
    if(self.controller.length > 0)
    {
        return self.controller;
    }
    for(PGElementNode *child in self.children)
    {
        NSString *name = [child firstController];
        if(name.length > 0)
        {
            return name;
        }
    }
    return @"";
}

- (NSString *)contentController
{
    for(PGElementNode *child in self.children.reverseObjectEnumerator)
    {
        NSString *deeper = [child contentController];
        if(deeper.length > 0)
        {
            return deeper;
        }
    }
    return PGControllerIsChrome(self.controller) ? @"" : self.controller;
}

+ (void)assignPaths:(NSArray<PGElementNode *> *)nodes parentPath:(NSString *)parent
{
    NSMutableDictionary<NSString *, NSNumber *> *counts = [NSMutableDictionary dictionary];
    for(PGElementNode *node in nodes)
    {
        NSString *segment = nil;
        if(node.identifier.length > 0)
        {
            NSInteger seen = counts[node.identifier].integerValue;
            counts[node.identifier] = @(seen + 1);
            segment = seen == 0 ? node.identifier : [NSString stringWithFormat:@"%@[%ld]", node.identifier, (long)seen];
        }
        else
        {
            NSString *type = node.type.length > 0 ? node.type : @"View";
            NSInteger index = counts[type].integerValue;
            counts[type] = @(index + 1);
            segment = [NSString stringWithFormat:@"%@[%ld]", type, (long)index];
        }
        node.path = parent.length > 0 ? [parent stringByAppendingFormat:@"/%@", segment] : segment;
        [self assignPaths:node.children parentPath:node.path];
    }
}

+ (PGElementNode *)nodeInNodes:(NSArray<PGElementNode *> *)nodes
           matchingIdentifier:(NSString *)identifier
                         text:(NSString *)text
{
    for(PGElementNode *node in nodes)
    {
        PGElementNode *found = [node nodeMatchingIdentifier:identifier text:text];
        if(found != nil)
        {
            return found;
        }
    }
    return nil;
}

- (PGElementNode *)nodeMatchingIdentifier:(NSString *)identifier text:(NSString *)text
{
    BOOL wantsIdentifier = identifier.length > 0;
    BOOL wantsText = text.length > 0;
    BOOL identifierMatches = !wantsIdentifier || [self.identifier isEqualToString:identifier];
    BOOL textMatches = !wantsText || [self.label containsString:text] || [self.value containsString:text] || [self.type containsString:text];
    if((wantsIdentifier || wantsText) && identifierMatches && textMatches && self.rect.width > 0 && self.rect.height > 0)
    {
        return self;
    }
    for(PGElementNode *child in self.children)
    {
        PGElementNode *found = [child nodeMatchingIdentifier:identifier text:text];
        if(found != nil)
        {
            return found;
        }
    }
    return nil;
}

+ (NSArray<PGElementNode *> *)flattenedNodes:(NSArray<PGElementNode *> *)nodes
{
    NSMutableArray<PGElementNode *> *flat = [NSMutableArray array];
    for(PGElementNode *node in nodes)
    {
        [node appendFlattenedInto:flat];
    }
    return flat;
}

- (void)appendFlattenedInto:(NSMutableArray<PGElementNode *> *)flat
{
    [flat addObject:self];
    for(PGElementNode *child in self.children)
    {
        [child appendFlattenedInto:flat];
    }
}

+ (uint64_t)fingerprintOfNodes:(NSArray<PGElementNode *> *)nodes
{
    if(nodes.count == 0)
    {
        return 0;
    }
    uint64_t combined = PGHashOffset;
    for(PGElementNode *node in nodes)
    {
        combined ^= [node structureHashMixingIndex:NO];
        combined *= PGHashPrime;
    }
    return combined == 0 ? 1 : combined;
}

- (uint64_t)structureHashMixingIndex:(BOOL)mixIndex
{
    NSUInteger index = 0;
    return [self mixHash:PGHashOffset index:&index mixIndex:mixIndex insideScroll:NO];
}

- (uint64_t)mixHash:(uint64_t)combined
              index:(NSUInteger *)index
           mixIndex:(BOOL)mixIndex
       insideScroll:(BOOL)insideScroll
{
    combined ^= [self identityHashInsideScroll:insideScroll];
    combined *= PGHashPrime;
    if(mixIndex)
    {
        combined ^= (uint64_t)(*index) * 0x1fc0ULL;
        combined *= PGHashPrime;
    }
    *index += 1;
    BOOL childInside = insideScroll || self.scrollable;
    for(PGElementNode *child in self.children)
    {
        combined = [child mixHash:combined index:index mixIndex:mixIndex insideScroll:childInside];
    }
    return combined;
}

- (BOOL)typeOmitsRect
{
    NSString *type = self.type.lowercaseString ?: @"";
    return [type containsString:@"progress"] || [type containsString:@"slider"] || [type containsString:@"indicator"];
}

- (uint64_t)identityHashInsideScroll:(BOOL)insideScroll
{
    NSString *rectPart = @"";
    if(!insideScroll && ![self typeOmitsRect])
    {
        rectPart = [NSString stringWithFormat:@"|%ld,%ld,%ld,%ld",
                    (long)(self.rect.left / PGRectGrid),
                    (long)(self.rect.top / PGRectGrid),
                    (long)(self.rect.width / PGRectGrid),
                    (long)(self.rect.height / PGRectGrid)];
    }
    NSString *identity = [NSString stringWithFormat:@"%@|%@|%@|%@%@",
                          self.type ?: @"",
                          self.identifier ?: @"",
                          self.controller ?: @"",
                          self.path ?: @"",
                          rectPart];
    uint64_t hash = PGHashOffset;
    NSData *bytes = [identity dataUsingEncoding:NSUTF8StringEncoding];
    const uint8_t *raw = bytes.bytes;
    for(NSUInteger i = 0; i < bytes.length; i++)
    {
        hash ^= raw[i];
        hash *= PGHashPrime;
    }
    return hash;
}

+ (BOOL)queryNamesListContainer:(NSString *)query
{
    return [query containsString:@"TableView"] || [query containsString:@"CollectionView"];
}

+ (NSArray<PGElementNode *> *)nodesMatchingQuery:(NSString *)query inNodes:(NSArray<PGElementNode *> *)nodes
{
    NSString *type = query ?: @"";
    NSInteger index = PGQueryIndexAny;
    NSRange split = [type rangeOfString:@"_"];
    if(split.location != NSNotFound)
    {
        NSString *suffix = [type substringFromIndex:split.location + 1];
        type = [type substringToIndex:split.location];
        if(suffix.length > 0)
        {
            index = suffix.integerValue;
        }
    }
    NSMutableArray<PGElementNode *> *matches = [NSMutableArray array];
    for(PGElementNode *node in nodes)
    {
        [node collectType:type into:matches];
    }
    if(index == PGQueryIndexAny)
    {
        return matches;
    }
    if(index < 0 || (NSUInteger)index >= matches.count)
    {
        return @[];
    }
    return @[matches[(NSUInteger)index]];
}

- (NSArray<PGElementNode *> *)nodesMatchingQuery:(NSString *)query
{
    if(query.length == 0)
    {
        return @[];
    }
    NSString *type = query;
    NSInteger index = PGQueryIndexAny;
    NSRange split = [query rangeOfString:@"_"];
    if(split.location != NSNotFound)
    {
        type = [query substringToIndex:split.location];
        NSString *suffix = [query substringFromIndex:split.location + 1];
        if(suffix.length > 0)
        {
            index = suffix.integerValue;
        }
    }
    NSMutableArray<PGElementNode *> *matches = [NSMutableArray array];
    [self collectType:type into:matches];
    if(index == PGQueryIndexAny)
    {
        return matches;
    }
    if(index < 0 || (NSUInteger)index >= matches.count)
    {
        return @[];
    }
    return @[matches[(NSUInteger)index]];
}

- (void)collectType:(NSString *)type into:(NSMutableArray<PGElementNode *> *)matches
{
    if([self.type isEqualToString:type])
    {
        [matches addObject:self];
    }
    for(PGElementNode *child in self.children)
    {
        [child collectType:type into:matches];
    }
}

+ (NSArray<PGElementNode *> *)combinedChildrenOfNodes:(NSArray<PGElementNode *> *)nodes
{
    NSMutableArray<PGElementNode *> *combined = [NSMutableArray array];
    for(PGElementNode *node in nodes)
    {
        if(node.children.count > 0)
        {
            [combined addObjectsFromArray:node.children];
        }
    }
    return combined;
}

@end
