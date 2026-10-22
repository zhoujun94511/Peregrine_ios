#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Remembers which activity each action opened, including across runs.
@interface PGReuseModel : NSObject
@property (nonatomic, copy, readonly, nullable) NSString *filePath;

- (void)loadFromDirectory:(nullable NSString *)directory bundleID:(nullable NSString *)bundleID;
- (void)save;
- (void)noteAction:(nullable NSString *)actionID reachedActivity:(nullable NSString *)activity;
- (BOOL)containsAction:(nullable NSString *)actionID;
// Share of stored arrivals whose activity has not been seen this run. 0 when the action is unknown.
- (double)fractionOfUnseenActivitiesForAction:(nullable NSString *)actionID
                                         seen:(nullable NSSet<NSString *> *)seen;
@end

NS_ASSUME_NONNULL_END
