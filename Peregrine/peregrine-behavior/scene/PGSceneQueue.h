#import "PGBehavior.h"

NS_ASSUME_NONNULL_BEGIN

// Plays scene limits in order. Each entry may set scheme, allow, block,
// duration and start (seconds from the beginning of the run).
// While a scene is active, a blocked or not-allowed page asks for BACK.
// actionSource is 3 only while a scene is active.
@interface PGSceneQueue : NSObject
@property (nonatomic, assign, readonly) NSUInteger actionSource;
@property (nonatomic, copy, readonly) NSString *activeScheme;
@property (nonatomic, copy, readonly) NSArray<NSString *> *activeAllow;
@property (nonatomic, copy, readonly) NSArray<NSString *> *activeBlock;
- (instancetype)initWithScenes:(NSArray *)scenes;
- (nullable PGOperate *)restrictionForActivity:(nullable NSString *)activity at:(NSDate *)now;
@end

NS_ASSUME_NONNULL_END
