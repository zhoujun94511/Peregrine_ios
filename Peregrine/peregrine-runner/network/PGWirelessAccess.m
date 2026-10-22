#import "PGWirelessAccess.h"
#import <XCTest/XCTest.h>

@implementation PGWirelessAccess

+ (BOOL)activateCurrentRunner
{
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
    if(bundleID.length == 0) return NO;
    XCUIApplication *runner = [[XCUIApplication alloc] initWithBundleIdentifier:bundleID];
    // activate preserves the currently executing XCTest process; never launch it.
    [runner activate];
    return runner.state == XCUIApplicationStateRunningForeground;
}

+ (void)leaveForWirelessPrompt
{
    // After the runner is in front, return home so the system can show the wireless-data dialog.
    NSLog(@"wireless prompt home pressed");
    [XCUIDevice.sharedDevice pressButton:XCUIDeviceButtonHome];
}

+ (BOOL)allowCurrentRunnerNetworkPrompt
{
    XCUIApplication *board = [[XCUIApplication alloc] initWithBundleIdentifier:@"com.apple.springboard"];
    XCUIElement *alert = board.alerts.firstMatch;
    if(!alert.exists) alert = board.sheets.firstMatch;
    if(!alert.exists) return NO;
    // The China wireless-data dialog's allow buttons are specific. Do not tap a generic Allow on an unrelated alert.
    for(NSString *label in @[
        @"无线局域网与蜂窝数据",
        @"无线局域网与蜂窝网络",
        @"WLAN & Cellular Data",
        @"WLAN & Cellular",
        @"Wi-Fi & Cellular Data",
        @"Wi-Fi & Cellular",
        @"无线局域网",
        @"WLAN",
        @"Wi-Fi"
    ])
    {
        XCUIElement *button = alert.buttons[label];
        if(button.exists && button.hittable)
        {
            NSLog(@"wireless prompt allow success %@", label);
            [button tap];
            return YES;
        }
    }
    return NO;
}

@end
