#import "PGExclusionCover.h"

@implementation PGExclusionCover

+ (NSArray<PGElementNode *> *)coversForExclusion:(PGElementExclusion *)exclusion
                                   inApplication:(XCUIApplication *)application
                                       pixelSize:(CGSize)pixelSize
                                      screenSize:(CGSize)screenSize
{
    if(exclusion.names.count == 0 || application == nil || pixelSize.width < 2 || pixelSize.height < 2 || screenSize.width < 2 || screenSize.height < 2)
    {
        return @[];
    }
    NSMutableArray<PGElementNode *> *covers = [NSMutableArray array];
    @try
    {
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"identifier IN %@ OR label IN %@", exclusion.names, exclusion.names];
        XCUIElementQuery *query = [[application descendantsMatchingType:XCUIElementTypeAny] matchingPredicate:predicate];
        for(XCUIElement *element in query.allElementsBoundByIndex)
        {
            CGRect frame = element.frame;
            if(frame.size.width < 1 || frame.size.height < 1)
            {
                continue;
            }
            PGElementNode *cover = [[PGElementNode alloc] init];
            cover.rect = (PGElementRect){
                (NSInteger)(frame.origin.x * pixelSize.width / screenSize.width),
                (NSInteger)(frame.origin.y * pixelSize.height / screenSize.height),
                (NSInteger)(frame.size.width * pixelSize.width / screenSize.width),
                (NSInteger)(frame.size.height * pixelSize.height / screenSize.height)
            };
            [covers addObject:cover];
        }
    }
    @catch(NSException *exception)
    {
        NSLog(@"exclude elements query failed %@", exception.reason ?: exception.name);
    }
    return covers;
}

@end
