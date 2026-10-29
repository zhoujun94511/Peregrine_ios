#import "PGAlertGate.h"
#import "PGOverlayRules.h"

// SpringBoard is the only system process queried every step.
// Walking the rest of the system UI catalog stalled exploration for minutes.

static NSArray<NSString *> *PGDismissLabels(void)
{
    return @[
        @"Cancel", @"Not Now", @"Close", @"Later", @"Dismiss", @"Remind Me Later", @"No Thanks",
        @"Don't Allow", @"Don’t Allow",
        @"取消", @"以后", @"关闭", @"稍后", @"不允许",
        @"稍后提醒我", @"稍后提醒", @"以后再说", @"暂不", @"忽略", @"Remind Me Tomorrow",
        @"Cancelar", @"Ahora no", @"Cerrar", @"Más tarde", @"No gracias",
        @"Agora não", @"Fechar", @"Mais tarde",
        @"Annuler", @"Plus tard", @"Fermer", @"Non merci",
        @"Abbrechen", @"Nicht jetzt", @"Schließen", @"Später",
        @"キャンセル", @"後で", @"閉じる",
        @"취소", @"나중에", @"닫기",
        @"Annulla", @"Non ora", @"Chiudi", @"Più tardi",
        @"Отмена", @"Не сейчас", @"Закрыть", @"Позже",
        @"إلغاء", @"ليس الآن", @"إغلاق",
        @"Batal", @"Nanti", @"Tutup",
        @"İptal", @"Şimdi değil", @"Kapat",
        @"Hủy", @"Để sau", @"Đóng",
        @"ยกเลิก", @"ภายหลัง", @"ปิด",
        @"रद्द करें", @"अभी नहीं", @"बंद", @"बंद करें"
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
    if(container == nil)
    {
        return NO;
    }
    // A vanished alert records an XCTest failure when its buttons are queried. One snapshot either
    // yields the buttons or says the alert is already gone, and @catch cannot clear that failure.
    NSError *error = nil;
    id<XCUIElementSnapshot> shot = [container snapshotWithError:&error];
    if(shot == nil || shot.frame.size.width <= 0 || shot.frame.size.height <= 0)
    {
        return NO;
    }
    NSMutableArray<id<XCUIElementSnapshot>> *buttons = [NSMutableArray array];
    [self collectFrom:shot into:buttons type:XCUIElementTypeButton];
    id<XCUIElementSnapshot> button = [self buttonToTap:buttons inContainer:shot];
    CGRect frame = button == nil ? CGRectZero : button.frame;
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

+ (void)collectFrom:(id<XCUIElementSnapshot>)node into:(NSMutableArray<id<XCUIElementSnapshot>> *)found type:(XCUIElementType)type
{
    if(node.elementType == type)
    {
        [found addObject:node];
    }
    for(id<XCUIElementSnapshot> child in node.children)
    {
        [self collectFrom:child into:found type:type];
    }
}

+ (id<XCUIElementSnapshot>)buttonToTap:(NSArray<id<XCUIElementSnapshot>> *)buttons inContainer:(id<XCUIElementSnapshot>)container
{
    if(buttons.count == 0)
    {
        return nil;
    }
    if([self buttonsLookLikePasscode:buttons] || [self containerAcceptsText:container] || [self containerOffersInstall:buttons text:container])
    {
        return [self firstButtonIn:buttons labels:PGDismissLabels()];
    }
    for(id<XCUIElementSnapshot> button in buttons)
    {
        if([PGOverlayRules textIsPurchase:button.label] || [PGOverlayRules textIsInstall:button.label])
        {
            return [self firstButtonIn:buttons labels:PGDismissLabels()];
        }
    }
    if(buttons.count <= 2)
    {
        id<XCUIElementSnapshot> dismiss = [self firstButtonIn:buttons labels:PGDismissLabels()];
        if(dismiss != nil)
        {
            return dismiss;
        }
    }
    id<XCUIElementSnapshot> chosen = buttons.count > 2 ? buttons[1] : buttons.lastObject;
    if([PGOverlayRules textIsDestructive:chosen.label])
    {
        id<XCUIElementSnapshot> dismiss = [self firstButtonIn:buttons labels:PGDismissLabels()];
        if(dismiss != nil)
        {
            return dismiss;
        }
        for(id<XCUIElementSnapshot> button in buttons)
        {
            if(![PGOverlayRules textIsDestructive:button.label])
            {
                return button;
            }
        }
    }
    return chosen;
}

+ (BOOL)containerOffersInstall:(NSArray<id<XCUIElementSnapshot>> *)buttons text:(id<XCUIElementSnapshot>)container
{
    for(id<XCUIElementSnapshot> button in buttons)
    {
        if([PGOverlayRules textIsInstall:button.label])
        {
            return YES;
        }
    }
    NSMutableArray<id<XCUIElementSnapshot>> *texts = [NSMutableArray array];
    [self collectFrom:container into:texts type:XCUIElementTypeStaticText];
    for(id<XCUIElementSnapshot> text in texts)
    {
        if([PGOverlayRules textIsInstall:text.label])
        {
            return YES;
        }
    }
    return NO;
}

+ (BOOL)buttonsLookLikePasscode:(NSArray<id<XCUIElementSnapshot>> *)buttons
{
    for(id<XCUIElementSnapshot> button in buttons)
    {
        NSString *label = [button.label stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if(label.length == 1 && [label rangeOfCharacterFromSet:[NSCharacterSet decimalDigitCharacterSet]].location != NSNotFound)
        {
            return YES;
        }
    }
    return NO;
}

+ (BOOL)containerAcceptsText:(id<XCUIElementSnapshot>)container
{
    NSMutableArray<id<XCUIElementSnapshot>> *fields = [NSMutableArray array];
    [self collectFrom:container into:fields type:XCUIElementTypeTextField];
    if(fields.count > 0)
    {
        return YES;
    }
    [self collectFrom:container into:fields type:XCUIElementTypeSecureTextField];
    return fields.count > 0;
}

+ (id<XCUIElementSnapshot>)firstButtonIn:(NSArray<id<XCUIElementSnapshot>> *)buttons labels:(NSArray<NSString *> *)labels
{
    for(id<XCUIElementSnapshot> button in buttons)
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
