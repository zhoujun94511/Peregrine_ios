#import "PGStepScreen.h"
#import "PGOperateChoice.h"
#import "PGScreenGrab.h"
#import "PGSnapshotTree.h"
#import "PGExclusionCover.h"

// The fingerprint samples every 32nd pixel, so a toggled switch or a new badge can keep it.
static const NSInteger PGCachedTreeReuseLimit = 3;

@implementation PGStepSnapshot
@end

@implementation PGStepScreen
{
    PGStepSnapshot *_stepSnapshot;
    NSInteger _cachedReuses;
    uint64_t _cachedFingerprint;
    NSArray<PGElementNode *> *_cachedNodes;
    NSString *_cachedActivity;
    BOOL _cachedOutside;
    BOOL _cachedPointTree;
    BOOL _cachedCorrectionDone;
}

- (void)captureInApplication:(XCUIApplication *)application
                    stubAlive:(BOOL)stubAlive
                       client:(PGStubClient *)client
                         port:(NSInteger)port
                 snapshotMode:(BOOL)snapshotMode
                correctClicks:(BOOL)correctClicks
                 segmentation:(PGSegmentation *)segmentation
{
    self.pixelNodes = nil;
    self.pixelSize = CGSizeZero;
    self.image = nil;
    self.rawTree = nil;
    self.activity = nil;
    self.outside = NO;
    self.hierarchyInspected = NO;
    self.hierarchyUnread = NO;
    self.usePoints = NO;
    self.correctionDone = NO;
    self.fingerprint = 0;
    _stepSnapshot = nil;
    self.screenSize = application.frame.size;
    if(stubAlive)
    {
        self.source = @"stub";
        self.usePoints = YES;
        self.rawTree = [PGOperateChoice treeFromClient:client port:port];
        NSArray<PGElementNode *> *nodes = [PGElementNode nodesFromResult:self.rawTree];
        self.activity = [PGOperateChoice activityInNodes:nodes];
        self.fingerprint = [PGElementNode fingerprintOfNodes:nodes];
        self.nodes = [self pointNodesClearOfExcluded:nodes];
        return;
    }
    NSInteger pixelWidth = 0;
    NSInteger pixelHeight = 0;
    self.image = [PGScreenGrab uprightScreenshotOfApplication:application];
    NSData *gray = [PGScreenGrab grayDataFromImage:self.image width:&pixelWidth height:&pixelHeight];
    uint64_t fingerprint = [PGScreenGrab hashGray:gray.bytes width:pixelWidth height:pixelHeight];
    self.fingerprint = fingerprint;
    self.pixelSize = CGSizeMake(pixelWidth, pixelHeight);
    if(snapshotMode)
    {
        [self captureSnapshot:application gray:gray width:pixelWidth height:pixelHeight fingerprint:fingerprint segmentation:segmentation];
        return;
    }
    [self captureScreenshot:application gray:gray width:pixelWidth height:pixelHeight fingerprint:fingerprint correctClicks:correctClicks segmentation:segmentation];
}

- (NSArray<PGElementNode *> *)pointNodesClearOfExcluded:(NSArray<PGElementNode *> *)nodes
{
    if(self.exclusion.names.count == 0)
    {
        return nodes;
    }
    return [self nodes:nodes clearOfCovers:[self.exclusion coversInNodes:nodes]];
}

- (NSArray<PGElementNode *> *)pixelNodesClearOfExcluded:(NSArray<PGElementNode *> *)nodes application:(XCUIApplication *)application
{
    if(self.exclusion.names.count == 0)
    {
        return nodes;
    }
    return [self nodes:nodes clearOfCovers:[PGExclusionCover coversForExclusion:self.exclusion inApplication:application pixelSize:self.pixelSize screenSize:self.screenSize]];
}

- (NSArray<PGElementNode *> *)nodes:(NSArray<PGElementNode *> *)nodes clearOfCovers:(NSArray<PGElementNode *> *)covers
{
    NSInteger before = [PGElementNode flattenedNodes:nodes].count;
    NSArray<PGElementNode *> *kept = [self.exclusion nodes:nodes clearOfCovers:covers];
    NSInteger dropped = before - (NSInteger)[PGElementNode flattenedNodes:kept].count;
    if(dropped > 0)
    {
        NSLog(@"exclude elements covers %lu dropped %ld", (unsigned long)covers.count, (long)dropped);
    }
    return kept;
}

- (void)rememberOutsidePage:(NSString *)pageName fingerprint:(uint64_t)fingerprint
{
    _cachedFingerprint = fingerprint;
    _cachedNodes = @[];
    _cachedActivity = pageName;
    _cachedOutside = YES;
    _cachedPointTree = NO;
    self.outside = YES;
    self.hierarchyInspected = YES;
    self.source = @"snapshot-outside";
    if(pageName.length > 0)
    {
        self.activity = pageName;
    }
}

