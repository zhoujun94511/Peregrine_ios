#import "PGStubClient.h"

// The runner's main thread blocks on these replies; a lower QoS reply queue is a priority inversion.
static NSURLSession *PGStubSession(void)
{
    static NSURLSession *session = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSOperationQueue *queue = [[NSOperationQueue alloc] init];
        queue.qualityOfService = NSQualityOfServiceUserInteractive;
        session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]
                                                delegate:nil
                                           delegateQueue:queue];
    });
    return session;
}

@implementation PGStubClient

- (void)postMethod:(NSString *)method
            params:(NSDictionary *)params
              port:(NSInteger)port
           timeout:(NSTimeInterval)timeout
        completion:(void (^)(NSDictionary * _Nullable, NSError * _Nullable))completion
{
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%ld/", (long)port]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = timeout;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    NSDictionary *body = @{
        @"jsonrpc": @"2.0",
        @"id": @0,
        @"method": method ?: @"",
        @"params": params ?: @{}
    };
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    [[PGStubSession() dataTaskWithRequest:request
                                     completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if(error != nil || data.length < 10)
        {
            completion(nil, error ?: [NSError errorWithDomain:@"PGStubClient" code:1 userInfo:nil]);
            return;
        }
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if(![json isKindOfClass:[NSDictionary class]] || ((NSDictionary *)json)[@"result"] == nil)
        {
            completion(nil, [NSError errorWithDomain:@"PGStubClient" code:2 userInfo:nil]);
            return;
        }
        completion(json, nil);
    }] resume];
}

- (void)postMethod:(NSString *)method
            params:(NSDictionary *)params
              port:(NSInteger)port
        completion:(void (^)(NSDictionary * _Nullable, NSError * _Nullable))completion
{
    [self postMethod:method params:params port:port timeout:10 completion:completion];
}

- (void)fetchTreeOnPort:(NSInteger)port
             completion:(void (^)(NSArray * _Nullable, NSError * _Nullable))completion
{
    [self postMethod:@"get_ui_tree" params:@{@"root_id": @""} port:port timeout:4 completion:^(NSDictionary *response, NSError *error) {
        id result = response[@"result"];
        completion([result isKindOfClass:[NSArray class]] ? result : nil, error);
    }];
}

- (void)fetchAppInfoOnPort:(NSInteger)port completion:(void (^)(NSDictionary * _Nullable))completion
{
    [self postMethod:@"app_info" params:@{} port:port timeout:2 completion:^(NSDictionary *response, NSError *error) {
        id result = response[@"result"];
        completion([result isKindOfClass:[NSDictionary class]] ? result : nil);
    }];
}

- (void)fetchPerfOnPort:(NSInteger)port completion:(void (^)(NSDictionary * _Nullable))completion
{
    [self postMethod:@"app_perf" params:@{} port:port timeout:1 completion:^(NSDictionary *response, NSError *error) {
        id result = response[@"result"];
        completion([result isKindOfClass:[NSDictionary class]] ? result : nil);
    }];
}

- (void)probeOnPort:(NSInteger)port completion:(void (^)(BOOL))completion
{
    // stub.m binds about 2 seconds after launch.
    [self probeOnPort:port within:8 completion:completion];
}

- (void)probeOnPort:(NSInteger)port within:(NSTimeInterval)seconds completion:(void (^)(BOOL))completion
{
    [self probeOnPort:port deadline:[NSDate dateWithTimeIntervalSinceNow:seconds] completion:completion];
}

- (void)probeOnPort:(NSInteger)port deadline:(NSDate *)deadline completion:(void (^)(BOOL))completion
{
    [self postMethod:@"kill_process" params:@{} port:port timeout:1 completion:^(NSDictionary *response, NSError *error) {
        if(error == nil && response[@"result"] != nil)
        {
            completion(YES);
            return;
        }
        if([deadline timeIntervalSinceNow] <= 0)
        {
            completion(NO);
            return;
        }
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
            PGStubClient *strongSelf = weakSelf;
            if(strongSelf == nil)
            {
                completion(NO);
                return;
            }
            [strongSelf probeOnPort:port deadline:deadline completion:completion];
        });
    }];
}

@end
