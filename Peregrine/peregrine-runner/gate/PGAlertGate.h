#import <XCTest/XCTest.h>

NS_ASSUME_NONNULL_BEGIN

// Dismisses prompts that block the app under test.
// Every step checks SpringBoard alerts, then the app's alerts and sheets.
// A prompt does not need to have appeared in a previous run to be covered.
// More than two buttons taps the second. Otherwise taps the last.
// A passcode pad, a sign-in form, a payment button, or a software-update install button is closed instead of confirmed.
// A chosen button that deletes, removes, signs out, clears or resets is swapped for a dismiss
// or any other button, so exploration keeps its login and data.
// Buttons are tapped at their centre through a coordinate, not through XCUIElement tap.
@interface PGAlertGate : NSObject
+ (void)installSystemMonitorOn:(XCTestCase *)testCase;
+ (BOOL)dismissBlockingAlertsInApplication:(XCUIApplication *)application;
+ (BOOL)dismissInApplication:(XCUIApplication *)application;
@end

NS_ASSUME_NONNULL_END
