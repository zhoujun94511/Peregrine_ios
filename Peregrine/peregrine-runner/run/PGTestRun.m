#import "PGTestRun.h"
#import "PGConfig.h"
#import "PGModel.h"
#import "PGGestureMix.h"
#import "PGStubClient.h"
#import "PGStubWatch.h"
#import "PGSegmentation.h"
#import "PGCaseSchedule.h"
#import "PGCoverage.h"
#import "PGPreference.h"
#import "PGSceneQueue.h"
#import "PGCommandServer.h"
#import "PGBlockRecovery.h"
#import "PGAppletSession.h"
#import "PGSceneCallback.h"
#import "PGAppWatch.h"
#import "PGAlertGate.h"
#import "PGSceneConfigClient.h"
#import "PGEventLog.h"
#import "PGSnapshotTree.h"
#import "PGExploreScore.h"
#import "PGStepScreen.h"
#import "PGClickCorrector.h"
#import "PGOverlayGate.h"
#import "PGImageGate.h"
#import "PGOutsideGate.h"
#import "PGRunFiles.h"
#import "PGStepShots.h"
#import "PGPerfSampler.h"
#import "PGOperateChoice.h"
#import "PGOperatePlayer.h"
#import "PGEnvironment.h"

static NSString * PGAppStateName(XCUIApplicationState state)
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

static NSArray<NSString *> * PGInputTexts(NSDictionary *environment)
{
    NSString *path = [PGEnvironment stringForKey:@"PEREGRINE_STRINGS" inEnvironment:environment];
    NSString *text = path.length > 0 ? [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] : nil;
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for(NSString *line in [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]])
    {
        if(line.length > 0)
        {
            [lines addObject:line];
        }
    }
    return lines.count > 0 ? lines : @[@"peregrine", @"1", @"test"];
}

