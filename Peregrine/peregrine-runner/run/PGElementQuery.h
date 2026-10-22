#import <XCTest/XCTest.h>
#import "PGBehavior.h"

NS_ASSUME_NONNULL_BEGIN

// Finds the live XCTest element behind a node through the public element query.
@interface PGElementQuery : NSObject
+ (nullable PGElementNode *)nodeForOperate:(PGOperate *)operate inNodes:(NSArray<PGElementNode *> *)nodes;
// frame receives the element's current frame; nil when the element is gone or has no size.
+ (nullable XCUIElement *)elementMatchingNode:(nullable PGElementNode *)node inApplication:(XCUIApplication *)application frame:(CGRect *)frame;
@end

NS_ASSUME_NONNULL_END
