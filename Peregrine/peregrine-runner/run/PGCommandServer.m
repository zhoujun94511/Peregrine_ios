#import "PGCommandServer.h"
#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

static const NSUInteger PGCommandRequestLimit = 65536;
static const NSUInteger PGCommandQueueLimit = 64;

@interface PGCommandServer ()
@property (nonatomic, assign) NSInteger port;
@property (atomic, assign) int listenSocket;
@property (nonatomic, strong) NSThread *thread;
@property (nonatomic, strong) NSLock *lock;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *pending;
@property (atomic, assign) BOOL running;
@end

@implementation PGCommandServer

- (instancetype)initWithPort:(NSInteger)port
{
    self = [super init];
    if(self != nil)
    {
        _port = port;
        _listenSocket = -1;
        _lock = [[NSLock alloc] init];
        _pending = [NSMutableArray array];
    }
    return self;
}

- (BOOL)start
{
    if(self.port <= 0 || self.running)
    {
        return NO;
    }
    if(self.port > 65535)
    {
        NSLog(@"command port %ld out of range, not listening", (long)self.port);
        return NO;
    }
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if(fd < 0)
    {
        return NO;
    }
    int yes = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_port = htons((uint16_t)self.port);
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if(bind(fd, (struct sockaddr *)&address, sizeof(address)) != 0 || listen(fd, 4) != 0)
    {
        NSLog(@"command port %ld not listening: %s", (long)self.port, strerror(errno));
        close(fd);
        return NO;
    }
    self.listenSocket = fd;
    self.running = YES;
    self.thread = [[NSThread alloc] initWithTarget:self selector:@selector(acceptLoop) object:nil];
    [self.thread start];
    return YES;
}

- (NSDictionary *)takeCommand
{
    [self.lock lock];
    NSDictionary *command = self.pending.firstObject;
    if(command != nil)
    {
        [self.pending removeObjectAtIndex:0];
    }
    [self.lock unlock];
    return command;
}

- (void)stop
{
    self.running = NO;
    int fd = self.listenSocket;
    self.listenSocket = -1;
    if(fd >= 0)
    {
        shutdown(fd, SHUT_RDWR);
        close(fd);
    }
}

- (void)acceptLoop
{
    while(self.running)
    {
        int fd = self.listenSocket;
        if(fd < 0)
        {
            break;
        }
        int client = accept(fd, NULL, NULL);
        if(client < 0)
        {
            // Errors such as EMFILE repeat at once; without a pause this loop takes a whole core.
            if(errno != EINTR && errno != ECONNABORTED && self.running)
            {
                usleep(100 * 1000);
            }
            continue;
        }
        // A client that hangs up before the reply would otherwise raise SIGPIPE and end the test run.
        int noSignal = 1;
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, sizeof(noSignal));
        @try {
            [self readClient:client];
        } @catch (NSException *exception) {
            NSLog(@"command request dropped %@", exception.reason ?: exception.name);
        }
        close(client);
    }
}

- (void)readClient:(int)client
{
    struct timeval wait = {2, 0};
    setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &wait, sizeof(wait));
    NSData *separator = [@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *data = [NSMutableData data];
    uint8_t buffer[1024];
    while(data.length < PGCommandRequestLimit)
    {
        ssize_t count = read(client, buffer, sizeof(buffer));
        if(count <= 0)
        {
            return;
        }
        [data appendBytes:buffer length:(NSUInteger)count];
        NSRange split = [data rangeOfData:separator options:0 range:NSMakeRange(0, data.length)];
        if(split.location == NSNotFound)
        {
            continue;
        }
        NSString *header = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, split.location)] encoding:NSUTF8StringEncoding];
        NSInteger length = 0;
        for(NSString *line in [header componentsSeparatedByString:@"\r\n"])
        {
            if([line.lowercaseString hasPrefix:@"content-length:"])
            {
                length = [[line substringFromIndex:@"content-length:".length] integerValue];
            }
        }
        NSUInteger bodyStart = split.location + split.length;
        if(length < 0 || bodyStart + (NSUInteger)length > PGCommandRequestLimit)
        {
            [self reply:client status:@"400 Bad Request" body:@"{\"result\":false}\n"];
            return;
        }
        if(data.length < bodyStart + (NSUInteger)length)
        {
            continue;
        }
        NSData *body = [data subdataWithRange:NSMakeRange(bodyStart, (NSUInteger)length)];
        id json = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
        BOOL queued = NO;
        if([json isKindOfClass:[NSDictionary class]])
        {
            [self.lock lock];
            if(self.pending.count < PGCommandQueueLimit)
            {
                [self.pending addObject:json];
                queued = YES;
            }
            [self.lock unlock];
        }
        [self reply:client status:queued ? @"200 OK" : @"400 Bad Request" body:queued ? @"{\"result\":true}\n" : @"{\"result\":false}\n"];
        return;
    }
    [self reply:client status:@"400 Bad Request" body:@"{\"result\":false}\n"];
}

- (void)reply:(int)client status:(NSString *)status body:(NSString *)body
{
    NSData *payload = [body dataUsingEncoding:NSUTF8StringEncoding];
    NSString *head = [NSString stringWithFormat:@"HTTP/1.1 %@\r\nContent-Type: application/json\r\nContent-Length: %lu\r\nConnection: close\r\n\r\n", status, (unsigned long)payload.length];
    NSMutableData *bytes = [[head dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    [bytes appendData:payload];
    send(client, bytes.bytes, bytes.length, 0);
}

@end
