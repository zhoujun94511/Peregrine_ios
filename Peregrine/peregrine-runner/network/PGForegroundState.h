#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Reads this process's own UIKit foreground state. It never touches the network.
/// The wireless-data decision is made on the first connect, so the probe needs to know
/// whether the runner was Active at that moment, not only what XCUIApplication reports.
@interface PGForegroundState : NSObject
/// UIApplicationState as an integer (0 active, 1 inactive, 2 background), or -1 when unavailable.
+ (NSInteger)applicationState;
/// Polls until UIApplicationStateActive or the timeout.
+ (BOOL)waitUntilActive:(NSTimeInterval)timeout;
@end

NS_ASSUME_NONNULL_END
