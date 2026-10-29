#import "PGOperatePlayer.h"
#import "PGAppletSession.h"
#import "PGCommandPlayer.h"
#import "PGElementQuery.h"
#import "PGSnapshotTree.h"

static BOOL PGFramesAgree(CGRect elementFrame, PGElementRect operateRect)
{
    if(elementFrame.size.width <= 0 || elementFrame.size.height <= 0 || operateRect.width <= 0 || operateRect.height <= 0)
    {
        return NO;
    }
    CGRect operateFrame = CGRectMake(operateRect.left, operateRect.top, operateRect.width, operateRect.height);
    CGRect overlap = CGRectIntersection(elementFrame, operateFrame);
    if(CGRectIsNull(overlap) || CGRectIsEmpty(overlap))
    {
        return NO;
    }
    CGFloat overlapArea = overlap.size.width * overlap.size.height;
    CGFloat smaller = MIN(operateFrame.size.width * operateFrame.size.height, elementFrame.size.width * elementFrame.size.height);
    return smaller > 0 && overlapArea / smaller >= 0.5;
}

static NSString * PGPlayerAppStateName(XCUIApplicationState state)
{
    switch(state)
    {
        case XCUIApplicationStateNotRunning: return @"not_running";
        case XCUIApplicationStateRunningBackgroundSuspended: return @"background_suspended";
        case XCUIApplicationStateRunningBackground: return @"background";
        case XCUIApplicationStateRunningForeground: return @"running";
        default: return @"unknown";
    }
}

static NSString * PGPlayerTarget(PGOperate *operate)
{
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if(operate.queryIdentifier.length > 0)
    {
        [parts addObject:[NSString stringWithFormat:@"id=%@", operate.queryIdentifier]];
    }
    NSString *text = operate.queryText.length > 0 ? operate.queryText : operate.text;
    if(text.length > 0)
    {
        [parts addObject:[NSString stringWithFormat:@"\"%@\"", text.length > 40 ? [text substringToIndex:40] : text]];
    }
    if(operate.name.length > 0)
    {
        [parts addObject:operate.name];
    }
    PGElementRect rect = operate.rect;
    if(rect.width > 0 && rect.height > 0)
    {
        [parts addObject:[NSString stringWithFormat:@"(%ld,%ld %ldx%ld)", (long)rect.left, (long)rect.top, (long)rect.width, (long)rect.height]];
    }
    return [parts componentsJoinedByString:@" "];
}

static NSString *PGOperateResultName(PGOperateResult result)
{
    switch(result)
    {
        case PGOperateResultSuccess: return @"success";
        case PGOperateResultTargetNotFound: return @"target_not_found";
        case PGOperateResultExecutionFailed: return @"execution_failed";
        case PGOperateResultSkipped: return @"skipped";
    }
    return @"execution_failed";
}

@implementation PGOperatePlayer

+ (BOOL)openURL:(NSURL *)url application:(XCUIApplication *)application
{
    if(url.scheme.length == 0)
    {
        return NO;
    }
    if(@available(iOS 16.4, *))
    {
        [application openURL:url];
        return YES;
    }
    return NO;
}

+ (PGOperateResult)traceOperate:(PGOperate *)operate
               nodes:(NSArray<PGElementNode *> *)nodes
               inApp:(XCUIApplication *)application
               cases:(PGCaseSchedule *)cases
                 log:(PGEventLog *)log
       timeoutMillis:(NSInteger)timeoutMillis
     resolveElement:(BOOL)resolveElement
              screen:(CGSize)screen
{
    NSString *act = operate.act ?: @"";
    [log recordEventType:@"action_start" fields:@{
        @"action": @{@"type": act, @"target": PGPlayerTarget(operate)},
        @"app_state": PGPlayerAppStateName(application.state)
    }];
    NSDate *started = [NSDate date];
    PGOperateResult operateResult = [self performOperate:operate nodes:nodes inApp:application resolveElement:resolveElement screen:screen];
    NSInteger durationMillis = (NSInteger)([[NSDate date] timeIntervalSinceDate:started] * 1000.0);
    BOOL intentional = [act caseInsensitiveCompare:@"RESTART"] == NSOrderedSame;
    NSString *result = intentional && operateResult == PGOperateResultSuccess ? @"intentional" : PGOperateResultName(operateResult);
    if(operateResult == PGOperateResultSuccess && application.state != XCUIApplicationStateRunningForeground)
    {
        result = intentional ? @"intentional_not_foreground" : @"app_not_foreground";
    }
    NSDictionary *fields = @{
        @"action": @{@"type": act, @"duration_ms": @(durationMillis)},
        @"app_state": PGPlayerAppStateName(application.state),
        @"result": result
    };
    [log recordEventType:@"action_end" fields:fields];
    if(timeoutMillis > 0 && durationMillis > timeoutMillis)
    {
        [log recordEventType:@"action_timeout" fields:fields];
    }
    if(operateResult != PGOperateResultSuccess && operateResult != PGOperateResultSkipped)
    {
        [cases noteStepFailed];
    }
    return operateResult;
}

