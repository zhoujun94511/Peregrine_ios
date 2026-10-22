#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "stub.h"
#import "PGStubPerf.h"
#import "GCDWebServer.h"
#import "GCDWebServerDataResponse.h"
#import "GCDWebServerDataRequest.h"

static NSString * const PGStubKillProcess = @"kill_process";
static NSString * const PGStubGetTree = @"get_ui_tree";
static NSString * const PGStubAppInfo = @"app_info";
static NSString * const PGStubAppPerf = @"app_perf";
static NSString * const PGStubClassKey = @"PGStubClass";
static const NSUInteger PGStubCoverSiblingLimit = 64;

@interface PGStub()

@property(nonatomic, strong) GCDWebServer* webServer;
// Main thread only. Tree requests that arrive while a build is queued share its result.
@property(nonatomic, strong) NSMutableArray<NSArray *> *treeWaiters;

@end

@implementation PGStub

#pragma mark - Start

+(void) load{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        __block id observer = [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
            [PGStub listen];
            [[NSNotificationCenter defaultCenter] removeObserver:observer];
        }];
    });
}

static PGStub* sharedStub = nil;

+(void) listen
{
    NSString *port = [[NSProcessInfo processInfo] environment][@"stubPort"];
    if(port.integerValue <= 0)
    {
        return;
    }
    if([[[NSProcessInfo processInfo] environment][@"stubPerf"] isEqualToString:@"1"])
    {
        [[PGStubPerf shared] startWatch];
    }
    if(sharedStub == nil)
    {
        sharedStub = [[[self stubClass] alloc] init];
    }
    [sharedStub delayListenOnPort:port.integerValue];
}

// A subclass named by the PGStubClass environment variable or Info.plist key
// replaces PGStub, so its shouldExposeView: is the one that runs.
+(Class) stubClass
{
    NSString *name = [[NSProcessInfo processInfo] environment][PGStubClassKey];
    if(name.length == 0)
    {
        id value = [[NSBundle mainBundle] objectForInfoDictionaryKey:PGStubClassKey];
        name = [value isKindOfClass:[NSString class]] ? value : nil;
    }
    Class cls = name.length > 0 ? NSClassFromString(name) : nil;
    if(cls != nil && [cls isSubclassOfClass:[PGStub class]])
    {
        return cls;
    }
    if(name.length > 0)
    {
        NSLog(@"peregrine stub class %@ is not a PGStub subclass, using PGStub", name);
    }
    return [PGStub class];
}

-(instancetype)init
{
    self = [super init];
    if(self != nil)
    {
        _treeWaiters = [NSMutableArray array];
    }
    return self;
}

#pragma mark - JSON-RPC

// Behavior this process must keep:
//   kill_process: result is true, answered off the main thread. Do not exit.
//   app_info: result is {bundle_id, name, version} of the host app, answered off the main
//     thread. The runner uses it to reject a stub that belongs to another app.
//   app_perf: result is the PGStubPerf sample, answered off the main thread.
//   get_ui_tree: result is the elem_info tree, built on the main thread. Requests that
//     queue up while the main thread is busy are answered from one build.
//   anything else: JSON-RPC error -32601 and no tree walk.
- (NSDictionary *)rpcResponseWithResult:(id)result requestId:(id)requestId
{
    return @{
        @"jsonrpc": @"2.0",
        @"id": requestId ?: @0,
        @"result": result ?: @[]
    };
}

