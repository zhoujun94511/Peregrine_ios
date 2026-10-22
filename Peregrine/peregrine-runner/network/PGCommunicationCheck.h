#import <XCTest/XCTest.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PGInternetStatus) {
    PGInternetStatusReachable = 0,
    // The system refuses the runner's wireless data (nw_path reason wifi_denied / cellular_denied).
    PGInternetStatusDenied,
    PGInternetStatusUnreachable,
};

@interface PGCommunicationReport : NSObject
@property (nonatomic, assign) BOOL loopback;
@property (nonatomic, assign) BOOL commandServer;
@property (nonatomic, assign) NSInteger commandPort;
// nil when PEREGRINE_DATAPORT is not set.
@property (nonatomic, strong, nullable) NSNumber *stub;
@property (nonatomic, assign) PGInternetStatus internet;
@property (nonatomic, assign) BOOL internetRequired;
@property (nonatomic, assign, readonly) BOOL passed;
- (NSString *)summary;
@end

// Checks behind testPingNetwork. Exploration talks over the device's loopback interface only:
// the command port and the stub listen on 127.0.0.1, and iproxy reaches the command port over USB.
// Those checks must pass. Internet access is needed only for a remote sceneConfigURL / sceneCallback
// or when PEREGRINE_REQUIRE_INTERNET=1; otherwise its status is reported without failing the test,
// because some devices deny the runner wireless data outright.
@interface PGCommunicationCheck : NSObject
+ (PGCommunicationReport *)reportWithEnvironment:(NSDictionary *)environment;
@end

NS_ASSUME_NONNULL_END
