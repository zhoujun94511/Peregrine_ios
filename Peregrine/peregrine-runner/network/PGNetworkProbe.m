//
//  PGNetworkProbe.m
//  peregrine-runner
//

#import "PGNetworkProbe.h"
#import "PGForegroundState.h"
#import "PGWirelessAccess.h"
#import <Network/Network.h>

static NSString *const PGPingURL = @"https://www.taobao.com/";

@implementation PGNetworkProbe

+ (int)deniedReasonForMonitor:(nw_path_monitor_t)monitor
{
    if(@available(iOS 14.2, *))
    {
        // Take only the first snapshot; later callbacks must not race the caller.
        NSObject *lock = [[NSObject alloc] init];
        __block int reason = -1;
        __block BOOL received = NO;
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        nw_path_monitor_set_queue(monitor, dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0));
        nw_path_monitor_set_update_handler(monitor, ^(nw_path_t path) {
            @synchronized(lock) {
                if(received) return;
                received = YES;
                reason = nw_path_get_status(path) == nw_path_status_unsatisfied ?
                    (int)nw_path_get_unsatisfied_reason(path) : -1;
            }
            dispatch_semaphore_signal(semaphore);
        });
        nw_path_monitor_start(monitor);
        long wait = dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC));
        nw_path_monitor_cancel(monitor);
        @synchronized(lock) {
            return wait == 0 ? reason : -1;
        }
    }
    return -1;
}

+ (BOOL)pathDenied
{
    if(@available(iOS 14.2, *))
    {
        int reason = [self deniedReasonForMonitor:nw_path_monitor_create()];
        int wifiReason = [self deniedReasonForMonitor:nw_path_monitor_create_with_type(nw_interface_type_wifi)];
        return reason == nw_path_unsatisfied_reason_wifi_denied ||
               reason == nw_path_unsatisfied_reason_cellular_denied ||
               wifiReason == nw_path_unsatisfied_reason_wifi_denied;
    }
    return NO;
}

+ (BOOL)requestPing:(NSString *_Nullable *_Nullable)failure
{
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    configuration.allowsCellularAccess = YES;
    if(@available(iOS 13.0, *))
    {
        configuration.allowsExpensiveNetworkAccess = YES;
        configuration.allowsConstrainedNetworkAccess = YES;
    }
    // Fail promptly on a denied path. Recovery below has a bounded retry budget.
    configuration.timeoutIntervalForRequest = 12;
    configuration.timeoutIntervalForResource = 15;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
    NSObject *lock = [[NSObject alloc] init];
    __block BOOL completed = NO;
    __block BOOL success = NO;
    __block NSError *requestError = nil;
    __block NSInteger statusCode = 0;
    NSURL *url = [NSURL URLWithString:PGPingURL];
    NSURLSessionDataTask *task = [session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        @synchronized(lock) {
            if(completed) return; // Ignore cancellation after the caller's deadline.
            statusCode = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
            success = error == nil && statusCode > 0 && statusCode < 500;
            requestError = error;
            completed = YES;
        }
    }];
    [task resume];
    NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + 15;
    NSTimeInterval nextPromptCheck = 0;
    while(NSProcessInfo.processInfo.systemUptime < deadline)
    {
        @synchronized(lock) { if(completed) break; }
        if(NSProcessInfo.processInfo.systemUptime >= nextPromptCheck)
        {
            [PGWirelessAccess allowCurrentRunnerNetworkPrompt];
            nextPromptCheck = NSProcessInfo.processInfo.systemUptime + 1;
        }
        // Keep the runner's main run loop alive for authorization UI and callbacks.
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    BOOL result;
    @synchronized(lock) {
        if(!completed)
        {
            requestError = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil];
            completed = YES;
        }
        result = success;
        if(!result && failure != NULL)
        {
            *failure = [NSString stringWithFormat:@"HTTP %ld %@", (long)statusCode, requestError.localizedDescription ?: @""];
        }
    }
    [session invalidateAndCancel];
    return result;
}

+ (BOOL)probeNetwork
{
    [PGForegroundState waitUntilActive:0];
    // Keep the runner in front and wait for the system wireless-data dialog. Opening Settings covers that dialog.
    [PGWirelessAccess activateCurrentRunner];
    // No network use before this point. CommCenter judges the first connect, and it logs
    // "BundleID is not in foreground" when that connect happens before the runner is Active.
    [PGForegroundState waitUntilActive:5];
    NSTimeInterval started = NSProcessInfo.processInfo.systemUptime;
    NSTimeInterval deadline = started + 75;
    BOOL leftForeground = NO;
    NSString *failure = nil;
    while(NSProcessInfo.processInfo.systemUptime < deadline)
    {
        if([PGWirelessAccess allowCurrentRunnerNetworkPrompt])
        {
            [PGWirelessAccess activateCurrentRunner];
        }
        else if(!leftForeground && NSProcessInfo.processInfo.systemUptime - started > 20)
        {
            [PGWirelessAccess leaveForWirelessPrompt];
            leftForeground = YES;
        }
        if([self requestPing:&failure]) return YES;
        [NSThread sleepForTimeInterval:1];
    }
    NSLog(@"ping network failed %@", failure ?: @"");
    return NO;
}

@end
