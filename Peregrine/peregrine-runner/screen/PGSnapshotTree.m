#import "PGSnapshotTree.h"
#import "PGEnvironment.h"

static const NSInteger PGSnapshotNodeCap = 200;

@implementation PGSnapshotTree

+ (PGSnapshotSourceMode)sourceModeInEnvironment:(NSDictionary *)environment
{
    NSString *text = [PGEnvironment stringForKey:@"PEREGRINE_UI_SOURCE" inEnvironment:environment];
    if(text.length == 0)
    {
        return PGSnapshotSourceModeCombined;
    }
    if([text caseInsensitiveCompare:@"screenshot"] == NSOrderedSame)
    {
        return PGSnapshotSourceModeScreenshot;
    }
    if([text caseInsensitiveCompare:@"snapshot"] == NSOrderedSame)
    {
        return PGSnapshotSourceModeSnapshot;
    }
    if([text caseInsensitiveCompare:@"combined"] != NSOrderedSame)
    {
        NSLog(@"PEREGRINE_UI_SOURCE %@ not recognized, using combined", text);
    }
    return PGSnapshotSourceModeCombined;
}

+ (PGElementNode *)controlCoveringRect:(PGElementRect)rect inNodes:(NSArray<PGElementNode *> *)nodes
{
    if(rect.width <= 0 || rect.height <= 0)
    {
        return nil;
    }
    CGPoint center = CGPointMake(rect.left + rect.width / 2.0, rect.top + rect.height / 2.0);
    PGElementNode *best = nil;
    long long bestArea = 0;
    for(PGElementNode *node in nodes)
    {
        if(!node.clickable || node.rect.height < 20 || node.rect.width < 8 || ![self typeIsTappableControl:node.type])
        {
            continue;
        }
        if(center.x < node.rect.left || center.y < node.rect.top || center.x >= node.rect.left + node.rect.width || center.y >= node.rect.top + node.rect.height)
        {
            continue;
        }
        long long area = (long long)node.rect.width * (long long)node.rect.height;
        if(best == nil || area < bestArea)
        {
            best = node;
            bestArea = area;
        }
    }
    return best;
}

+ (NSArray<PGElementNode *> *)nodesFromApplication:(XCUIApplication *)application
                                          pageName:(NSString **)pageName
                                        outsideApp:(BOOL *)outsideApp
{
    if(pageName != nil)
    {
        *pageName = nil;
    }
    if(outsideApp != nil)
    {
        *outsideApp = NO;
    }
    if(application == nil)
    {
        return @[];
    }
    NSError *error = nil;
    id<XCUIElementSnapshot> snapshot = [application snapshotWithError:&error];
    if(snapshot == nil)
    {
        return @[];
    }
    CGRect screen = snapshot.frame;
    if(screen.size.width < 2 || screen.size.height < 2)
    {
        screen = CGRectMake(0, 0, 2000, 2000);
    }
    NSMutableArray<PGElementNode *> *nodes = [NSMutableArray array];
    NSString *page = nil;
    BOOL outside = NO;
    [self appendSnapshot:snapshot toNodes:nodes screen:screen pageName:&page outsideApp:&outside depth:0];
    if(nodes.count > PGSnapshotNodeCap)
    {
        NSMutableArray<PGElementNode *> *preferred = [NSMutableArray array];
        for(PGElementNode *node in nodes)
        {
            if(node.clickable || node.interactive || node.scrollable)
            {
                [preferred addObject:node];
            }
        }
        nodes = preferred.count > PGSnapshotNodeCap ? [[preferred subarrayWithRange:NSMakeRange(0, PGSnapshotNodeCap)] mutableCopy] : preferred;
    }
    if(page.length > 0)
    {
        for(PGElementNode *node in nodes)
        {
            node.controller = page;
        }
    }
    [PGElementNode assignPaths:nodes parentPath:@""];
    if(pageName != nil)
    {
        *pageName = page;
    }
    if(outsideApp != nil)
    {
        *outsideApp = outside || [self pageIsSystemScreen:page];
    }
    return nodes;
}

+ (NSArray<PGElementNode *> *)nodesByAddingHoles:(NSArray<PGElementNode *> *)holes
                                 toSnapshotNodes:(NSArray<PGElementNode *> *)snapshotNodes
                                       pixelSize:(CGSize)pixelSize
                                      screenSize:(CGSize)screenSize
{
    if(holes.count == 0 || pixelSize.width < 2 || pixelSize.height < 2 || screenSize.width < 2 || screenSize.height < 2)
    {
        return snapshotNodes ?: @[];
    }
    NSMutableArray<PGElementNode *> *merged = [NSMutableArray arrayWithArray:snapshotNodes ?: @[]];
    NSInteger added = 0;
    for(PGElementNode *hole in holes)
    {
        if(added >= 16 || hole == nil || !hole.clickable)
        {
            continue;
        }
        PGElementNode *scaled = [self node:hole scaledFrom:pixelSize to:screenSize];
        if(scaled.rect.width < 8 || scaled.rect.height < 8)
        {
            continue;
        }
        if([self rect:scaled.rect overlapsNodes:snapshotNodes])
        {
            continue;
        }
        [merged addObject:scaled];
        added += 1;
    }
    [PGElementNode assignPaths:merged parentPath:@""];
    return merged;
}

