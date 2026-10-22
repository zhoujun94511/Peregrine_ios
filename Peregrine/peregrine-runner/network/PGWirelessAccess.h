#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Brings the runner forward and accepts the system wireless-data dialog.
@interface PGWirelessAccess : NSObject
+ (BOOL)activateCurrentRunner;
+ (void)leaveForWirelessPrompt;
+ (BOOL)allowCurrentRunnerNetworkPrompt;
@end

NS_ASSUME_NONNULL_END
