#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "PGOperate.h"

NS_ASSUME_NONNULL_BEGIN

// Shares of model steps that are not taps, read from testconfig.json GestureRatio.
// SWIPE and PINCH act on the whole screen; LONG_PRESS, DOUBLE_TAP and DRAG act on the chosen node.
// A key that is missing keeps its default; all zero keeps every model step a tap.
@interface PGGestureMix : NSObject
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSNumber *> *ratios;
+ (NSDictionary<NSString *, NSNumber *> *)defaultRatios;
- (instancetype)initWithRatios:(nullable NSDictionary *)ratios;
// One of SWIPE, PINCH, LONG_PRESS, DOUBLE_TAP, DRAG or CLICK.
- (NSString *)nextGesture;
// Space is the coordinate space of the nodes: screenshot pixels or screen points.
- (PGOperate *)screenOperate:(NSString *)gesture space:(CGSize)space;
- (void)applyGesture:(NSString *)gesture toOperate:(PGOperate *)operate space:(CGSize)space;
// Scrolls mostly up, then down, then sideways.
- (NSString *)scrollAct;
@end

NS_ASSUME_NONNULL_END
