#import "PGAlertGate.h"

// SpringBoard is the only system process queried every step.
// Walking the rest of the system UI catalog stalled exploration for minutes.

static NSArray<NSString *> *PGDismissLabels(void)
{
    return @[
        @"Cancel", @"Not Now", @"Close", @"Later", @"Dismiss", @"Remind Me Later", @"No Thanks",
        @"Don't Allow", @"Don’t Allow",
        @"取消", @"以后", @"关闭", @"稍后", @"不允许",
        @"稍后提醒我", @"稍后提醒", @"以后再说", @"暂不", @"忽略", @"Remind Me Tomorrow"
    ];
}

static NSArray<NSString *> *PGInstallLabels(void)
{
    return @[
        @"Install", @"Install Now", @"Install Tonight", @"Download and Install",
        @"Update", @"Update Now", @"Update Tonight", @"Upgrade", @"Restart Now",
        @"安装", @"现在安装", @"立即安装", @"今晚安装",
        @"更新", @"现在更新", @"立即更新", @"升级", @"立即重新启动"
    ];
}

static NSArray<NSString *> *PGPaymentLabels(void)
{
    return @[
        @"Buy", @"Subscribe", @"Purchase", @"Pay",
        @"购买", @"订阅", @"付款", @"支付"
    ];
}

static NSArray<NSString *> *PGDestructiveWords(void)
{
    return @[
        @"Delete", @"Remove", @"Erase", @"Log Out", @"Logout", @"Sign Out", @"Reset", @"Clear",
        @"删除", @"移除", @"抹掉", @"退出登录", @"登出", @"注销", @"清空", @"清除", @"重置"
    ];
}

@implementation PGAlertGate

+ (void)installSystemMonitorOn:(XCTestCase *)testCase
{
    [testCase addUIInterruptionMonitorWithDescription:@"system-alert" handler:^BOOL(XCUIElement *alert) {
        @try {
            return [self tapPrompt:alert kind:@"system-monitor" origin:[self springboard]];
        } @catch (NSException *exception) {
            NSLog(@"alert gate skipped %@", exception.reason ?: exception.name);
            return NO;
        }
    }];
}

+ (BOOL)dismissBlockingAlertsInApplication:(XCUIApplication *)application
{
    @try {
        if([self dismissSystemAlerts])
        {
            return YES;
        }
        return [self dismissInApplication:application];
    } @catch (NSException *exception) {
        NSLog(@"alert gate skipped %@", exception.reason ?: exception.name);
        return NO;
    }
}

+ (XCUIApplication *)springboard
{
    return [[XCUIApplication alloc] initWithBundleIdentifier:@"com.apple.springboard"];
}

+ (BOOL)dismissSystemAlerts
{
    XCUIApplication *board = [self springboard];
    return [self dismissContainers:board.alerts kind:@"springboard-alert" origin:board];
}

+ (BOOL)dismissInApplication:(XCUIApplication *)application
{
    // Querying an app that has exited records an XCTest failure, which a @catch cannot stop.
    if(application == nil || application.state != XCUIApplicationStateRunningForeground)
    {
        return NO;
    }
    NSPredicate *prompt = [NSPredicate predicateWithFormat:@"elementType == %lu OR elementType == %lu", (unsigned long)XCUIElementTypeAlert, (unsigned long)XCUIElementTypeSheet];
    return [self dismissContainers:[[application descendantsMatchingType:XCUIElementTypeAny] matchingPredicate:prompt] kind:@"app-prompt" origin:application];
}

+ (BOOL)dismissContainers:(XCUIElementQuery *)containers kind:(NSString *)kind origin:(XCUIApplication *)origin
{
    NSUInteger count = 0;
    @try {
        count = containers.count;
    } @catch (NSException *exception) {
        NSLog(@"alert gate skipped %@", exception.reason ?: exception.name);
        return NO;
    }
    if(count == 0)
    {
        return NO;
    }
    for(XCUIElement *container in containers.allElementsBoundByIndex)
    {
        if([self tapPrompt:container kind:kind origin:origin])
        {
            return YES;
        }
    }
    return NO;
}

