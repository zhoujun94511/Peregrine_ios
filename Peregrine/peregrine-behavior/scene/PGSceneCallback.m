#import "PGSceneCallback.h"

static const NSTimeInterval PGSceneCallbackTimeout = 5;

@interface PGSceneCallback ()
@property (nonatomic, copy) NSString *urlString;
@property (nonatomic, assign, readwrite) BOOL inside;
@property (nonatomic, copy) NSString *scheme;
@property (nonatomic, strong) dispatch_queue_t queue;
@end

@implementation PGSceneCallback

- (instancetype)initWithURL:(NSString *)url
{
    self = [super init];
    if(self != nil)
    {
        _urlString = url ?: @"";
        _queue = dispatch_queue_create("com.peregrine.scenecallback", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)enteredScheme:(NSString *)scheme allow:(NSArray *)allow block:(NSArray *)block
{
    if(self.inside)
    {
        return;
    }
    self.inside = YES;
    self.scheme = scheme ?: @"";
    [self post:@{
        @"event": @"enter",
        @"scheme": scheme ?: @"",
        @"allow": allow ?: @[],
        @"block": block ?: @[]
    }];
}

- (void)exitedScheme:(NSString *)scheme
{
    if(!self.inside)
    {
        return;
    }
    self.inside = NO;
    [self post:@{@"event": @"exit", @"scheme": scheme ?: @""}];
}

- (void)finishWithin:(NSTimeInterval)seconds
{
    [self exitedScheme:self.scheme];
    dispatch_semaphore_t drained = dispatch_semaphore_create(0);
    dispatch_async(self.queue, ^{
        dispatch_semaphore_signal(drained);
    });
    dispatch_semaphore_wait(drained, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)));
}

- (void)post:(NSDictionary *)body
{
    NSURL *url = [NSURL URLWithString:self.urlString];
    if(url == nil || self.urlString.length == 0)
    {
        return;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = PGSceneCallbackTimeout;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    dispatch_async(self.queue, ^{
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            dispatch_semaphore_signal(done);
        }] resume];
        dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)((PGSceneCallbackTimeout + 1) * NSEC_PER_SEC)));
    });
}

@end
