#import <Foundation/Foundation.h>
#import "PGBehavior.h"

NS_ASSUME_NONNULL_BEGIN

@interface PGSegment : NSObject
@property (nonatomic, assign) PGElementRect rect;
@property (nonatomic, copy) NSString *type;
@end

// Splits a grayscale screenshot into horizontal bands, then columns.
// A centered block that does not touch the screen edge is treated as a dialog
// and segmented on its own. This replaces the OpenCV call sites; it does not
// embed the OpenCV library.
@interface PGSegmentation : NSObject
// Pixel boxes {left,top,width,height}. A segment whose center falls inside one is dropped.
@property (nonatomic, copy) NSArray *excludeRects;
- (NSArray<PGSegment *> *)segmentsFromGray:(const uint8_t *)pixels
                                     width:(NSInteger)width
                                    height:(NSInteger)height;
- (NSArray<PGElementNode *> *)nodesFromGray:(const uint8_t *)pixels
                                      width:(NSInteger)width
                                     height:(NSInteger)height;
@end

NS_ASSUME_NONNULL_END