- (NSDictionary *)appInfo
{
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *name = [bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"] ?: [bundle objectForInfoDictionaryKey:@"CFBundleName"];
    return @{
        @"bundle_id": bundle.bundleIdentifier ?: @"",
        @"name": [name isKindOfClass:[NSString class]] ? name : @"",
        @"version": [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @""
    };
}

- (NSDictionary *)rpcErrorWithCode:(NSInteger)code message:(NSString *)message requestId:(id)requestId
{
    return @{
        @"jsonrpc": @"2.0",
        @"id": requestId ?: @0,
        @"error": @{@"code": @(code), @"message": message}
    };
}

#pragma mark - Element tree

- (BOOL)shouldExposeView:(UIView *)view
{
    return view != nil;
}

- (NSArray *)elementTree
{
    NSMutableArray *result = [[NSMutableArray alloc] init];
    CGRect screen = [UIScreen mainScreen].bounds;
    for(UIView *view in [self contentWindows])
    {
        NSDictionary *node = [self elementNodeForView:view clip:screen interactionAllowed:YES];
        if(node != nil)
        {
            [result addObject:node];
        }
    }
    return result;
}

// Hidden or transparent views take their subtree with them. A view that clips to
// its bounds limits what its subtree can show, so the subtree is dropped when that
// limit is empty. rect is reported clipped to what is on screen; clickable also
// needs every ancestor to accept touches.
- (NSDictionary *)elementNodeForView:(UIView *)view clip:(CGRect)clip interactionAllowed:(BOOL)interactionAllowed
{
    if(![self shouldExposeView:view] || view.hidden || view.alpha <= 0.01)
    {
        return nil;
    }
    CGRect frame = [self screenRectOfView:view];
    CGRect shown = CGRectIntersection(frame, clip);
    BOOL onScreen = !CGRectIsNull(shown) && shown.size.width >= 1 && shown.size.height >= 1;
    CGRect childClip = clip;
    if(view.clipsToBounds)
    {
        if(!onScreen)
        {
            return nil;
        }
        childClip = shown;
    }
    BOOL childInteraction = interactionAllowed && view.userInteractionEnabled;
    NSMutableDictionary *info = [self propertiesForView:view];
    info[@"rect"] = [self rectDictionary:onScreen ? shown : CGRectZero];
    info[@"visible"] = @(onScreen);
    if(!onScreen || !childInteraction)
    {
        info[@"clickable"] = @NO;
        info[@"interactive"] = @NO;
    }
    NSMutableArray *children = [[NSMutableArray alloc] init];
    NSArray<UIView *> *subviews = view.subviews;
    for(NSUInteger index = 0; index < subviews.count; index++)
    {
        UIView *subview = subviews[index];
        BOOL covered = [self view:subview isCoveredBySiblingsAfter:index in:subviews];
        NSDictionary *child = [self elementNodeForView:subview clip:childClip interactionAllowed:childInteraction && !covered];
        if(child != nil)
        {
            [children addObject:child];
        }
    }
    if(!onScreen && children.count == 0)
    {
        return nil;
    }
    return @{@"elem_info": info, @"children": children};
}

// A later sibling draws on top. When it, or a view up to two levels inside it,
// takes touches, is drawn, and fully covers this view on screen, taps aimed at
// this view's subtree land there instead, e.g. the dimming view of a page sheet,
// which sits inside the transition view that follows the presenting screen.
- (BOOL)view:(UIView *)view isCoveredBySiblingsAfter:(NSUInteger)index in:(NSArray<UIView *> *)siblings
{
    if(siblings.count > PGStubCoverSiblingLimit)
    {
        return NO;
    }
    CGRect target = [self screenRectOfView:view];
    if(target.size.width < 1 || target.size.height < 1)
    {
        return NO;
    }
    for(NSUInteger later = index + 1; later < siblings.count; later++)
    {
        if([self view:siblings[later] covers:target depth:2])
        {
            return YES;
        }
    }
    return NO;
}

- (BOOL)view:(UIView *)cover covers:(CGRect)target depth:(NSInteger)depth
{
    if(cover.hidden || cover.alpha <= 0.01 || !cover.userInteractionEnabled)
    {
        return NO;
    }
    BOOL drawn = [NSStringFromClass([cover class]) containsString:@"Dimming"];
    if(!drawn)
    {
        CGFloat red = 0, green = 0, blue = 0, alpha = 0;
        drawn = [cover.backgroundColor getRed:&red green:&green blue:&blue alpha:&alpha] && alpha > 0.01;
    }
    if(drawn && CGRectContainsRect([self screenRectOfView:cover], target))
    {
        return YES;
    }
    if(depth <= 0 || cover.subviews.count > PGStubCoverSiblingLimit)
    {
        return NO;
    }
    for(UIView *inner in cover.subviews)
    {
        if([self view:inner covers:target depth:depth - 1])
        {
            return YES;
        }
    }
    return NO;
}

- (NSMutableDictionary *)propertiesForView:(UIView *)view
{
    BOOL clickable = [self uiViewClickable:view];
    BOOL textEntry = [view isKindOfClass:[UITextField class]] || [view isKindOfClass:[UITextView class]];
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithDictionary:@{
        @"rect":        [self rectUIView:view],
        @"type":        NSStringFromClass([view class]),
        @"identifier":  [self nonullNSString:[view accessibilityIdentifier]],
        @"visible":     @([@(!view.hidden && view.alpha>0.01) boolValue]),
        @"interactive": @(clickable || textEntry),
        @"value":       [self nonullNSString:[view accessibilityValue]],
        @"label":       [self nonullNSString:[view accessibilityLabel]],
        @"scrollable":  @([self uiViewScrollable:view]),
        @"clickable":   @(clickable)
    }];
    NSString *controller = [self uiViewViewControllerStr:view];
    if(controller.length != 0)
    {
        info[@"controller"] = controller;
    }
    return info;
}

#pragma mark - View facts

- (NSArray<UIWindow *> *)applicationWindows
{
    UIApplication *app = [UIApplication sharedApplication];
    NSArray *windows = nil;
    if (@available(iOS 13.0, *)) {
        for(UIScene *scene in app.connectedScenes)
        {
            if([scene isKindOfClass:[UIWindowScene class]])
            {
                windows = ((UIWindowScene *)scene).windows;
                break;
            }
        }
    } else {
        windows = [app windows];
    }
    return windows ?: @[];
}

- (NSArray<UIWindow *> *)contentWindows
{
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    for(UIWindow *window in [self sortedWindows])
    {
        if([self windowCarriesAppContent:window])
        {
            [windows addObject:window];
        }
    }
    return windows;
}

- (BOOL)windowCarriesAppContent:(UIWindow *)window
{
    if(window.hidden || window.alpha <= 0.01)
    {
        return NO;
    }
    NSString *name = NSStringFromClass([window class]);
    if([name containsString:@"TextEffects"] || [name containsString:@"Keyboard"] || [name containsString:@"Cursor"])
    {
        return NO;
    }
    return YES;
}

- (NSArray<UIWindow *> *)sortedWindows
{
    return [[self applicationWindows] sortedArrayUsingComparator:^NSComparisonResult(UIWindow *w1, UIWindow *w2) {
        if([w1 windowLevel] == [w2 windowLevel])
        {
            if([w1 isKeyWindow]){
                return NSOrderedAscending;
            }
            if([w2 isKeyWindow]){
                return NSOrderedDescending;
            }
        }
        return [w1 windowLevel] < [w2 windowLevel] ? NSOrderedDescending : NSOrderedAscending;
    }];
}

- (CGRect)screenRectOfView:(UIView *)view
{
    return [view convertRect:view.bounds toCoordinateSpace:[UIScreen mainScreen].coordinateSpace];
}

- (NSDictionary *)rectUIView:(UIView *)view
{
    return [self rectDictionary:[self screenRectOfView:view]];
}

- (NSDictionary *)rectDictionary:(CGRect)rect
{
    return @{
        @"left": @(round(rect.origin.x)),
        @"top": @(round(rect.origin.y)),
        @"width": @(round(rect.size.width)),
        @"height": @(round(rect.size.height)),
    };
}

-(BOOL) uiViewScrollable:(UIView *)view
{
    if([view isKindOfClass:[UIScrollView class]])
    {
        return ((UIScrollView *)view).scrollEnabled;
    }
    return NO;
}

-(BOOL) uiViewClickable:(UIView *)view
{
    if(view.hidden || view.alpha <= 0.01)
    {
        return NO;
    }
    if([view isKindOfClass:[UIControl class]])
    {
        UIControl *control = (UIControl *)view;
        return control.enabled && control.userInteractionEnabled;
    }
    UIAccessibilityTraits traits = view.accessibilityTraits;
    if((traits & UIAccessibilityTraitButton) != 0 || (traits & UIAccessibilityTraitLink) != 0)
    {
        return YES;
    }
    if([view isKindOfClass:[UITableViewCell class]] || [view isKindOfClass:[UICollectionViewCell class]])
    {
        return view.userInteractionEnabled;
    }
    for(UIGestureRecognizer *recognizer in view.gestureRecognizers)
    {
        if([recognizer isKindOfClass:[UITapGestureRecognizer class]] && recognizer.enabled)
        {
            return YES;
        }
    }
    return NO;
}

-(NSString *) uiViewViewControllerStr:(UIView *)view
{
    id viewController = [self uiViewViewController:view];
    return viewController ? NSStringFromClass([viewController class]) : @"";
}

-(id) uiViewViewController:(UIView *)view
{
    id responder = [view nextResponder];
    if ([responder isKindOfClass:[UIViewController class]] &&
        ((UIViewController *)responder).view.window &&
        ((UIViewController *)responder).isViewLoaded) {
        return responder;
    }
    return nil;
}

-(NSString *) nonullNSString:(nullable NSString *)str
{
    return str ? str : @"";
}

#pragma mark - HTTP

- (void)queueTreeReply:(GCDWebServerCompletionBlock)completionBlock requestId:(id)requestId
{
    [self.treeWaiters addObject:@[[completionBlock copy], requestId ?: @0]];
    if(self.treeWaiters.count > 1)
    {
        return;
    }
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf answerTreeWaiters];
    });
}

