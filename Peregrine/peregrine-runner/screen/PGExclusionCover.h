#import <XCTest/XCTest.h>
#import "PGBehavior.h"
#import "PGElementExclusion.h"

NS_ASSUME_NONNULL_BEGIN

// Current frames of the excluded elements, for screens that have no element tree.
@interface PGExclusionCover : NSObject
// One query plus one frame read per match. Frames come back in screenshot pixels.
+ (NSArray<PGElementNode *> *)coversForExclusion:(PGElementExclusion *)exclusion
                                   inApplication:(XCUIApplication *)application
                                       pixelSize:(CGSize)pixelSize
                                      screenSize:(CGSize)screenSize;
@end

NS_ASSUME_NONNULL_END
