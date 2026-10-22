#import <XCTest/XCTest.h>

NS_ASSUME_NONNULL_BEGIN

@interface PGNetworkProbe : NSObject
/// Retries for up to 75 seconds, accepting the wireless-data dialog. A denied path does not count as success.
+ (BOOL)probeNetwork;
/// YES when the system denies this process wireless or cellular data.
+ (BOOL)pathDenied;
/// One request, up to 15 seconds, tapping the runner's network prompt if it shows. On failure `failure` holds the status and error.
+ (BOOL)requestPing:(NSString *_Nullable *_Nullable)failure;
@end

NS_ASSUME_NONNULL_END
