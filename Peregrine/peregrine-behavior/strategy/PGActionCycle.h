#import "PGOperateSelector.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PGActionCycleStatus) {
    PGActionCycleStatusRetry = 0,
    PGActionCycleStatusOperate,
    PGActionCycleStatusCustomCommand,
};

@interface PGActionCycleResult : NSObject
@property (nonatomic, assign) PGActionCycleStatus status;
@property (nonatomic, strong, nullable) PGOperate *operate;
@property (nonatomic, copy, nullable) NSString *customCommand;
@property (nonatomic, copy, nullable) NSDictionary *modelRequest;
@end

@interface PGActionCycle : NSObject
@property (nonatomic, assign) NSInteger emptyTreeCount;
@property (nonatomic, assign) PGAgentKind agentKind;

// Stub mode. A tree shorter than 20 characters counts as empty.
// More than 50 empty reads in a row produce a RESTART operate and the counter resets.
// A non-empty custom command is returned as-is and skips model selection.
- (PGActionCycleResult *)evaluateStubTree:(nullable NSString *)tree
                            customCommand:(nullable NSString *)customCommand
                                 activity:(nullable NSString *)activity
                             actionSource:(NSUInteger)actionSource
                                  context:(NSDictionary *)context
                                 selector:(PGOperateSelector *)selector;
@end

NS_ASSUME_NONNULL_END
