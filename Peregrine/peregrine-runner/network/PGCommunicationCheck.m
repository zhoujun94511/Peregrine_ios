#import "PGCommunicationCheck.h"
#import "PGCommandServer.h"
#import "PGConfig.h"
#import "PGEnvironment.h"
#import "PGNetworkProbe.h"
#import "PGSession.h"
#import "PGStubClient.h"
#import "PGStubWatch.h"
#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

static NSString *PGInternetName(PGInternetStatus status)
{
    switch(status)
    {
        case PGInternetStatusReachable: return @"reachable";
        case PGInternetStatusDenied: return @"denied";
        case PGInternetStatusUnreachable: return @"unreachable";
    }
    return @"unknown";
}

static void PGSetSocketTimeouts(int fd)
{
    struct timeval timeout = {2, 0};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
    int noSignal = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, sizeof(noSignal));
}

static struct sockaddr_in PGLoopbackAddress(uint16_t port)
{
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_port = htons(port);
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    return address;
}

static int PGConnectLoopback(uint16_t port)
{
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if(fd < 0)
    {
        return -1;
    }
    PGSetSocketTimeouts(fd);
    struct sockaddr_in address = PGLoopbackAddress(port);
    if(connect(fd, (struct sockaddr *)&address, sizeof(address)) != 0)
    {
        close(fd);
        return -1;
    }
    return fd;
}

@implementation PGCommunicationReport

- (BOOL)passed
{
    BOOL stubPassed = self.stub == nil || self.stub.boolValue;
    BOOL internetPassed = !self.internetRequired || self.internet == PGInternetStatusReachable;
    return self.loopback && self.commandServer && stubPassed && internetPassed;
}

- (NSString *)summary
{
    NSString *stub = self.stub == nil ? @"not_configured" : (self.stub.boolValue ? @"ok" : @"failed");
    return [NSString stringWithFormat:@"communication loopback %@ | command_server %@ port %ld | stub %@ | internet %@ (%@) | %@",
            self.loopback ? @"ok" : @"failed",
            self.commandServer ? @"ok" : @"failed",
            (long)self.commandPort,
            stub,
            PGInternetName(self.internet),
            self.internetRequired ? @"required" : @"not required",
            self.passed ? @"passed" : @"failed"];
}

@end

@implementation PGCommunicationCheck

+ (PGCommunicationReport *)reportWithEnvironment:(NSDictionary *)environment
{
    PGCommunicationReport *report = [[PGCommunicationReport alloc] init];
    report.loopback = [self loopbackEcho];
    NSLog(@"loopback %@", report.loopback ? @"success" : @"failed");
    report.commandPort = [self commandPortInEnvironment:environment];
    report.commandServer = report.commandPort > 0 && [self commandServerAcceptsOnPort:report.commandPort];
    NSLog(@"command server %@ port %ld", report.commandServer ? @"success" : @"failed", (long)report.commandPort);
    PGSession *session = [PGSession sessionFromEnvironment:environment];
    if(session != nil && session.dataPort > 0)
    {
        report.stub = @([self stubAnswersForSession:session environment:environment]);
        NSLog(@"stub %@ port %ld", report.stub.boolValue ? @"success" : @"failed", (long)session.dataPort);
    }
    report.internetRequired = [self internetRequiredInEnvironment:environment];
    NSString *probeURL = [PGEnvironment stringForKey:@"PEREGRINE_NETWORK_PROBE_URL" inEnvironment:environment];
    if(report.internetRequired)
    {
        report.internet = [PGNetworkProbe probeNetworkWithURL:probeURL] ? PGInternetStatusReachable : ([PGNetworkProbe pathDenied] ? PGInternetStatusDenied : PGInternetStatusUnreachable);
    }
    else
    {
        report.internet = [self quickInternetStatusWithURL:probeURL];
    }
    if(report.internet == PGInternetStatusReachable)
    {
        NSLog(@"internet success");
    }
    else
    {
        NSLog(@"internet %@ (%@)", PGInternetName(report.internet), report.internetRequired ? @"required" : @"not required");
    }
    if(report.internet == PGInternetStatusDenied)
    {
        NSLog(@"the system denies this runner wireless data; exploration, the command port and the stub use 127.0.0.1 and are not affected");
    }
    return report;
}

// A TCP round trip over 127.0.0.1, the interface the command port and the stub use.
+ (BOOL)loopbackEcho
{
    int server = socket(AF_INET, SOCK_STREAM, 0);
    if(server < 0)
    {
        return NO;
    }
    struct sockaddr_in address = PGLoopbackAddress(0);
    socklen_t length = sizeof(address);
    BOOL ok = bind(server, (struct sockaddr *)&address, sizeof(address)) == 0
        && listen(server, 1) == 0
        && getsockname(server, (struct sockaddr *)&address, &length) == 0;
    int client = ok ? PGConnectLoopback(ntohs(address.sin_port)) : -1;
    int peer = client >= 0 ? accept(server, NULL, NULL) : -1;
    if(peer >= 0)
    {
        PGSetSocketTimeouts(peer);
        char buffer[16] = {0};
        ok = send(client, "ping", 4, 0) == 4
            && recv(peer, buffer, sizeof(buffer), 0) == 4 && memcmp(buffer, "ping", 4) == 0
            && send(peer, "pong", 4, 0) == 4
            && recv(client, buffer, sizeof(buffer), 0) == 4 && memcmp(buffer, "pong", 4) == 0;
    }
    else
    {
        ok = NO;
    }
    if(!ok)
    {
        NSLog(@"loopback round trip failed errno=%d(%s)", errno, strerror(errno));
    }
    if(peer >= 0) close(peer);
    if(client >= 0) close(client);
    close(server);
    return ok;
}

