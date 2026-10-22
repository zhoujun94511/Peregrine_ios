#import "PGSession.h"
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

// Turns an operate into a gesture.
// CLICK uses the rect center about 30% of the time and a random point inside it otherwise.
// A tap in the status-bar band is dropped.
// SWIPE_LEFT, SWIPE_RIGHT, SWIPE_UP and SWIPE_DOWN move from the rect center by 30% of its width
// or 25% of its height, at least 40; without a rect they use the whole screen.
// A path of at least two points is followed in order.
// DOUBLE_TAP picks its point like CLICK. PINCH_OUT and PINCH_IN zoom by 2 and 0.5 around the app center.
// DRAG holds the first path point for 0.8 s, or waitTime, then moves to the last.
// id or text selects a node before the tap. FORCE_BACK is a longer edge drag.
@interface PGCommandPlayer : NSObject
+ (PGGesture *)gestureForOperate:(PGOperate *)operate
                          inNodes:(NSArray<PGElementNode *> *)nodes
                           screen:(CGSize)screen;
@end

NS_ASSUME_NONNULL_END
