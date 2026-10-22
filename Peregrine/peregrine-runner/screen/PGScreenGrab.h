#import <XCTest/XCTest.h>
#import "PGBehavior.h"
#import "PGSegmentation.h"

NS_ASSUME_NONNULL_BEGIN

// One upright grayscale screenshot and the segments cut from it.
@interface PGScreenGrab : NSObject
+ (uint64_t)hashGray:(const uint8_t *)bytes width:(NSInteger)width height:(NSInteger)height;
+ (nullable NSData *)grayDataFromApplication:(XCUIApplication *)application width:(NSInteger *)width height:(NSInteger *)height;
+ (nullable UIImage *)uprightScreenshotOfApplication:(XCUIApplication *)application;
+ (nullable NSData *)grayDataFromImage:(nullable UIImage *)image width:(NSInteger *)width height:(NSInteger *)height;
+ (NSArray<PGElementNode *> *)nodesFromGray:(const uint8_t *)gray width:(NSInteger)width height:(NSInteger)height segmentation:(PGSegmentation *)segmentation;
+ (NSArray<PGElementNode *> *)nodesFromScreenshot:(XCUIApplication *)application segmentation:(PGSegmentation *)segmentation;
// pixels is the screenshot size the operate was chosen in. Segments rarely reach the
// right and bottom edges, so their extent is not a usable stand-in.
+ (PGOperate *)scaleOperate:(PGOperate *)operate fromPixels:(CGSize)pixels toScreen:(CGSize)points;
@end

NS_ASSUME_NONNULL_END
