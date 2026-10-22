#import "PGBehavior.h"

NS_ASSUME_NONNULL_BEGIN

// One scripted case. timeout is seconds. When it elapses and restart is set,
// the schedule asks for RESTART and moves to the next case.
// Each dueOperateAt: call consumes a step, so call it only when the step will run.
// A step that is not a dictionary counts as a failure; three failures skip the case.
@interface PGCaseSchedule : NSObject
@property (nonatomic, assign, readonly) NSInteger failCount;
- (instancetype)initWithCases:(NSArray *)cases;
- (nullable PGOperate *)dueOperateAt:(NSDate *)now allowsRestart:(BOOL)allowsRestart;
- (void)noteStepFailed;
@end

NS_ASSUME_NONNULL_END
