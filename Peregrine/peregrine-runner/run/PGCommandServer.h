#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Accepts JSON commands on http://127.0.0.1:<port>/ and returns them in arrival order.
// The body is an operate dictionary: act, pos, id, text, path.
// Requests are capped at 64 KB and the queue at 64 commands; anything else gets 400.
// Ports outside 1-65535 are not opened.
@interface PGCommandServer : NSObject
- (instancetype)initWithPort:(NSInteger)port;
- (BOOL)start;
- (nullable NSDictionary *)takeCommand;
- (void)stop;
@end

NS_ASSUME_NONNULL_END
