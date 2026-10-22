#import <Foundation/Foundation.h>
#import "PGBehavior.h"
#import "PGGraph.h"

NS_ASSUME_NONNULL_BEGIN

// getOperate:
//   an unreadable tree yields an empty operate;
//   the first call installs N-step Q when no agent was chosen;
//   the graph records the screen and the edge from the previous screen;
//   once the decision meter reaches 101 the operate is RESTART, the meter returns to 0, action values are halved,
//   and blacklisted actions become eligible again;
//   otherwise the selector chooses a gesture, or BACK when nothing on screen can be operated.
//   A short loop between a few screens asks for other actions, then BACK, a top-corner tap,
//   a downward drag, then RESTART. The screens in that restart wait 60 steps before the same
//   loop can restart the app again. The 101-decision meter is unchanged.
@interface PGModel : NSObject
@property (nonatomic, strong, readonly) PGGraph *graph;
@property (nonatomic, strong, readonly) PGOperateSelector *selector;
@property (nonatomic, assign, readonly) NSInteger decisionCount;
@property (nonatomic, assign) NSInteger restartMeter;
// When set, the 101-decision meter keeps selecting a click.
@property (nonatomic, assign) BOOL skipRestart;
- (instancetype)initWithAgent:(PGAgentKind)kind;
- (PGOperate *)operateForTreeText:(nullable NSString *)treeText activity:(nullable NSString *)activity;
- (PGOperate *)operateForNodes:(NSArray<PGElementNode *> *)nodes activity:(nullable NSString *)activity;
// The action that entered the current screen should not be chosen again.
- (void)blacklistLastAction;
// The last operate was replaced and never ran. The next screen is not linked to it.
- (void)discardLatestOperate;
// A cycle-escape RESTART from the latest operateForNodes actually ran.
- (void)confirmCycleRestart;
// Reads and writes peregrine-<bundle>.reuse.json. An empty directory uses the temporary directory.
- (void)loadReuseFromDirectory:(nullable NSString *)directory bundleID:(nullable NSString *)bundleID;
- (void)saveReuse;
@end

NS_ASSUME_NONNULL_END