// Screenshot blocks carry no id or text, so CLICK_ID / CLICK_TEXT look the control up in a snapshot.
+ (NSArray<PGElementNode *> *)snapshotNodesInApplication:(XCUIApplication *)application
{
    BOOL outside = NO;
    NSArray<PGElementNode *> *nodes = nil;
    @try
    {
        nodes = [PGSnapshotTree nodesFromApplication:application pageName:nil outsideApp:&outside];
    }
    @catch(NSException *exception)
    {
        NSLog(@"query snapshot failed %@", exception.reason ?: exception.name);
        return @[];
    }
    return outside ? @[] : (nodes ?: @[]);
}

+ (BOOL)typeText:(NSString *)text inApplication:(XCUIApplication *)application
{
    if(text.length == 0 || !application.keyboards.firstMatch.exists)
    {
        return NO;
    }
    [application typeText:text];
    return YES;
}

+ (PGOperateResult)performOperate:(PGOperate *)operate nodes:(NSArray<PGElementNode *> *)nodes inApp:(XCUIApplication *)application resolveElement:(BOOL)resolveElement screen:(CGSize)screen
{
    @try
    {
        return [self performOperateBody:operate nodes:nodes inApp:application resolveElement:resolveElement screen:screen];
    }
    @catch(NSException *exception)
    {
        NSLog(@"operate %@ failed: %@", operate.act, exception.reason);
        return PGOperateResultExecutionFailed;
    }
}

