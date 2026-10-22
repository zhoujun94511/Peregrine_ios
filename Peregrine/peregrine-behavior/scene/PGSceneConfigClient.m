#import "PGSceneConfigClient.h"

// The caller blocks on the reply, usually from the runner's main thread.
static NSURLSession *PGSceneConfigSession(void)
{
    static NSURLSession *session = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSOperationQueue *queue = [[NSOperationQueue alloc] init];
        queue.qualityOfService = NSQualityOfServiceUserInteractive;
        session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]
                                                delegate:nil
                                           delegateQueue:queue];
    });
    return session;
}

@implementation PGSceneConfigClient

+ (NSArray *)scenesFromURL:(NSString *)urlString timeout:(NSTimeInterval)timeout
{
    NSURL *url = [NSURL URLWithString:urlString ?: @""];
    if(url.scheme.length == 0 || timeout <= 0)
    {
        return nil;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";
    request.timeoutInterval = timeout;
    dispatch_semaphore_t gate = dispatch_semaphore_create(0);
    __block NSData *body = nil;
    __block NSInteger status = 0;
    [[PGSceneConfigSession() dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        body = data;
        if([response isKindOfClass:[NSHTTPURLResponse class]])
        {
            status = ((NSHTTPURLResponse *)response).statusCode;
        }
        dispatch_semaphore_signal(gate);
    }] resume];
    if(dispatch_semaphore_wait(gate, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC))) != 0)
    {
        return nil;
    }
    if(status < 200 || status >= 300 || body.length == 0)
    {
        return nil;
    }
    id json = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
    if([json isKindOfClass:[NSArray class]])
    {
        return json;
    }
    if(![json isKindOfClass:[NSDictionary class]])
    {
        return nil;
    }
    NSDictionary *object = json;
    if([object[@"sceneLimits"] isKindOfClass:[NSArray class]])
    {
        return object[@"sceneLimits"];
    }
    if([object[@"sceneLimit"] isKindOfClass:[NSDictionary class]])
    {
        return @[object[@"sceneLimit"]];
    }
    return nil;
}

@end
