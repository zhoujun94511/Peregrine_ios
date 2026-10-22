#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Draws a screenshot so its pixel buffer is upright before segmentation.
@interface PGScreenMap : NSObject
+ (UIImage *)uprightImage:(UIImage *)image;
@end

NS_ASSUME_NONNULL_END
