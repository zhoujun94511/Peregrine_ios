#import <XCTest/XCTest.h>
#import "PGBehavior.h"

NS_ASSUME_NONNULL_BEGIN

// One public accessibility snapshot for the whole screen.
// This does not require the in-app stub and does not resolve each element.
// The default run screenshots every step and asks this tree to correct a click.
typedef NS_ENUM(NSInteger, PGSnapshotSourceMode) {
    PGSnapshotSourceModeCombined = 0,
    PGSnapshotSourceModeScreenshot = 1,
    PGSnapshotSourceModeSnapshot = 2,
};

@interface PGSnapshotTree : NSObject
+ (PGSnapshotSourceMode)sourceModeInEnvironment:(NSDictionary *)environment;
+ (nullable PGElementNode *)controlCoveringRect:(PGElementRect)rect inNodes:(NSArray<PGElementNode *> *)nodes;
+ (NSArray<PGElementNode *> *)nodesFromApplication:(XCUIApplication *)application
                                          pageName:(NSString * _Nullable * _Nullable)pageName
                                        outsideApp:(BOOL * _Nullable)outsideApp;
+ (NSArray<PGElementNode *> *)nodesByAddingHoles:(NSArray<PGElementNode *> *)holes
                                 toSnapshotNodes:(NSArray<PGElementNode *> *)snapshotNodes
                                       pixelSize:(CGSize)pixelSize
                                      screenSize:(CGSize)screenSize;
@end

NS_ASSUME_NONNULL_END