+ (NSInteger)commandPortInEnvironment:(NSDictionary *)environment
{
    id value = environment[@"PEREGRINE_COMMAND_PORT"];
    NSInteger port = [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : 0;
    if(port > 0 && port <= 65535)
    {
        return port;
    }
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if(fd < 0)
    {
        return 0;
    }
    struct sockaddr_in address = PGLoopbackAddress(0);
    socklen_t length = sizeof(address);
    NSInteger free = 0;
    if(bind(fd, (struct sockaddr *)&address, sizeof(address)) == 0 && getsockname(fd, (struct sockaddr *)&address, &length) == 0)
    {
        free = ntohs(address.sin_port);
    }
    close(fd);
    return free;
}

// Runs the real command server and posts one command to it, as iproxy would deliver it.
+ (BOOL)commandServerAcceptsOnPort:(NSInteger)port
{
    PGCommandServer *server = [[PGCommandServer alloc] initWithPort:port];
    if(![server start])
    {
        return NO;
    }
    BOOL ok = NO;
    int fd = PGConnectLoopback((uint16_t)port);
    if(fd >= 0)
    {
        NSString *body = @"{\"act\":\"BACK\"}";
        NSString *request = [NSString stringWithFormat:@"POST / HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: %lu\r\n\r\n%@", (unsigned long)body.length, body];
        NSData *bytes = [request dataUsingEncoding:NSUTF8StringEncoding];
        NSMutableData *reply = [NSMutableData data];
        if(send(fd, bytes.bytes, bytes.length, 0) == (ssize_t)bytes.length)
        {
            char buffer[512];
            ssize_t count = 0;
            while((count = recv(fd, buffer, sizeof(buffer), 0)) > 0)
            {
                [reply appendBytes:buffer length:(NSUInteger)count];
            }
        }
        close(fd);
        NSString *text = [[NSString alloc] initWithData:reply encoding:NSUTF8StringEncoding] ?: @"";
        NSDictionary *command = [server takeCommand];
        ok = [text hasPrefix:@"HTTP/1.1 200"] && [command[@"act"] isEqual:@"BACK"];
        if(!ok)
        {
            NSLog(@"command server reply %@ queued %@", [text componentsSeparatedByString:@"\r\n"].firstObject ?: @"", command ?: @"nothing");
        }
    }
    [server stop];
    return ok;
}

+ (BOOL)stubAnswersForSession:(PGSession *)session environment:(NSDictionary *)environment
{
    NSMutableDictionary *launchEnvironment = [[PGSession launchEnvironmentFromEncoded:environment[@"PEREGRINE_LAUNCHENV"]] mutableCopy];
    if(launchEnvironment[@"stubPort"] == nil)
    {
        launchEnvironment[@"stubPort"] = [NSString stringWithFormat:@"%ld", (long)session.dataPort];
    }
    XCUIApplication *app = [[XCUIApplication alloc] initWithBundleIdentifier:session.bundleID];
    app.launchEnvironment = launchEnvironment;
    [app launch];
    PGStubWatch *watch = [[PGStubWatch alloc] initWithClient:[[PGStubClient alloc] init] port:session.dataPort bundleID:session.bundleID];
    BOOL alive = [watch probeAtLaunch];
    [app terminate];
    return alive;
}

+ (BOOL)internetRequiredInEnvironment:(NSDictionary *)environment
{
    if([[PGEnvironment stringForKey:@"PEREGRINE_REQUIRE_INTERNET" inEnvironment:environment] isEqualToString:@"1"])
    {
        return YES;
    }
    PGConfig *config = [PGConfig loadedConfig];
    if(config.sceneConfigURL.length > 0 || config.sceneCallbackURL.length > 0)
    {
        return YES;
    }
    for(NSString *key in @[@"SCENE_CONFIG_URL", @"SCENE_CALLBACK"])
    {
        if([PGEnvironment stringForKey:key inEnvironment:environment].length > 0)
        {
            return YES;
        }
    }
    return NO;
}

// One request without the permission-dialog loop: a denied path is reported, not waited out.
+ (PGInternetStatus)quickInternetStatusWithURL:(NSString *)urlString
{
    if([PGNetworkProbe pathDenied])
    {
        return PGInternetStatusDenied;
    }
    NSString *failure = nil;
    if([PGNetworkProbe requestPingURL:urlString failure:&failure])
    {
        return PGInternetStatusReachable;
    }
    NSLog(@"ping network failed %@", failure);
    return PGInternetStatusUnreachable;
}

@end