- (void)rememberCorrectedNodes:(NSArray<PGElementNode *> *)nodes activity:(NSString *)activity fingerprint:(uint64_t)fingerprint
{
    nodes = [self pointNodesClearOfExcluded:nodes];
    self.nodes = nodes;
    self.usePoints = YES;
    self.source = @"corrected";
    self.correctionDone = YES;
    if(activity.length > 0)
    {
        self.activity = activity;
    }
    _cachedFingerprint = fingerprint;
    _cachedNodes = nodes;
    _cachedActivity = self.activity;
    _cachedOutside = NO;
    _cachedPointTree = YES;
    _cachedCorrectionDone = YES;
}

- (void)rememberCorrectionAttempted
{
    self.correctionDone = YES;
    _cachedCorrectionDone = YES;
}

- (void)discardTreeCache
{
    _cachedFingerprint = 0;
    _cachedNodes = nil;
    _cachedReuses = 0;
}

- (PGStepSnapshot *)snapshotInApplication:(XCUIApplication *)application
{
    if(_stepSnapshot != nil)
    {
        return _stepSnapshot;
    }
    PGStepSnapshot *snapshot = [[PGStepSnapshot alloc] init];
    NSString *pageName = nil;
    BOOL outside = NO;
    NSDate *started = [NSDate date];
    @try {
        snapshot.nodes = [PGSnapshotTree nodesFromApplication:application pageName:&pageName outsideApp:&outside];
    } @catch (NSException *exception) {
        snapshot.failure = exception.reason ?: exception.name;
        snapshot.nodes = @[];
        outside = NO;
        pageName = nil;
    }
    snapshot.elapsedMillis = (NSInteger)([[NSDate date] timeIntervalSinceDate:started] * 1000.0);
    snapshot.pageName = pageName;
    snapshot.outside = outside;
    _stepSnapshot = snapshot;
    return snapshot;
}

- (BOOL)reuseCacheFor:(uint64_t)fingerprint
{
    if(fingerprint == 0 || fingerprint != _cachedFingerprint || _cachedNodes == nil)
    {
        _cachedReuses = 0;
        return NO;
    }
    if(_cachedReuses >= PGCachedTreeReuseLimit)
    {
        _cachedReuses = 0;
        return NO;
    }
    _cachedReuses += 1;
    return YES;
}

- (void)captureSnapshot:(XCUIApplication *)application
                   gray:(NSData *)gray
                  width:(NSInteger)pixelWidth
                 height:(NSInteger)pixelHeight
            fingerprint:(uint64_t)fingerprint
           segmentation:(PGSegmentation *)segmentation
{
    self.usePoints = YES;
    PGStepSnapshot *snapshot = [self snapshotInApplication:application];
    if(snapshot.failure != nil)
    {
        NSLog(@"snapshot failed %@", snapshot.failure);
    }
    NSString *pageName = snapshot.pageName;
    BOOL outside = snapshot.outside;
    NSArray<PGElementNode *> *nodes = snapshot.nodes;
    self.hierarchyInspected = snapshot.failure == nil;
    self.hierarchyUnread = snapshot.failure != nil;
    if(outside)
    {
        NSLog(@"snapshot outside page %@", pageName);
        self.source = @"snapshot-outside";
        self.nodes = @[];
        self.outside = YES;
        self.activity = pageName;
        _cachedFingerprint = fingerprint;
        _cachedNodes = @[];
        _cachedActivity = pageName;
        _cachedOutside = YES;
        _cachedPointTree = NO;
        return;
    }
    // A snapshot object with no nodes is not a screen that was read. An empty array must not clear a cover timer.
    if(nodes.count == 0)
    {
        self.hierarchyInspected = NO;
        self.hierarchyUnread = YES;
        self.nodes = @[];
        self.usePoints = NO;
        return;
    }
    if(!_cachedOutside && _cachedNodes.count > 0 && [self reuseCacheFor:fingerprint])
    {
        self.nodes = _cachedNodes;
        self.activity = pageName.length > 0 ? pageName : _cachedActivity;
        self.outside = NO;
        self.hierarchyInspected = YES;
        self.hierarchyUnread = NO;
        self.source = @"snapshot";
        self.usePoints = YES;
        return;
    }
    self.source = @"snapshot";
    NSArray<PGElementNode *> *holes = [PGScreenGrab nodesFromGray:gray.bytes width:pixelWidth height:pixelHeight segmentation:segmentation];
    self.nodes = [self pointNodesClearOfExcluded:[PGSnapshotTree nodesByAddingHoles:holes toSnapshotNodes:nodes pixelSize:CGSizeMake(pixelWidth, pixelHeight) screenSize:self.screenSize]];
    self.activity = pageName;
    _cachedFingerprint = fingerprint;
    _cachedNodes = self.nodes;
    _cachedActivity = self.activity;
    _cachedOutside = NO;
    _cachedPointTree = YES;
}