+ (PGOperateResult)performOperateBody:(PGOperate *)operate nodes:(NSArray<PGElementNode *> *)nodes inApp:(XCUIApplication *)application resolveElement:(BOOL)resolveElement screen:(CGSize)screen
{
    if([operate.act caseInsensitiveCompare:@"SCHEMA"] == NSOrderedSame)
    {
        NSString *schema = operate.name.length > 0 ? operate.name : operate.text;
        return [self openURL:[PGAppletSession openableURLFromSchema:schema] application:application] ? PGOperateResultSuccess : PGOperateResultExecutionFailed;
    }
    NSString *act = operate.act.uppercaseString ?: @"";
    BOOL pointAction = [act isEqualToString:@"CLICK"] || [act isEqualToString:@"LONG_PRESS"] || [act isEqualToString:@"TYPE"] || [act isEqualToString:@"DOUBLE_TAP"];
    PGElementNode *matched = resolveElement && pointAction ? [PGElementQuery nodeForOperate:operate inNodes:nodes] : nil;
    CGRect frame = CGRectZero;
    XCUIElement *element = matched != nil ? [PGElementQuery elementMatchingNode:matched inApplication:application frame:&frame] : nil;
    if(element != nil)
    {
        @try
        {
            // The frame already came from a snapshot. Asking XCUIElement whether the
            // button is hittable records a test failure when the activation point is
            // invalid, and @try cannot clear that failure. Tap the snapshot center.
            if(PGFramesAgree(frame, operate.rect))
            {
                XCUICoordinate *origin = [application coordinateWithNormalizedOffset:CGVectorMake(0, 0)];
                XCUICoordinate *center = [origin coordinateWithOffset:CGVectorMake(CGRectGetMidX(frame), CGRectGetMidY(frame))];
                if([act isEqualToString:@"TYPE"])
                {
                    [center tap];
                    NSString *text = operate.text.length > 0 ? operate.text : @"peregrine";
                    if(![self typeText:text inApplication:application])
                    {
                        return PGOperateResultExecutionFailed;
                    }
                }
                else if([act isEqualToString:@"LONG_PRESS"])
                {
                    NSTimeInterval duration = operate.waitTime > 0 ? operate.waitTime / 1000.0 : 1.0;
                    [center pressForDuration:duration];
                }
                else if([act isEqualToString:@"DOUBLE_TAP"])
                {
                    [center doubleTap];
                }
                else
                {
                    [center tap];
                }
                NSLog(@"element %@ %@", act, matched.identifier.length > 0 ? matched.identifier : (matched.label ?: @""));
                return PGOperateResultSuccess;
            }
        }
        @catch(NSException *exception)
        {
            NSLog(@"element %@ failed, use coordinate: %@", act, exception.reason);
        }
    }
    NSArray<PGElementNode *> *queryNodes = nodes;
    if(!resolveElement && (operate.queryIdentifier.length > 0 || operate.queryText.length > 0))
    {
        queryNodes = [self snapshotNodesInApplication:application];
    }
    PGGesture *gesture = [PGCommandPlayer gestureForOperate:operate inNodes:queryNodes screen:screen];
    if(gesture.unresolved)
    {
        NSLog(@"operate %@ target not found id %@ text %@", operate.act, operate.queryIdentifier ?: @"", operate.queryText ?: @"");
        return PGOperateResultTargetNotFound;
    }
    XCUICoordinate *origin = [application coordinateWithNormalizedOffset:CGVectorMake(0, 0)];
    switch(gesture.kind)
    {
        case PGGestureKindTap: {
            XCUICoordinate *point = [origin coordinateWithOffset:CGVectorMake(gesture.start.left, gesture.start.top)];
            if(gesture.duration >= 0.4)
            {
                [point pressForDuration:gesture.duration];
            }
            else
            {
                [point tap];
            }
            break;
        }
        case PGGestureKindSwipe:
        case PGGestureKindForceBack: {
            CGFloat midY = screen.height / 2;
            PGElementRect startRect = gesture.kind == PGGestureKindForceBack ? (PGElementRect){2, (NSInteger)midY, 1, 1} : gesture.start;
            PGElementRect endRect = gesture.kind == PGGestureKindForceBack ? (PGElementRect){(NSInteger)MAX(160.0, screen.width * 0.45), (NSInteger)midY, 1, 1} : gesture.end;
            XCUICoordinate *start = [origin coordinateWithOffset:CGVectorMake(startRect.left, startRect.top)];
            XCUICoordinate *end = [origin coordinateWithOffset:CGVectorMake(endRect.left, endRect.top)];
            [start pressForDuration:0.05 thenDragToCoordinate:end];
            break;
        }
        case PGGestureKindPath: {
            if(gesture.points.count < 2)
            {
                return PGOperateResultExecutionFailed;
            }
            CGPoint first = gesture.points.firstObject.CGPointValue;
            XCUICoordinate *current = [origin coordinateWithOffset:CGVectorMake(first.x, first.y)];
            for(NSUInteger index = 1; index < gesture.points.count; index++)
            {
                CGPoint next = gesture.points[index].CGPointValue;
                XCUICoordinate *target = [origin coordinateWithOffset:CGVectorMake(next.x, next.y)];
                [current pressForDuration:0.05 thenDragToCoordinate:target];
                current = target;
            }
            break;
        }
        case PGGestureKindBack: {
            CGFloat midY = screen.height / 2;
            XCUICoordinate *start = [origin coordinateWithOffset:CGVectorMake(2, midY)];
            XCUICoordinate *end = [origin coordinateWithOffset:CGVectorMake(120, midY)];
            [start pressForDuration:0.05 thenDragToCoordinate:end];
            break;
        }
        case PGGestureKindHome:
            [[XCUIDevice sharedDevice] pressButton:XCUIDeviceButtonHome];
            break;
        case PGGestureKindRestart:
            [application terminate];
            [application launch];
            break;
        case PGGestureKindLaunch:
            [application launch];
            break;
        case PGGestureKindTerminate:
            [application terminate];
            break;
        case PGGestureKindType: {
            // Without id or pos there is no field to tap; type into the one that has focus.
            if(gesture.start.width > 0)
            {
                XCUICoordinate *point = [origin coordinateWithOffset:CGVectorMake(gesture.start.left, gesture.start.top)];
                [point tap];
            }
            if(![self typeText:gesture.text inApplication:application])
            {
                return PGOperateResultExecutionFailed;
            }
            break;
        }
        case PGGestureKindDoubleTap:
            [[origin coordinateWithOffset:CGVectorMake(gesture.start.left, gesture.start.top)] doubleTap];
            break;
        case PGGestureKindPinch:
            [application pinchWithScale:gesture.scale velocity:gesture.scale > 1 ? 1.0 : -1.0];
            break;
        case PGGestureKindDrag: {
            XCUICoordinate *start = [origin coordinateWithOffset:CGVectorMake(gesture.start.left, gesture.start.top)];
            XCUICoordinate *end = [origin coordinateWithOffset:CGVectorMake(gesture.end.left, gesture.end.top)];
            [start pressForDuration:gesture.duration thenDragToCoordinate:end];
            break;
        }
        case PGGestureKindNone:
            return PGOperateResultSkipped;
    }
    return PGOperateResultSuccess;
}

@end
