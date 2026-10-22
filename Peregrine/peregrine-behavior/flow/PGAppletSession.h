#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Watches whether the current page has entered a configured schema.
@interface PGAppletSession : NSObject
@property (nonatomic, assign, readonly) BOOL entered;
@property (nonatomic, assign, readonly) NSInteger failures;
@property (nonatomic, assign, readonly) BOOL openAttempted;
- (instancetype)initWithSchema:(nullable NSString *)schema;
- (nullable NSURL *)URLToOpenOnce;
+ (nullable NSURL *)openableURLFromSchema:(nullable NSString *)schema;
- (void)observeActivity:(nullable NSString *)activity;
- (BOOL)writeSummaryToDirectory:(NSString *)directory error:(NSError * _Nullable *)error;
- (NSString *)summary;
@end

NS_ASSUME_NONNULL_END
