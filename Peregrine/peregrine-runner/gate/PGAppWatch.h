#import <XCTest/XCTest.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PGAppWatchRecovery) {
    PGAppWatchRecoveryNone = 0,
    // The app left its own screen. The watch activated it.
    PGAppWatchRecoveryRelaunch,
    // Repeated returns did not bring its own screen back. This visit restarts the app.
    PGAppWatchRecoveryRestart,
};

typedef NS_ENUM(NSInteger, PGForegroundWatch) {
    // The target may keep being explored.
    PGForegroundWatchTarget = 0,
    // The foreground is not the target yet. Do not explore it.
    PGForegroundWatchWait,
    // It has stayed long enough. The caller brings the target back.
    PGForegroundWatchReturn,
};

// The foreground process is XCUIApplication.state, not a screen title.
// A sheet covering most of the target is handled separately: activate does not close it.
@interface PGAppWatch : NSObject
@property (nonatomic, assign, readonly) PGAppWatchRecovery lastRecovery;
@property (nonatomic, assign, readonly) XCUIApplicationState lastState;
@property (nonatomic, assign, readonly) NSInteger lastAttempt;
- (PGForegroundWatch)considerProcess:(XCUIApplication *)application allowsRestart:(BOOL)allowsRestart;
- (PGForegroundWatch)considerCovered:(BOOL)covered application:(XCUIApplication *)application allowsRestart:(BOOL)allowsRestart;
- (BOOL)coverHoldActive;
- (void)noteInApplication;
- (BOOL)returnFromForeignScreen:(XCUIApplication *)application allowsRestart:(BOOL)allowsRestart;
// A background pulse logs when the loop stops calling beat. A slow returned step and a long stretch
// with no exploration each ask for one restart, so a blocked snapshot cannot sit there for the whole run.
- (void)startPulse;
- (void)beat;
- (BOOL)consumeSlowStep;
- (BOOL)exploreIdle;
@end

NS_ASSUME_NONNULL_END
