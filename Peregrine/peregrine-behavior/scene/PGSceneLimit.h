#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PGSceneLimitState) {
    PGSceneLimitStateIdle = 0,
    PGSceneLimitStateRunning = 1,
    PGSceneLimitStateInside = 2,
    PGSceneLimitStateStopped = 3,
};

// While running, a screen is allowed when it is not blocked, it is allowed
// if an allow-list exists, and the configured duration has not elapsed.
// Idle and stopped scenes are not checked. Leaving the scheme asks the
// caller to handle the jump-out.
@interface PGSceneLimit : NSObject
@property (nonatomic, copy) NSString *scheme;
@property (nonatomic, copy) NSString *schemeViewController;
@property (nonatomic, copy) NSArray<NSString *> *allowViewControllers;
@property (nonatomic, copy) NSArray<NSString *> *blockViewControllers;
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, strong, nullable) NSDate *startedAt;
@property (nonatomic, assign) PGSceneLimitState state;

- (BOOL)shouldCheck;
- (BOOL)allowsViewController:(nullable NSString *)name;
- (NSUInteger)actionSource;
@end

NS_ASSUME_NONNULL_END