// Nodes shorter than 20pt stay off this tree. The pixel hit test still drops thin clicks; handing those nodes to the model would tap them.
- (NSArray<PGElementNode *> *)operableSnapshotNodes:(NSArray<PGElementNode *> *)nodes
{
    NSMutableArray<PGElementNode *> *kept = [NSMutableArray array];
    BOOL interactive = NO;
    for(PGElementNode *node in [self pointNodesClearOfExcluded:nodes])
    {
        if(node.rect.height < 20)
        {
            continue;
        }
        [kept addObject:node];
        if(node.interactive)
        {
            interactive = YES;
        }
    }
    return interactive ? kept : @[];
}

- (BOOL)adoptOperableSnapshot:(NSArray<PGElementNode *> *)nodes pageName:(NSString *)pageName fingerprint:(uint64_t)fingerprint
{
    NSArray<PGElementNode *> *operable = [self operableSnapshotNodes:nodes];
    if(operable.count == 0)
    {
        return NO;
    }
    self.nodes = operable;
    self.usePoints = YES;
    self.correctionDone = YES;
    self.source = @"snapshot";
    self.outside = NO;
    self.hierarchyInspected = YES;
    self.hierarchyUnread = NO;
    if(pageName.length > 0)
    {
        self.activity = pageName;
    }
    if(fingerprint != 0)
    {
        _cachedFingerprint = fingerprint;
        _cachedNodes = operable;
        _cachedActivity = self.activity;
        _cachedOutside = NO;
        _cachedPointTree = YES;
        _cachedCorrectionDone = YES;
    }
    return YES;
}

- (void)captureScreenshot:(XCUIApplication *)application
                     gray:(NSData *)gray
                    width:(NSInteger)pixelWidth
                   height:(NSInteger)pixelHeight
              fingerprint:(uint64_t)fingerprint
            correctClicks:(BOOL)correctClicks
             segmentation:(PGSegmentation *)segmentation
{
    PGStepSnapshot *snapshot = [self snapshotInApplication:application];
    self.hierarchyInspected = snapshot.failure == nil;
    self.hierarchyUnread = snapshot.failure != nil;
    if(snapshot.outside)
    {
        self.outside = YES;
        self.source = @"snapshot-outside";
        self.nodes = @[];
        self.usePoints = NO;
        if(snapshot.pageName.length > 0)
        {
            self.activity = snapshot.pageName;
        }
        if(fingerprint != 0)
        {
            _cachedFingerprint = fingerprint;
            _cachedNodes = @[];
            _cachedActivity = self.activity;
            _cachedOutside = YES;
            _cachedPointTree = NO;
            _cachedCorrectionDone = YES;
        }
        return;
    }
    if(snapshot.failure != nil || snapshot.nodes.count == 0)
    {
        self.hierarchyInspected = NO;
        self.hierarchyUnread = YES;
        self.nodes = @[];
        self.usePoints = NO;
        return;
    }
    if(correctClicks && !_cachedOutside && _cachedNodes.count > 0 && [self reuseCacheFor:fingerprint])
    {
        self.nodes = _cachedNodes;
        self.activity = snapshot.pageName.length > 0 ? snapshot.pageName : _cachedActivity;
        self.outside = NO;
        self.hierarchyInspected = YES;
        self.hierarchyUnread = NO;
        self.usePoints = _cachedPointTree;
        self.correctionDone = _cachedCorrectionDone;
        self.source = self.usePoints ? @"corrected" : @"screenshot";
        if(!self.usePoints)
        {
            self.pixelNodes = self.nodes;
        }
        return;
    }
    if(correctClicks && [self adoptOperableSnapshot:snapshot.nodes pageName:snapshot.pageName fingerprint:fingerprint])
    {
        return;
    }
    self.source = @"screenshot";
    self.nodes = [self pixelNodesClearOfExcluded:[PGScreenGrab nodesFromGray:gray.bytes width:pixelWidth height:pixelHeight segmentation:segmentation] application:application];
    self.pixelNodes = self.nodes;
    if(correctClicks && fingerprint != 0 && self.hierarchyInspected)
    {
        _cachedFingerprint = fingerprint;
        _cachedNodes = self.nodes;
        _cachedActivity = nil;
        _cachedOutside = NO;
        _cachedPointTree = NO;
        _cachedCorrectionDone = NO;
    }
}

@end
