#import <XCTest/XCTest.h>
#import "PGBehavior.h"
#import "PGSegmentation.h"
#import "PGStubClient.h"
#import "PGElementExclusion.h"

NS_ASSUME_NONNULL_BEGIN

@interface PGStepSnapshot : NSObject
@property (nonatomic, copy) NSArray<PGElementNode *> *nodes;
@property (nonatomic, copy, nullable) NSString *pageName;
@property (nonatomic, assign) BOOL outside;
// Exception reason when the snapshot threw; nodes is then empty.
@property (nonatomic, copy, nullable) NSString *failure;
@property (nonatomic, assign) NSInteger elapsedMillis;
@end

// The nodes for one step, including the fingerprint cache.
// A cached tree is reused at most 3 steps in a row for the same fingerprint, and only after this step's hierarchy is not covered and not empty.
@interface PGStepScreen : NSObject
@property (nonatomic, copy) NSString *source;
// application.frame.size read once per capture; each read is a round trip to the app.
@property (nonatomic, assign) CGSize screenSize;
@property (nonatomic, copy) NSArray<PGElementNode *> *nodes;
@property (nonatomic, copy, nullable) NSArray<PGElementNode *> *pixelNodes;
@property (nonatomic, copy, nullable) NSString *activity;
@property (nonatomic, copy, nullable) NSArray *rawTree;
@property (nonatomic, assign) CGSize pixelSize;
// Kept for this step only; nil when the stub tree was used.
@property (nonatomic, strong, nullable) UIImage *image;
@property (nonatomic, assign) uint64_t fingerprint;
@property (nonatomic, assign) BOOL outside;
// YES only after this step read a hierarchy. A cache of a screen that was not covered stays NO, so it cannot clear a cover timer.
@property (nonatomic, assign) BOOL hierarchyInspected;
// YES when this step's snapshot threw or returned nil. That step is not explored.
@property (nonatomic, assign) BOOL hierarchyUnread;
@property (nonatomic, assign) BOOL usePoints;
@property (nonatomic, assign) BOOL correctionDone;
// Applied to every node source before the nodes are cached.
@property (nonatomic, strong, nullable) PGElementExclusion *exclusion;
- (void)captureInApplication:(XCUIApplication *)application
                    stubAlive:(BOOL)stubAlive
                       client:(PGStubClient *)client
                         port:(NSInteger)port
                 snapshotMode:(BOOL)snapshotMode
                correctClicks:(BOOL)correctClicks
                 segmentation:(PGSegmentation *)segmentation;
- (void)rememberOutsidePage:(nullable NSString *)pageName fingerprint:(uint64_t)fingerprint;
- (void)rememberCorrectedNodes:(NSArray<PGElementNode *> *)nodes activity:(nullable NSString *)activity fingerprint:(uint64_t)fingerprint;
- (void)rememberCorrectionAttempted;
// Drops the fingerprint cache so the next capture reads the hierarchy again.
- (void)discardTreeCache;
// The XCUI snapshot of this step. Taken on first use and shared until the next capture.
- (PGStepSnapshot *)snapshotInApplication:(XCUIApplication *)application;
@end

NS_ASSUME_NONNULL_END
