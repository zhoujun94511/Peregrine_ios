#import "PGElementQuery.h"

@implementation PGElementQuery

+ (PGElementNode *)nodeForOperate:(PGOperate *)operate inNodes:(NSArray<PGElementNode *> *)nodes
{
    for(PGElementNode *node in [PGElementNode flattenedNodes:nodes])
    {
        BOOL sameType = operate.name.length == 0 || [node.type isEqualToString:operate.name];
        BOOL sameRect = node.rect.left == operate.rect.left && node.rect.top == operate.rect.top && node.rect.width == operate.rect.width && node.rect.height == operate.rect.height;
        if(sameType && sameRect)
        {
            return node;
        }
    }
    return nil;
}

+ (XCUIElement *)elementMatchingNode:(PGElementNode *)node inApplication:(XCUIApplication *)application frame:(CGRect *)frame
{
    XCUIElementType type = [self elementTypeForNode:node];
    if(type == XCUIElementTypeAny || application == nil)
    {
        return nil;
    }
    XCUIElementQuery *query = [application descendantsMatchingType:type];
    NSString *identifier = node.identifier ?: @"";
    XCUIElement *element = nil;
    if([identifier hasPrefix:@"_"])
    {
        NSInteger index = [[identifier substringFromIndex:1] integerValue];
        NSArray<XCUIElement *> *all = query.allElementsBoundByIndex;
        if(index >= 0 && index < (NSInteger)all.count)
        {
            element = all[index];
        }
    }
    else if(identifier.length > 0)
    {
        element = [self elementIn:[query matchingIdentifier:identifier] nearestRect:node.rect];
    }
    if(element == nil && node.label.length > 0)
    {
        NSPredicate *label = [NSPredicate predicateWithFormat:@"label CONTAINS[c] %@", node.label];
        element = [self elementIn:[query matchingPredicate:label] nearestRect:node.rect];
    }
    if(element == nil)
    {
        return nil;
    }
    // One round trip for existence and frame; reading frame of a vanished element records a test failure.
    NSError *error = nil;
    id<XCUIElementSnapshot> snapshot = [element snapshotWithError:&error];
    CGRect found = snapshot == nil ? CGRectZero : snapshot.frame;
    if(found.size.width <= 0 || found.size.height <= 0)
    {
        return nil;
    }
    if(frame != NULL)
    {
        *frame = found;
    }
    return element;
}

// Resolving query[identifier] or query.element with more than one match records an
// XCTest failure that @try cannot undo, so candidates are always bound by index.
+ (XCUIElement *)elementIn:(XCUIElementQuery *)query nearestRect:(PGElementRect)rect
{
    NSArray<XCUIElement *> *candidates = query.allElementsBoundByIndex;
    if(candidates.count <= 1)
    {
        return candidates.firstObject;
    }
    if(candidates.count > 24)
    {
        candidates = [candidates subarrayWithRange:NSMakeRange(0, 24)];
    }
    CGRect target = CGRectMake(rect.left, rect.top, rect.width, rect.height);
    XCUIElement *best = nil;
    CGFloat bestArea = 0;
    for(XCUIElement *candidate in candidates)
    {
        CGRect overlap = CGRectIntersection(candidate.frame, target);
        CGFloat area = CGRectIsNull(overlap) ? 0 : overlap.size.width * overlap.size.height;
        if(best == nil || area > bestArea)
        {
            best = candidate;
            bestArea = area;
        }
    }
    return best;
}

+ (XCUIElementType)elementTypeForNode:(PGElementNode *)node
{
    NSString *type = node.type.lowercaseString ?: @"";
    if([type containsString:@"secure"])
    {
        return XCUIElementTypeSecureTextField;
    }
    if([type containsString:@"search"])
    {
        return XCUIElementTypeSearchField;
    }
    if([type containsString:@"textview"])
    {
        return XCUIElementTypeTextView;
    }
    if([type containsString:@"textfield"] || [type containsString:@"uitextfield"])
    {
        return XCUIElementTypeTextField;
    }
    if([type containsString:@"button"])
    {
        return XCUIElementTypeButton;
    }
    if([type containsString:@"icon"])
    {
        return XCUIElementTypeIcon;
    }
    if([type containsString:@"image"])
    {
        return XCUIElementTypeImage;
    }
    if([type containsString:@"statictext"] || [type containsString:@"uilabel"])
    {
        return XCUIElementTypeStaticText;
    }
    if([type containsString:@"cell"])
    {
        return XCUIElementTypeCell;
    }
    if([type containsString:@"switch"])
    {
        return XCUIElementTypeSwitch;
    }
    if([type containsString:@"slider"])
    {
        return XCUIElementTypeSlider;
    }
    if([type containsString:@"collection"])
    {
        return XCUIElementTypeCollectionView;
    }
    if([type containsString:@"table"])
    {
        return XCUIElementTypeTable;
    }
    if([type containsString:@"scroll"])
    {
        return XCUIElementTypeScrollView;
    }
    return XCUIElementTypeAny;
}

@end
