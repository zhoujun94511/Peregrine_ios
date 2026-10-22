#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Records distinct screen names seen during a run.
@interface PGCoverage : NSObject
@property (nonatomic, assign, readonly) NSInteger count;
- (void)recordActivity:(nullable NSString *)activity;
- (NSString *)summary;
- (BOOL)writeSummaryToDirectory:(NSString *)directory error:(NSError * _Nullable *)error;
@end

NS_ASSUME_NONNULL_END