+ (void)appendSnapshot:(id<XCUIElementSnapshot>)snapshot
               toNodes:(NSMutableArray<PGElementNode *> *)nodes
                screen:(CGRect)screen
              pageName:(NSString **)pageName
            outsideApp:(BOOL *)outsideApp
                 depth:(NSInteger)depth
{
    if(snapshot == nil || depth > 30)
    {
        return;
    }
    NSString *identifier = snapshot.identifier ?: @"";
    NSString *label = snapshot.label ?: @"";
    if(!*outsideApp && ([self textContainsSystemPicker:identifier] || [self textContainsSystemPicker:label]))
    {
        *outsideApp = YES;
        NSLog(@"snapshot outside marker identifier %@ label %@", identifier, label);
    }
    XCUIElementType type = snapshot.elementType;
    if(type == XCUIElementTypeNavigationBar && (*pageName).length == 0)
    {
        *pageName = identifier.length > 0 ? identifier : (label.length > 0 ? label : nil);
    }
    if(type == XCUIElementTypeKeyboard || type == XCUIElementTypeStatusBar)
    {
        return;
    }
    PGElementNode *node = [self nodeFromSnapshot:snapshot screen:screen];
    if(node != nil)
    {
        [nodes addObject:node];
    }
    for(id<XCUIElementSnapshot> child in snapshot.children)
    {
        [self appendSnapshot:child toNodes:nodes screen:screen pageName:pageName outsideApp:outsideApp depth:depth + 1];
    }
}

+ (PGElementNode *)nodeFromSnapshot:(id<XCUIElementSnapshot>)snapshot screen:(CGRect)screen
{
    XCUIElementType type = snapshot.elementType;
    if(![self typeIsUseful:type])
    {
        return nil;
    }
    CGRect frame = snapshot.frame;
    if(![self shouldKeepFrame:frame screen:screen])
    {
        return nil;
    }
    PGElementNode *node = [[PGElementNode alloc] init];
    node.type = [self typeName:type];
    node.identifier = snapshot.identifier ?: @"";
    node.label = snapshot.label ?: @"";
    node.value = [self stringFromValue:snapshot.value];
    node.rect = (PGElementRect){(NSInteger)frame.origin.x, (NSInteger)frame.origin.y, (NSInteger)frame.size.width, (NSInteger)frame.size.height};
    node.visible = YES;
    node.scrollable = type == XCUIElementTypeTable || type == XCUIElementTypeCollectionView || type == XCUIElementTypeScrollView;
    node.clickable = [self typeIsClickable:type];
    node.interactive = node.clickable || [self typeIsTextEntry:type] || type == XCUIElementTypeSlider;
    node.children = @[];
    node.controller = @"";
    node.path = @"";
    return node;
}

+ (BOOL)typeIsUseful:(XCUIElementType)type
{
    return [self typeIsClickable:type] || [self typeIsTextEntry:type] || type == XCUIElementTypeSlider || type == XCUIElementTypeTable || type == XCUIElementTypeCollectionView || type == XCUIElementTypeScrollView || type == XCUIElementTypeStaticText || type == XCUIElementTypeImage || type == XCUIElementTypeIcon;
}

+ (BOOL)typeIsTappableControl:(NSString *)type
{
    return [type isEqualToString:@"Button"] || [type isEqualToString:@"Switch"] || [type isEqualToString:@"Cell"] || [type isEqualToString:@"Link"] || [type isEqualToString:@"ToolbarButton"] || [type isEqualToString:@"MenuItem"];
}

+ (BOOL)typeIsClickable:(XCUIElementType)type
{
    switch(type)
    {
        case XCUIElementTypeButton:
        case XCUIElementTypeSwitch:
        case XCUIElementTypeCell:
        case XCUIElementTypeLink:
        case XCUIElementTypeToolbarButton:
        case XCUIElementTypeMenuItem:
        case XCUIElementTypeImage:
        case XCUIElementTypeIcon:
            return YES;
        default:
            return NO;
    }
}

