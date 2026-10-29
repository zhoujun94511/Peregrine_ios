#import "PGActionFilter.h"
#import "PGOverlayRules.h"

static NSInteger PGShareSheetSeen;

static BOOL PGNodeIsPurchase(PGElementNode *node)
{
    NSString *text = [NSString stringWithFormat:@"%@ %@ %@", node.label ?: @"", node.value ?: @"", node.identifier ?: @""];
    // A price opens the system payment sheet. It is not a control to explore.
    return [PGOverlayRules textIsPurchase:text] || [PGOverlayRules textHasPrice:text];
}

static BOOL PGNodeIsShareEntry(PGElementNode *node)
{
    if(PGShareSheetSeen < 1)
    {
        return NO;
    }
    NSString *text = [NSString stringWithFormat:@"%@ %@ %@", node.label ?: @"", node.value ?: @"", node.identifier ?: @""];
    return [PGOverlayRules textIsShareEntry:text];
}

@implementation PGActionFilter

+ (void)noteShareSheetSeen
{
    PGShareSheetSeen = 1;
}

+ (BOOL)includeNode:(PGElementNode *)node kind:(PGActionFilterKind)kind visits:(NSInteger)visits
{
    return [self includeNode:node kind:kind visits:visits target:nil];
}

+ (BOOL)includeNode:(PGElementNode *)node
               kind:(PGActionFilterKind)kind
             visits:(NSInteger)visits
             target:(NSString *)target
{
    if(target.length > 0)
    {
        BOOL hit = [node.identifier isEqualToString:target]
            || [node.label containsString:target]
            || [node.value containsString:target]
            || [node.type containsString:target];
        if(!hit)
        {
            return NO;
        }
    }
    if(kind == PGActionFilterAll)
    {
        return YES;
    }
    BOOL sized = node.rect.width > 0 && node.rect.height > 0;
    BOOL valid = node.visible && sized;
    if(kind == PGActionFilterValid)
    {
        return valid;
    }
    BOOL enabled = valid && (node.clickable || node.interactive) && !PGNodeIsPurchase(node) && !PGNodeIsShareEntry(node);
    if(kind == PGActionFilterEnabled)
    {
        return enabled;
    }
    return enabled && visits < 1;
}

+ (NSInteger)priorityForNode:(PGElementNode *)node
{
    NSString *type = node.type.lowercaseString ?: @"";
    if([type containsString:@"button"])
    {
        return 5;
    }
    if([type containsString:@"field"] || [type containsString:@"textview"])
    {
        return 3;
    }
    if([type containsString:@"icon"])
    {
        return 4;
    }
    if([type containsString:@"dialog"])
    {
        return 3;
    }
    if([type containsString:@"webview"])
    {
        return 0;
    }
    if([type containsString:@"text"])
    {
        return 2;
    }
    return 1;
}

@end
