#import <Foundation/Foundation.h>
#import "PGStubClient.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PGStubTreeVerdict) {
    PGStubTreeKeep,
    // The stub answered a probe after an empty tree; fetch the tree again.
    PGStubTreeRetry,
    // The stub is given up for the rest of the run.
    PGStubTreeLost,
};

// Whether the stub's view tree is the screen source for this run.
// The launch probe decides first. The first empty tree of a streak triggers a
// 4-second probe, which covers the stub's 2-second start after an app restart.
// After 5 empty trees in a row another probe runs; if it fails, the stub is lost.
// At launch the stub must report the app under test through app_info; a stub that
// reports another bundle or cannot provide app_info is not used.
@interface PGStubWatch : NSObject
@property (nonatomic, readonly) BOOL alive;
- (instancetype)initWithClient:(PGStubClient *)client port:(NSInteger)port bundleID:(NSString *)bundleID;
- (BOOL)probeAtLaunch;
- (PGStubTreeVerdict)noteTree:(nullable NSArray *)tree;
@end

NS_ASSUME_NONNULL_END
