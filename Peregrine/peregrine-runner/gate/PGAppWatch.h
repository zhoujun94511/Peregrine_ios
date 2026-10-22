#import <XCTest/XCTest.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PGAppWatchRecovery) {
    PGAppWatchRecoveryNone = 0,
    // The app left its own screen. The watch activated it.
    PGAppWatchRecoveryRelaunch,
    // Two activations did not bring its own screen back. The third visit restarts the app.
    PGAppWatchRecoveryRestart,
};

// Brings the app under test back when it leaves the foreground or a system screen.
@interface PGAppWatch : NSObject
@property (nonatomic, assign, readonly) PGAppWatchRecovery lastRecovery;
@property (nonatomic, assign, readonly) XCUIApplicationState lastState;
@property (nonatomic, assign, readonly) NSInteger lastAttempt;
- (BOOL)recoverApplication:(XCUIApplication *)application allowsRestart:(BOOL)allowsRestart;
- (void)noteInApplication;
- (BOOL)returnFromForeignScreen:(XCUIApplication *)application allowsRestart:(BOOL)allowsRestart;
@end

NS_ASSUME_NONNULL_END
