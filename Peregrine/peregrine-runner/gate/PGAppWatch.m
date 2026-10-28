#import "PGAppWatch.h"

static const NSInteger PGAppWatchRestartAfter = 3;
// Not the target has to stay this long before a return. One transition frame is not enough.
static const NSTimeInterval PGForeignForegroundSeconds = 3;
// One returned step this long has already blocked the run. The next beat restarts the target.
static const NSTimeInterval PGRunSlowStepSeconds = 60;
// The loop is alive but has not reached exploration. Restart rather than wait out the session.
static const NSTimeInterval PGRunExploreIdleSeconds = 120;
static const NSTimeInterval PGRunPulseStallSeconds = 90;

@interface PGAppWatch ()
@property (nonatomic, assign) NSInteger misses;
@property (nonatomic, assign) NSInteger foreignScreens;
@property (nonatomic, assign) NSInteger coveredTries;
@property (nonatomic, strong) NSDate *leftSince;
@property (nonatomic, strong) NSDate *coveredSince;
@property (nonatomic, assign, readwrite) PGAppWatchRecovery lastRecovery;
@property (nonatomic, assign, readwrite) XCUIApplicationState lastState;
@property (nonatomic, assign, readwrite) NSInteger lastAttempt;
@property (nonatomic, strong) NSDate *lastBeat;
@property (nonatomic, strong) NSDate *lastExplore;
@property (nonatomic, assign) BOOL pulseStarted;
@property (nonatomic, assign) BOOL stallLogged;
@property (nonatomic, assign) BOOL stepWasSlow;
@end

@implementation PGAppWatch

- (PGForegroundWatch)considerProcess:(XCUIApplication *)application allowsRestart:(BOOL)allowsRestart
{
    XCUIApplicationState state = application.state;
    self.lastState = state;
    self.lastRecovery = PGAppWatchRecoveryNone;
    if(state == XCUIApplicationStateRunningForeground)
    {
        self.misses = 0;
        self.leftSince = nil;
        return PGForegroundWatchTarget;
    }
    // Unknown is not evidence either way, and must not clear a hold already running.
    NSString *reason = @"background";
    if(state == XCUIApplicationStateUnknown)
    {
        if(self.leftSince == nil)
        {
            return PGForegroundWatchTarget;
        }
        reason = @"unknown";
    }
    else if(state == XCUIApplicationStateNotRunning)
    {
        reason = @"not_running";
    }
    if([self holdLeft:reason] == PGForegroundWatchWait)
    {
        return PGForegroundWatchWait;
    }
    return [self returnProcess:application allowsRestart:allowsRestart];
}

- (PGForegroundWatch)holdLeft:(NSString *)reason
{
    if(self.leftSince == nil)
    {
        self.leftSince = [NSDate date];
    }
    NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:self.leftSince];
    NSLog(@"foreground not target %@ %.0fs", reason, elapsed);
    return elapsed < PGForeignForegroundSeconds ? PGForegroundWatchWait : PGForegroundWatchReturn;
}

- (PGForegroundWatch)returnProcess:(XCUIApplication *)application allowsRestart:(BOOL)allowsRestart
{
    self.misses += 1;
    self.lastAttempt = self.misses;
    if(self.misses >= PGAppWatchRestartAfter && allowsRestart)
    {
        [self restartApplication:application];
        return PGForegroundWatchReturn;
    }
    [application activate];
    self.lastRecovery = PGAppWatchRecoveryRelaunch;
    return PGForegroundWatchReturn;
}

- (PGForegroundWatch)considerCovered:(BOOL)covered application:(XCUIApplication *)application allowsRestart:(BOOL)allowsRestart
{
    if(!covered)
    {
        self.coveredSince = nil;
        self.coveredTries = 0;
        return PGForegroundWatchTarget;
    }
    if(self.coveredSince == nil)
    {
        self.coveredSince = [NSDate date];
    }
    NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:self.coveredSince];
    NSLog(@"foreground covered %.0fs", elapsed);
    if(elapsed < PGForeignForegroundSeconds)
    {
        return PGForegroundWatchWait;
    }
    self.coveredTries += 1;
    self.lastAttempt = self.coveredTries;
    if(self.coveredTries >= PGAppWatchRestartAfter && allowsRestart)
    {
        [self restartApplication:application];
        self.coveredSince = nil;
        self.coveredTries = 0;
        return PGForegroundWatchReturn;
    }
    self.lastRecovery = PGAppWatchRecoveryRelaunch;
    return PGForegroundWatchReturn;
}

- (BOOL)coverHoldActive
{
    return self.coveredSince != nil;
}

- (void)noteInApplication
{
    self.foreignScreens = 0;
    @synchronized(self)
    {
        self.lastExplore = [NSDate date];
    }
}

- (void)startPulse
{
    if(self.pulseStarted)
    {
        return;
    }
    self.pulseStarted = YES;
    [self beat];
    [self noteInApplication];
    NSThread *thread = [[NSThread alloc] initWithTarget:self selector:@selector(pulseLoop) object:nil];
    thread.name = @"peregrine-pulse";
    [thread start];
}

- (void)beat
{
    NSDate *now = [NSDate date];
    @synchronized(self)
    {
        if(self.lastBeat != nil && [now timeIntervalSinceDate:self.lastBeat] >= PGRunSlowStepSeconds)
        {
            self.stepWasSlow = YES;
            NSLog(@"run step slow %.0fs", [now timeIntervalSinceDate:self.lastBeat]);
        }
        self.lastBeat = now;
        self.stallLogged = NO;
    }
}

- (BOOL)consumeSlowStep
{
    @synchronized(self)
    {
        BOOL slow = self.stepWasSlow;
        self.stepWasSlow = NO;
        return slow;
    }
}

- (BOOL)exploreIdle
{
    @synchronized(self)
    {
        if(self.lastExplore == nil)
        {
            return NO;
        }
        return [[NSDate date] timeIntervalSinceDate:self.lastExplore] >= PGRunExploreIdleSeconds;
    }
}

- (void)pulseLoop
{
    while(YES)
    {
        [NSThread sleepForTimeInterval:5];
        NSDate *beat = nil;
        BOOL alreadyLogged = NO;
        @synchronized(self)
        {
            beat = self.lastBeat;
            alreadyLogged = self.stallLogged;
        }
        NSTimeInterval idle = beat == nil ? 0 : [[NSDate date] timeIntervalSinceDate:beat];
        if(idle < PGRunPulseStallSeconds || alreadyLogged)
        {
            continue;
        }
        @synchronized(self)
        {
            self.stallLogged = YES;
        }
        NSLog(@"run pulse stalled %.0fs", idle);
    }
}

- (BOOL)returnFromForeignScreen:(XCUIApplication *)application allowsRestart:(BOOL)allowsRestart
{
    self.lastState = application.state;
    self.foreignScreens += 1;
    self.lastAttempt = self.foreignScreens;
    if(self.foreignScreens >= PGAppWatchRestartAfter && allowsRestart)
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
    self.leftSince = nil;
    self.lastRecovery = PGAppWatchRecoveryRestart;
}

@end
