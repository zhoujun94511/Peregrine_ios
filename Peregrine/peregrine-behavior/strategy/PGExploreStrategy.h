#import "PGBehavior.h"

NS_ASSUME_NONNULL_BEGIN

@interface PGExploreStrategy : NSObject
// Fewer than 20001 observations uses 0.5, then 0.4, 0.3, and 0.25.
+ (double)learningRateForObservations:(NSInteger)observations;
@end

NS_ASSUME_NONNULL_END
