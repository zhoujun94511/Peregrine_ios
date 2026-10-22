#import "PGForegroundState.h"
#import <UIKit/UIKit.h>

@implementation PGForegroundState

+ (NSInteger)applicationState
{
    __block NSInteger state = -1;
    void (^read)(void) = ^{
        UIApplication *application = UIApplication.sharedApplication;
        if(application) state = (NSInteger)application.applicationState;
    };
    if(NSThread.isMainThread) read();
    else dispatch_sync(dispatch_get_main_queue(), read);
    return state;
}

+ (BOOL)waitUntilActive:(NSTimeInterval)timeout
{
    NSTimeInterval started = NSProcessInfo.processInfo.systemUptime;
    NSInteger state = [self applicationState];
    while(state != UIApplicationStateActive &&
          NSProcessInfo.processInfo.systemUptime - started < timeout)
    {
        // Keep the main run loop turning so the scene can finish activating.
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        state = [self applicationState];
    }
    return state == UIApplicationStateActive;
}

@end