- (void)answerTreeWaiters
{
    NSArray<NSArray *> *waiters = [self.treeWaiters copy];
    [self.treeWaiters removeAllObjects];
    NSArray *tree = nil;
    @try {
        tree = [self elementTree];
    }
    @catch(NSException *exception)
    {
        NSLog(@"peregrine stub tree failed: %@", exception.reason);
        tree = @[];
    }
    NSMutableArray<NSDictionary *> *payloads = [NSMutableArray arrayWithCapacity:waiters.count];
    for(NSArray *waiter in waiters)
    {
        [payloads addObject:[self rpcResponseWithResult:tree requestId:waiter[1]]];
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        for(NSUInteger index = 0; index < waiters.count; index++)
        {
            GCDWebServerCompletionBlock completion = waiters[index][0];
            completion([GCDWebServerDataResponse responseWithJSONObject:payloads[index]]);
        }
    });
}

-(void) delayListenOnPort:(NSInteger)port
{
    if(self.webServer == nil)
    {
        _webServer = [[GCDWebServer alloc] init];
    }
    if(self.webServer.isRunning)
    {
        [self.webServer stop];
    }
    [GCDWebServer setLogLevel:3];
    __weak typeof(self) weakSelf = self;
    GCDWebServerAsyncProcessBlock process = ^(__kindof GCDWebServerRequest * _Nonnull request, GCDWebServerCompletionBlock _Nonnull completionBlock) {
        // GCDWebServer's jsonObject aborts in Debug builds when Content-Type is not JSON.
        NSData *body = ((GCDWebServerDataRequest *)request).data;
        id json = body.length > 0 ? [NSJSONSerialization JSONObjectWithData:body options:0 error:nil] : nil;
        NSDictionary *data = [json isKindOfClass:[NSDictionary class]] ? json : @{};
        NSString *method = [data[@"method"] isKindOfClass:[NSString class]] ? data[@"method"] : @"";
        id requestId = data[@"id"];
        if([method isEqualToString:PGStubKillProcess])
        {
            completionBlock([GCDWebServerDataResponse responseWithJSONObject:[weakSelf rpcResponseWithResult:@YES requestId:requestId]]);
            return;
        }
        if([method isEqualToString:PGStubAppInfo])
        {
            completionBlock([GCDWebServerDataResponse responseWithJSONObject:[weakSelf rpcResponseWithResult:[weakSelf appInfo] requestId:requestId]]);
            return;
        }
        if([method isEqualToString:PGStubAppPerf])
        {
            completionBlock([GCDWebServerDataResponse responseWithJSONObject:[weakSelf rpcResponseWithResult:[[PGStubPerf shared] sample] requestId:requestId]]);
            return;
        }
        if(![method isEqualToString:PGStubGetTree])
        {
            NSDictionary *error = [weakSelf rpcErrorWithCode:-32601 message:@"method not found" requestId:requestId];
            completionBlock([GCDWebServerDataResponse responseWithJSONObject:error]);
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf queueTreeReply:completionBlock requestId:requestId];
        });
    };
    [self.webServer addHandlerForMethod:@"POST" path:@"/" requestClass:[GCDWebServerDataRequest class] asyncProcessBlock:process];
    [self.webServer addHandlerForMethod:@"POST" path:@"/view" requestClass:[GCDWebServerDataRequest class] asyncProcessBlock:process];

    dispatch_time_t delayTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC));
    // GCDWebServer expects its control calls on the main thread.
    dispatch_after(delayTime, dispatch_get_main_queue(), ^(void){
        NSDictionary *options = @{
            GCDWebServerOption_Port: @(port),
            GCDWebServerOption_BindToLocalhost: @YES,
            GCDWebServerOption_AutomaticallySuspendInBackground: @NO
        };
        NSError *err = nil;
        if([weakSelf.webServer startWithOptions:options error:&err])
        {
            NSLog(@"start peregrine stub listen success on 127.0.0.1:%ld", (long)port);
        }
        else
        {
            NSLog(@"start peregrine stub listen failed: %@", err);
        }
    });
}

@end