+ (BOOL)tapPrompt:(XCUIElement *)container kind:(NSString *)kind origin:(XCUIApplication *)origin
{
    if(container == nil || ![container exists])
    {
        return NO;
    }
    NSArray<XCUIElement *> *buttons = container.buttons.allElementsBoundByIndex;
    XCUIElement *button = [self buttonToTap:buttons inContainer:container];
    CGRect frame = button.exists ? button.frame : CGRectZero;
    if(button == nil || CGRectIsEmpty(frame))
    {
        return NO;
    }
    NSLog(@"dismiss %@ button %@", kind, button.label ?: @"");
    // XCUIElement tap waits for the app's animations to finish, up to a minute.
    XCUICoordinate *top = [origin coordinateWithNormalizedOffset:CGVectorMake(0, 0)];
    [[top coordinateWithOffset:CGVectorMake(CGRectGetMidX(frame), CGRectGetMidY(frame))] tap];
    return YES;
}

+ (XCUIElement *)buttonToTap:(NSArray<XCUIElement *> *)buttons inContainer:(XCUIElement *)container
{
    if(buttons.count == 0)
    {
        return nil;
    }
    if([self buttonsLookLikePasscode:buttons] || [self containerAcceptsText:container] || [self containerOffersInstall:buttons text:container])
    {
        return [self firstButtonIn:buttons labels:PGDismissLabels()];
    }
    XCUIElement *chosen = buttons.count > 2 ? buttons[1] : buttons.lastObject;
    if([self label:chosen.label isOneOf:PGPaymentLabels()] || [self label:chosen.label isOneOf:PGInstallLabels()])
    {
        return [self firstButtonIn:buttons labels:PGDismissLabels()];
    }
    if([self labelIsDestructive:chosen.label])
    {
        XCUIElement *dismiss = [self firstButtonIn:buttons labels:PGDismissLabels()];
        if(dismiss != nil)
        {
            return dismiss;
        }
        for(XCUIElement *button in buttons)
        {
            if(![self labelIsDestructive:button.label])
            {
                return button;
            }
        }
    }
    return chosen;
}

+ (BOOL)labelIsDestructive:(NSString *)label
{
    for(NSString *word in PGDestructiveWords())
    {
        if(label.length > 0 && [label rangeOfString:word options:NSCaseInsensitiveSearch].location != NSNotFound)
        {
            return YES;
        }
    }
    return NO;
}

+ (BOOL)containerOffersInstall:(NSArray<XCUIElement *> *)buttons text:(XCUIElement *)container
{
    for(XCUIElement *button in buttons)
    {
        if([self label:button.label isOneOf:PGInstallLabels()])
        {
            return YES;
        }
    }
    NSArray<NSString *> *phrases = @[
        @"Software Update", @"iOS Update", @"Update Available",
        @"软件更新", @"系统更新", @"系统升级", @"iOS 更新"
    ];
    for(XCUIElement *text in container.staticTexts.allElementsBoundByIndex)
    {
        NSString *label = text.label ?: @"";
        for(NSString *phrase in phrases)
        {
            if([label rangeOfString:phrase options:NSCaseInsensitiveSearch].location != NSNotFound)
            {
                return YES;
            }
        }
    }
    return NO;
}

+ (BOOL)buttonsLookLikePasscode:(NSArray<XCUIElement *> *)buttons
{
    for(XCUIElement *button in buttons)
    {
        NSString *label = [button.label stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if(label.length == 1 && [label rangeOfCharacterFromSet:[NSCharacterSet decimalDigitCharacterSet]].location != NSNotFound)
        {
            return YES;
        }
    }
    return NO;
}

+ (BOOL)containerAcceptsText:(XCUIElement *)container
{
    return [container.textFields.firstMatch waitForExistenceWithTimeout:0]
        || [container.secureTextFields.firstMatch waitForExistenceWithTimeout:0];
}

+ (XCUIElement *)firstButtonIn:(NSArray<XCUIElement *> *)buttons labels:(NSArray<NSString *> *)labels
{
    for(XCUIElement *button in buttons)
    {
        if([self label:button.label isOneOf:labels])
        {
            return button;
        }
    }
    return nil;
}

+ (BOOL)label:(NSString *)label isOneOf:(NSArray<NSString *> *)words
{
    NSString *trimmed = [label stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
    for(NSString *word in words)
    {
        if([trimmed caseInsensitiveCompare:word] == NSOrderedSame)
        {
            return YES;
        }
    }
    return NO;
}

@end
