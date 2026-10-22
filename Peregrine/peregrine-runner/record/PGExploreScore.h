#import "PGBehavior.h"

NS_ASSUME_NONNULL_BEGIN

// Counts screens and clicks for one exploration run.
@interface PGExploreScore : NSObject
- (void)noteSource:(NSString *)source activity:(nullable NSString *)activity fingerprint:(uint64_t)fingerprint operate:(nullable PGOperate *)operate bundleID:(nullable NSString *)bundleID;
- (NSDictionary *)fields;
- (NSString *)line;
@end

NS_ASSUME_NONNULL_END