+ (BOOL)typeIsTextEntry:(XCUIElementType)type
{
    switch(type)
    {
        case XCUIElementTypeTextField:
        case XCUIElementTypeSecureTextField:
        case XCUIElementTypeTextView:
        case XCUIElementTypeSearchField:
            return YES;
        default:
            return NO;
    }
}

+ (NSString *)typeName:(XCUIElementType)type
{
    switch(type)
    {
        case XCUIElementTypeButton: return @"Button";
        case XCUIElementTypeSwitch: return @"Switch";
        case XCUIElementTypeCell: return @"Cell";
        case XCUIElementTypeLink: return @"Link";
        case XCUIElementTypeToolbarButton: return @"ToolbarButton";
        case XCUIElementTypeMenuItem: return @"MenuItem";
        case XCUIElementTypeImage: return @"Image";
        case XCUIElementTypeIcon: return @"Icon";
        case XCUIElementTypeTextField: return @"TextField";
        case XCUIElementTypeSecureTextField: return @"SecureTextField";
        case XCUIElementTypeTextView: return @"TextView";
        case XCUIElementTypeSearchField: return @"SearchField";
        case XCUIElementTypeSlider: return @"Slider";
        case XCUIElementTypeTable: return @"Table";
        case XCUIElementTypeCollectionView: return @"CollectionView";
        case XCUIElementTypeScrollView: return @"ScrollView";
        case XCUIElementTypeStaticText: return @"StaticText";
        default: return @"View";
    }
}

+ (BOOL)shouldKeepFrame:(CGRect)frame screen:(CGRect)screen
{
    if(frame.size.width < 8 || frame.size.height < 8)
    {
        return NO;
    }
    if(screen.size.width > 0 && screen.size.width < 1500 && frame.size.width > screen.size.width * 0.92 && frame.size.height > screen.size.height * 0.92)
    {
        return NO;
    }
    CGPoint center = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
    return CGRectContainsPoint(screen, center);
}

+ (NSString *)stringFromValue:(id)value
{
    if([value isKindOfClass:[NSString class]])
    {
        return value;
    }
    return value == nil ? @"" : [value description];
}

+ (BOOL)textContainsSystemPicker:(NSString *)text
{
    if(text.length == 0)
    {
        return NO;
    }
    for(NSString *marker in @[@"PUPicker", @"PHPicker", @"PUPhotoPicker", @"PXPhotos", @"PhotosUI"])
    {
        if([text rangeOfString:marker options:NSCaseInsensitiveSearch].location != NSNotFound)
        {
            return YES;
        }
    }
    return NO;
}

+ (BOOL)pageIsSystemScreen:(NSString *)name
{
    if(name.length == 0)
    {
        return NO;
    }
    if([self textContainsSystemPicker:name])
    {
        return YES;
    }
    return [name caseInsensitiveCompare:@"Photos"] == NSOrderedSame || [name caseInsensitiveCompare:@"PUPickerContainer"] == NSOrderedSame;
}

+ (PGElementNode *)node:(PGElementNode *)node scaledFrom:(CGSize)pixelSize to:(CGSize)screenSize
{
    PGElementNode *scaled = [[PGElementNode alloc] init];
    scaled.type = node.type;
    scaled.identifier = node.identifier;
    scaled.label = node.label;
    scaled.value = node.value;
    scaled.controller = node.controller;
    scaled.path = @"";
    scaled.visible = node.visible;
    scaled.interactive = node.interactive;
    scaled.scrollable = node.scrollable;
    scaled.clickable = node.clickable;
    scaled.children = @[];
    PGElementRect rect = node.rect;
    rect.left = (NSInteger)(rect.left * screenSize.width / pixelSize.width);
    rect.top = (NSInteger)(rect.top * screenSize.height / pixelSize.height);
    rect.width = (NSInteger)(rect.width * screenSize.width / pixelSize.width);
    rect.height = (NSInteger)(rect.height * screenSize.height / pixelSize.height);
    scaled.rect = rect;
    return scaled;
}

+ (BOOL)rect:(PGElementRect)rect overlapsNodes:(NSArray<PGElementNode *> *)nodes
{
    NSInteger area = MAX(rect.width * rect.height, 1);
    for(PGElementNode *node in nodes)
    {
        NSInteger left = MAX(rect.left, node.rect.left);
        NSInteger top = MAX(rect.top, node.rect.top);
        NSInteger right = MIN(rect.left + rect.width, node.rect.left + node.rect.width);
        NSInteger bottom = MIN(rect.top + rect.height, node.rect.top + node.rect.height);
        if(right <= left || bottom <= top)
        {
            continue;
        }
        if((right - left) * (bottom - top) * 2 >= area)
        {
            return YES;
        }
    }
    return NO;
}

@end