static NSInteger PGActionTimeoutMillis(NSDictionary *environment)
{
    id value = environment[@"ACTION_TIMEOUT_MS"];
    NSInteger millis = [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : 0;
    return millis > 0 ? millis : 8000;
}

static NSInteger PGShotsLimit(NSDictionary *environment)
{
    id value = environment[@"PEREGRINE_SHOTS_LIMIT"];
    NSInteger limit = [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : 0;
    return limit > 0 ? limit : 500;
}

static void PGReturnToApp(PGAppWatch *appWatch, XCUIApplication *app, PGEventLog *events, BOOL allowsRestart)
{
    [appWatch returnFromForeignScreen:app allowsRestart:allowsRestart];
    NSString *kind = appWatch.lastRecovery == PGAppWatchRecoveryRestart ? @"foreign_screen_restart" : @"foreign_screen_activate";
    NSLog(@"return app to foreground %@ %ld", kind, (long)appWatch.lastAttempt);
    [events recordEventType:@"app_state_changed" fields:@{
        @"app_state": PGAppStateName(app.state),
        @"result": kind
    }];
}

static void PGNoteOutside(PGExploreScore *score, PGStepScreen *screens, NSString *bundleID)
{
    NSString *activity = screens.activity.length > 0 ? screens.activity : @"foreground";
    [score noteSource:@"outside" activity:activity fingerprint:screens.fingerprint operate:nil bundleID:bundleID];
}

@implementation PGTestRun

+ (void)runWithEnvironment:(NSDictionary *)environment testCase:(XCTestCase *)testCase
{
    testCase.continueAfterFailure = YES;
    PGSession *session = [PGSession sessionFromEnvironment:environment];
    XCTAssertTrue(session != nil, @"Set PEREGRINE_BUNDLEID to the app under test");
    if(session == nil)
    {
        return;
    }
    PGConfig *config = [PGConfig loadedConfig];
    PGModel *model = [[PGModel alloc] initWithAgent:PGAgentKindNStepQ];
    model.skipRestart = config.skipRestart;
    model.selector.gestures = [[PGGestureMix alloc] initWithRatios:config.gestureRatios];
    PGActionCycle *cycle = [[PGActionCycle alloc] init];
    cycle.agentKind = PGAgentKindNStepQ;
    PGSceneLimit *sceneLimit = [[PGSceneLimit alloc] init];
    [config applyToSceneLimit:sceneLimit];
    PGPreference *preference = [[PGPreference alloc] init];
    [config applyToPreference:preference];
    PGCaseSchedule *cases = [[PGCaseSchedule alloc] initWithCases:config.cases];
    PGCoverage *coverage = [[PGCoverage alloc] init];
    PGStubClient *client = [[PGStubClient alloc] init];
    PGSegmentation *segmentation = [[PGSegmentation alloc] init];
    segmentation.excludeRects = config.excludeRects;
    PGBlockRecovery *block = [[PGBlockRecovery alloc] init];
    NSString *callbackURL = config.sceneCallbackURL;
    id callbackOverride = environment[@"SCENE_CALLBACK"];
    if(callbackURL.length == 0 && [callbackOverride isKindOfClass:[NSString class]])
    {
        callbackURL = callbackOverride;
    }
    PGSceneCallback *sceneCallback = [[PGSceneCallback alloc] initWithURL:callbackURL];
    PGAppletSession *applet = [[PGAppletSession alloc] initWithSchema:config.appletSchema];
    NSString *sceneURL = config.sceneConfigURL;
    id sceneOverride = environment[@"SCENE_CONFIG_URL"];
    if(sceneURL.length == 0 && [sceneOverride isKindOfClass:[NSString class]])
    {
        sceneURL = sceneOverride;
    }
    NSArray *remoteScenes = sceneURL.length > 0 ? [PGSceneConfigClient scenesFromURL:sceneURL timeout:8] : nil;
    PGSceneQueue *sceneQueue = [[PGSceneQueue alloc] initWithScenes:remoteScenes != nil ? remoteScenes : config.sceneLimits];
    PGAppWatch *appWatch = [[PGAppWatch alloc] init];
    id portValue = environment[@"PEREGRINE_COMMAND_PORT"];
    NSInteger commandPort = [portValue respondsToSelector:@selector(integerValue)] ? [portValue integerValue] : 0;
    PGCommandServer *commands = [[PGCommandServer alloc] initWithPort:commandPort];
    if(![commands start])
    {
        commandPort = 0;
    }

    NSMutableDictionary *launchEnvironment = [[PGSession launchEnvironmentFromEncoded:environment[@"PEREGRINE_LAUNCHENV"]] mutableCopy];
    if(session.dataPort > 0 && launchEnvironment[@"stubPort"] == nil)
    {
        launchEnvironment[@"stubPort"] = [NSString stringWithFormat:@"%ld", (long)session.dataPort];
    }
    [PGAlertGate installSystemMonitorOn:testCase];
    if(!config.skipHome)
    {
        [[XCUIDevice sharedDevice] pressButton:XCUIDeviceButtonHome];
    }
    XCUIApplication *app = [[XCUIApplication alloc] initWithBundleIdentifier:session.bundleID];
    BOOL perfEnabled = session.dataPort > 0 && [[PGEnvironment stringForKey:@"PEREGRINE_PERF" inEnvironment:environment] isEqualToString:@"1"];
    if(perfEnabled)
    {
        launchEnvironment[@"stubPerf"] = @"1";
    }
    app.launchEnvironment = launchEnvironment;
    [app launch];

    PGStubWatch *stubWatch = [[PGStubWatch alloc] initWithClient:client port:session.dataPort bundleID:session.bundleID];
    BOOL stubAlive = [stubWatch probeAtLaunch];
    PGSnapshotSourceMode sourceMode = [PGSnapshotTree sourceModeInEnvironment:environment];
    BOOL snapshotEnabled = !stubAlive && sourceMode == PGSnapshotSourceModeSnapshot;
    BOOL correctClicks = !stubAlive && sourceMode == PGSnapshotSourceModeCombined;
    NSString *uiMode = stubAlive ? @"stub" : (snapshotEnabled ? @"snapshot" : (correctClicks ? @"combined" : @"screenshot"));
    NSLog(@"stub probe port %ld alive %d channel %@ command %ld ui %@", (long)session.dataPort, stubAlive, config.channel, (long)commandPort, uiMode);
    NSString *coverageDirectory = [PGEnvironment stringForKey:@"PEREGRINE_COVERAGE_DIR" inEnvironment:environment];
    NSString *outputDirectory = [coverageDirectory isKindOfClass:[NSString class]] ? coverageDirectory : @"";
    [PGRunFiles keepPreviousRunInDirectory:outputDirectory];
    PGEventLog *events = [[PGEventLog alloc] initWithDirectory:outputDirectory];
    PGStepShotsMode shotsMode = [PGStepShots modeFromText:[PGEnvironment stringForKey:@"PEREGRINE_SHOTS" inEnvironment:environment]];
    PGStepShots *shots = [[PGStepShots alloc] initWithMode:shotsMode directory:outputDirectory limit:PGShotsLimit(environment)];
    PGPerfSampler *perf = [[PGPerfSampler alloc] initWithEnabled:perfEnabled && stubAlive client:client port:session.dataPort log:events];
    [model loadReuseFromDirectory:outputDirectory bundleID:session.bundleID];
    model.selector.inputTexts = PGInputTexts(environment);
    NSInteger actionTimeoutMillis = PGActionTimeoutMillis(environment);
    NSDate *taskStarted = [NSDate date];
    [appWatch startPulse];
    [events recordEventType:@"task_start" fields:@{@"app_state": PGAppStateName(app.state), @"result": session.bundleID ?: @""}];
    PGStepScreen *screens = [[PGStepScreen alloc] init];
    screens.exclusion = [[PGElementExclusion alloc] initWithNames:config.excludeElements];
    PGClickCorrector *corrector = [[PGClickCorrector alloc] init];
    PGOverlayGate *overlayGate = [[PGOverlayGate alloc] init];
    PGImageGate *imageGate = [[PGImageGate alloc] init];
    PGOutsideGate *outsideGate = [[PGOutsideGate alloc] init];
    PGExploreScore *score = [[PGExploreScore alloc] init];
    while(![session timeIsUp])
    {
        @autoreleasepool
        {
            [appWatch beat];
            if([appWatch consumeSlowStep] && !config.skipRestart)
            {
                NSLog(@"run step slow restart");
                [app terminate];
                [app launch];
                [appWatch noteInApplication];
            }
            else if([appWatch exploreIdle] && !config.skipRestart)
            {
                NSLog(@"run explore idle restart");
                [app terminate];
                [app launch];
                [appWatch noteInApplication];
            }
            NSURL *schemaURL = [applet URLToOpenOnce];
            if([PGOperatePlayer openURL:schemaURL application:app])
            {
                [NSThread sleepForTimeInterval:session.throttleMilliseconds / 1000.0];
                continue;
            }
            if([PGAlertGate dismissBlockingAlertsInApplication:app])
            {
                [NSThread sleepForTimeInterval:session.throttleMilliseconds / 1000.0];
                continue;
            }
            PGForegroundWatch process = [appWatch considerProcess:app allowsRestart:!config.skipRestart];
            if(process != PGForegroundWatchTarget)
            {
                if(process == PGForegroundWatchReturn)
                {
                    BOOL crashed = appWatch.lastState == XCUIApplicationStateNotRunning;
                    NSString *kind = @"left_foreground";
                    if(crashed && appWatch.lastRecovery == PGAppWatchRecoveryRestart)
                    {
                        kind = @"suspected_crash_restart";
                    }
                    else if(crashed)
                    {
                        kind = @"suspected_crash";
                    }
                    else if(appWatch.lastRecovery == PGAppWatchRecoveryRestart)
                    {
                        kind = @"left_foreground_restart";
                    }
                    [events recordEventType:@"app_state_changed" fields:@{
                        @"app_state": PGAppStateName(appWatch.lastState),
                        @"result": kind
                    }];
                    NSLog(@"return app to foreground %@ %ld", kind, (long)appWatch.lastAttempt);
                }
                [NSThread sleepForTimeInterval:session.throttleMilliseconds / 1000.0];
                continue;
            }
            if(!stubAlive && [appWatch coverHoldActive])
            {
                [screens discardTreeCache];
            }
            [screens captureInApplication:app stubAlive:stubAlive client:client port:session.dataPort snapshotMode:snapshotEnabled correctClicks:correctClicks segmentation:segmentation];
            PGStubTreeVerdict verdict = stubAlive ? [stubWatch noteTree:screens.rawTree] : PGStubTreeKeep;
            if(verdict == PGStubTreeRetry)
            {
                [screens captureInApplication:app stubAlive:YES client:client port:session.dataPort snapshotMode:NO correctClicks:NO segmentation:segmentation];
                verdict = [stubWatch noteTree:screens.rawTree];
            }
            if(verdict == PGStubTreeLost)
            {
                stubAlive = NO;
                snapshotEnabled = sourceMode == PGSnapshotSourceModeSnapshot;
                correctClicks = sourceMode == PGSnapshotSourceModeCombined;
                [screens captureInApplication:app stubAlive:NO client:client port:session.dataPort snapshotMode:snapshotEnabled correctClicks:correctClicks segmentation:segmentation];
            }
            if(!stubAlive || screens.outside)
            {
                if(!stubAlive && screens.hierarchyUnread)
                {
                    NSLog(@"foreground hierarchy unread");
                }
                BOOL readCover = screens.hierarchyInspected || screens.outside || screens.hierarchyUnread;
                if(readCover)
                {
                    BOOL coveredNow = screens.outside || screens.hierarchyUnread;
                    PGForegroundWatch covered = [appWatch considerCovered:coveredNow application:app allowsRestart:!config.skipRestart];
                    if(covered != PGForegroundWatchTarget)
                    {
                        events.activity = screens.activity ?: @"";
                        PGNoteOutside(score, screens, session.bundleID);
                        if(covered == PGForegroundWatchReturn && appWatch.lastRecovery != PGAppWatchRecoveryRestart)
                        {
                            PGOperate *dismiss = [outsideGate dismissCoveringScreen:screens.screenSize];
                            NSLog(@"foreground covered dismiss");
                            [PGOperatePlayer traceOperate:dismiss nodes:@[] inApp:app cases:cases log:events timeoutMillis:actionTimeoutMillis resolveElement:NO screen:screens.screenSize];
                        }
                        else if(appWatch.lastRecovery == PGAppWatchRecoveryRestart)
                        {
                            NSLog(@"return app to foreground foreign_screen_restart %ld", (long)appWatch.lastAttempt);
                        }
                        [NSThread sleepForTimeInterval:session.throttleMilliseconds / 1000.0];
                        continue;
                    }
                }
                else if([appWatch coverHoldActive])
                {
                    events.activity = screens.activity ?: @"";
                    PGNoteOutside(score, screens, session.bundleID);
                    NSLog(@"foreground covered unreadable");
                    [NSThread sleepForTimeInterval:session.throttleMilliseconds / 1000.0];
                    continue;
                }
            }
            if(screens.activity.length == 0)
            {
                screens.activity = session.bundleID;
            }
            events.activity = screens.activity;
            NSLog(@"ui source %@ nodes %lu activity %@", screens.source, (unsigned long)screens.nodes.count, screens.activity);
            PGOverlayDecision *overlay = [outsideGate decisionForScreen:screens];
            if(overlay.action == PGOverlayActionNone)
            {
                overlay = [overlayGate decisionForScreen:screens application:app];
                if(overlay.action == PGOverlayActionNone)
                {
                    overlay = [imageGate decisionForScreen:screens application:app];
                }
            }
            if(overlay.action == PGOverlayActionForeground)
            {
                [score noteSource:screens.source activity:screens.activity fingerprint:screens.fingerprint operate:nil bundleID:session.bundleID];
                PGReturnToApp(appWatch, app, events, !config.skipRestart);
                [NSThread sleepForTimeInterval:session.throttleMilliseconds / 1000.0];
                continue;
            }
            if(overlay.action == PGOverlayActionOperate)
            {
                [appWatch noteInApplication];
                [coverage recordActivity:screens.activity.length > 0 ? screens.activity : session.bundleID];
                [applet observeActivity:screens.activity];
                [score noteSource:screens.source activity:screens.activity fingerprint:screens.fingerprint operate:overlay.operate bundleID:session.bundleID];
                if(overlay.operate.act.length > 0)
                {
                    [shots recordScreen:screens operate:overlay.operate application:app];
                    [PGOperatePlayer traceOperate:overlay.operate nodes:screens.nodes inApp:app cases:cases log:events timeoutMillis:actionTimeoutMillis resolveElement:NO screen:screens.screenSize];
                }
                NSTimeInterval overlayPause = overlay.operate.throttle > 0 ? overlay.operate.throttle / 1000.0 : session.throttleMilliseconds / 1000.0;
                [NSThread sleepForTimeInterval:overlayPause];
                continue;
            }
            [appWatch noteInApplication];
            [coverage recordActivity:screens.activity.length > 0 ? screens.activity : session.bundleID];
            [applet observeActivity:screens.activity];
            NSString *signature = [block signatureForNodes:screens.nodes fingerprint:screens.fingerprint activity:screens.activity];
            PGOperate *recovery = [block noteSignature:signature allowsRestart:!config.skipRestart];
            PGOperate *remote = [PGOperate operateFromDictionary:[commands takeCommand]];
            PGOperate *scheduled = remote.act.length > 0 ? nil : [cases dueOperateAt:[NSDate date] allowsRestart:!config.skipRestart];
            PGOperate *sceneOperate = config.skipCheckBlock ? nil : [sceneQueue restrictionForActivity:screens.activity at:[NSDate date]];
            if(sceneQueue.actionSource == 3)
            {
                [sceneCallback enteredScheme:sceneQueue.activeScheme allow:sceneQueue.activeAllow block:sceneQueue.activeBlock];
            }
            else
            {
                [sceneCallback exitedScheme:sceneQueue.activeScheme];
            }
            if(sceneOperate == nil && config.sceneLimits.count == 0 && !config.skipCheckBlock && screens.activity.length > 0 && ![sceneLimit allowsViewController:screens.activity])
            {
                sceneOperate = [[PGOperate alloc] init];
                sceneOperate.act = @"BACK";
            }
            if(sceneOperate.act.length > 0 && [sceneOperate.act caseInsensitiveCompare:@"BACK"] == NSOrderedSame)
            {
                [model blacklistLastAction];
            }
            NSString *treeText = stubAlive ? (screens.rawTree.count > 0 ? @"{\"source\":\"ui-stub-tree\"}" : @"[]") : (screens.usePoints ? @"{\"source\":\"xcui-snapshot-tree\"}" : @"");
            PGOperate *operate = remote.act.length > 0 ? remote : (scheduled.act.length > 0 ? scheduled : (sceneOperate.act.length > 0 ? sceneOperate : (screens.usePoints
                ? [PGOperateChoice operateForNodes:screens.nodes tree:treeText cycle:cycle model:model preference:preference session:session activity:screens.activity actionSource:sceneQueue.actionSource screen:screens.screenSize]
                : [PGOperateChoice operateForScreenshotNodes:screens.nodes model:model preference:preference activity:screens.activity pixels:screens.pixelSize screen:screens.screenSize])));
            BOOL higherPriority = remote.act.length > 0 || scheduled.act.length > 0 || sceneOperate.act.length > 0;
            if(higherPriority)
            {
                [model discardLatestOperate];
            }
            if(!higherPriority && recovery.act.length > 0)
            {
                NSLog(@"block recovery %@ signature %@", recovery.act, signature);
                operate = recovery;
                [model discardLatestOperate];
            }
            if(config.skipRestart && [operate.act caseInsensitiveCompare:@"RESTART"] == NSOrderedSame)
            {
                operate = [[PGOperate alloc] init];
                [model discardLatestOperate];
            }
            BOOL modelClick = !higherPriority && recovery.act.length == 0;
            if(correctClicks && [corrector allowsCorrectionForOperate:operate modelClick:modelClick usePoints:screens.usePoints correctionDone:screens.correctionDone])
            {
                PGClickCorrection *correction = [corrector correctOperate:operate application:app screen:screens pixelNodes:screens.pixelNodes ?: screens.nodes pixelSize:screens.pixelSize];
                operate = correction.operate;
                if(correction.outside)
                {
                    [model discardLatestOperate];
                    [screens rememberOutsidePage:correction.pageName fingerprint:screens.fingerprint];
                    screens.outside = YES;
                    screens.source = @"snapshot-outside";
                    PGForegroundWatch covered = [appWatch considerCovered:YES application:app allowsRestart:!config.skipRestart];
                    events.activity = screens.activity ?: @"";
                    PGNoteOutside(score, screens, session.bundleID);
                    if(covered == PGForegroundWatchReturn && appWatch.lastRecovery != PGAppWatchRecoveryRestart)
                    {
                        PGOperate *dismiss = [outsideGate dismissCoveringScreen:screens.screenSize];
                        NSLog(@"foreground covered dismiss");
                        [PGOperatePlayer traceOperate:dismiss nodes:@[] inApp:app cases:cases log:events timeoutMillis:actionTimeoutMillis resolveElement:NO screen:screens.screenSize];
                    }
                    else if(appWatch.lastRecovery == PGAppWatchRecoveryRestart)
                    {
                        NSLog(@"return app to foreground foreign_screen_restart %ld", (long)appWatch.lastAttempt);
                    }
                    [NSThread sleepForTimeInterval:session.throttleMilliseconds / 1000.0];
                    continue;
                }
                if(correction.inspected)
                {
                    [appWatch considerCovered:NO application:app allowsRestart:!config.skipRestart];
                }
                if(correction.corrected)
                {
                    [screens rememberCorrectedNodes:correction.nodes activity:correction.pageName fingerprint:screens.fingerprint];
                }
                else if(!correction.slow)
                {
                    [screens rememberCorrectionAttempted];
                }
                if(operate.act.length == 0)
                {
                    [model discardLatestOperate];
                }
            }
            [score noteSource:screens.source activity:screens.activity fingerprint:screens.fingerprint operate:operate bundleID:session.bundleID];
            if(operate.act.length > 0)
            {
                if([operate.act caseInsensitiveCompare:@"RESTART"] == NSOrderedSame)
                {
                    [block confirmRestartIssued];
                    [model confirmCycleRestart];
                }
                [shots recordScreen:screens operate:operate application:app];
                BOOL resolveElement = stubAlive || screens.usePoints;
                [PGOperatePlayer traceOperate:operate nodes:screens.nodes inApp:app cases:cases log:events timeoutMillis:actionTimeoutMillis resolveElement:resolveElement screen:screens.screenSize];
            }
            [perf sampleWithStubAlive:stubWatch.alive];
            NSTimeInterval pause = operate.throttle > 0 ? operate.throttle / 1000.0 : session.throttleMilliseconds / 1000.0;
            [NSThread sleepForTimeInterval:pause];
        }
    }
    [appWatch stopPulse];
    NSInteger elapsedMillis = (NSInteger)([[NSDate date] timeIntervalSinceDate:taskStarted] * 1000.0);
    NSLog(@"%@", [score line]);
    NSLog(@"%@", [events.anomalies line]);
    if([perf line] != nil)
    {
        NSLog(@"%@", [perf line]);
    }
    NSMutableDictionary *endFields = [@{
        @"app_state": PGAppStateName(app.state),
        @"result": @"finished",
        @"action": @{@"duration_ms": @(elapsedMillis)}
    } mutableCopy];
    [endFields addEntriesFromDictionary:[score fields]];
    [endFields addEntriesFromDictionary:[events.anomalies fields]];
    [endFields addEntriesFromDictionary:[perf fields]];
    [events recordEventType:@"task_end" fields:endFields];
    [model saveReuse];
    [sceneCallback finishWithin:3];
    [events finish];
    NSLog(@"%@", [coverage summary]);
    NSLog(@"%@", [applet summary]);
    NSError *coverageError = nil;
    if([coverage writeSummaryToDirectory:outputDirectory error:&coverageError])
    {
        NSLog(@"coverage written");
    }
    NSError *appletError = nil;
    if([applet writeSummaryToDirectory:outputDirectory error:&appletError])
    {
        NSLog(@"applet summary written");
    }
    [shots finish];
    [commands stop];
    [app terminate];
}
@end
