#import "PGAppWatch.h"

static const NSInteger PGAppWatchRestartAfter = 3;

@interface PGAppWatch ()
@property (nonatomic, assign) NSInteger misses;
@property (nonatomic, assign) NSInteger foreignScreens;
@property (nonatomic, assign, readwrite) PGAppWatchRecovery lastRecovery;
@property (nonatomic, assign, readwrite) XCUIApplicationState lastState;
@property (nonatomic, assign, readwrite) NSInteger lastAttempt;
@end

@implementation PGAppWatch

- (BOOL)recoverApplication:(XCUIApplication *)application allowsRestart:(BOOL)allowsRestart
{
    XCUIApplicationState state = application.state;
    self.lastState = state;
    self.lastRecovery = PGAppWatchRecoveryNone;
    if(state == XCUIApplicationStateRunningForeground)
    {
        self.misses = 0;
        return NO;
    }
    if(state == XCUIApplicationStateUnknown)
    {
        return NO;
    }
    self.misses += 1;
    self.lastAttempt = self.misses;
    if(self.misses >= PGAppWatchRestartAfter && allowsRestart)
    {
        [self restartApplication:application];
        return YES;
    }
    [application activate];
    self.lastRecovery = PGAppWatchRecoveryRelaunch;
    return YES;
}

- (void)noteInApplication
{
    self.foreignScreens = 0;
}

- (BOOL)returnFromForeignScreen:(XCUIApplication *)application allowsRestart:(BOOL)allowsRestart
{
    self.lastState = application.state;
    self.foreignScreens += 1;
    self.lastAttempt = self.foreignScreens;
    if(self.foreignScreens >= 3 && allowsRestart)
    {
        [self restartApplication:application];
        self.foreignScreens = 0;
        return YES;
    }
    [application activate];
    self.lastRecovery = PGAppWatchRecoveryRelaunch;
    return YES;
}

- (void)restartApplication:(XCUIApplication *)application
{
    [application terminate];
    [application launch];
    self.misses = 0;
    self.lastRecovery = PGAppWatchRecoveryRestart;
}

@end
