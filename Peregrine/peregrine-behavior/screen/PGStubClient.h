#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// JSON-RPC client for the stub. Posts to http://127.0.0.1:<port>/ .
// A usable response is at least 10 characters and contains "result".
// kill_process is only a liveness check, answered off the app's main thread.
// The launch probe retries for 8 seconds because the stub binds 2 seconds after
// launch. A tree request gives up after 4 seconds.
@interface PGStubClient : NSObject
- (void)postMethod:(NSString *)method
            params:(nullable NSDictionary *)params
              port:(NSInteger)port
        completion:(void (^)(NSDictionary * _Nullable response, NSError * _Nullable error))completion;

- (void)fetchTreeOnPort:(NSInteger)port
             completion:(void (^)(NSArray * _Nullable tree, NSError * _Nullable error))completion;

- (void)probeOnPort:(NSInteger)port
         completion:(void (^)(BOOL alive))completion;

// info is {bundle_id, name, version} of the app hosting the stub; nil when the stub
// predates app_info or does not answer within 2 seconds.
- (void)fetchAppInfoOnPort:(NSInteger)port
                completion:(void (^)(NSDictionary * _Nullable info))completion;

// sample is the stub's app_perf payload; nil when the stub has no app_perf or does not answer within 1 second.
- (void)fetchPerfOnPort:(NSInteger)port
             completion:(void (^)(NSDictionary * _Nullable sample))completion;

- (void)probeOnPort:(NSInteger)port
             within:(NSTimeInterval)seconds
         completion:(void (^)(BOOL alive))completion;
@end

NS_ASSUME_NONNULL_END
