#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Posts scene enter and exit when a callback URL is configured.
// Posts go out one at a time, so the server sees them in the order they happened.
@interface PGSceneCallback : NSObject
@property (nonatomic, assign, readonly) BOOL inside;
- (instancetype)initWithURL:(nullable NSString *)url;
- (void)enteredScheme:(nullable NSString *)scheme allow:(NSArray *)allow block:(NSArray *)block;
- (void)exitedScheme:(nullable NSString *)scheme;
// Posts exit if still inside, then waits up to `seconds` for queued posts to finish.
- (void)finishWithin:(NSTimeInterval)seconds;
@end

NS_ASSUME_NONNULL_END
