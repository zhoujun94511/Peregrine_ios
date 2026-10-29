#import "PGBehavior.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PGCycleEscape) {
    PGCycleEscapeNone = 0,
    // Drop the edges inside the recent window and pick another action.
    PGCycleEscapeAvoid,
    PGCycleEscapeBack,
    // Tap the smallest control in a top corner, where close buttons sit.
    PGCycleEscapeCorner,
    // Drag down from the upper screen; dismisses sheets and photo viewers.
    PGCycleEscapeDismiss,
    PGCycleEscapeRestart,
};

// Alternating screens never trip the same-signature streak, and a photo viewer changes its
// pixels on every tap. 8 steps within at most 3 states with nothing new asks for a graded
// escape: 3 avoiding steps, back, corner, dismiss, restart, one plain step between them.
// A state outside the stuck set means the escape worked and the ladder starts over.
// After that restart, a later loop whose states all sit inside the restarted set waits 60
// steps before another escape. The 101-decision restart meter is separate and is not cooled.
// Named clickable controls that stay put count as one state, so a waving banner does not clear this window.
@interface PGCycleGuard : NSObject
@property (nonatomic, assign, readonly) NSInteger stepsSinceNewState;
@property (nonatomic, copy, readonly) NSArray<NSString *> *recentStateKeys;
- (PGCycleEscape)noteStateKey:(nullable NSString *)key created:(BOOL)created;
- (void)reset;
// The RESTART returned this step ran. Starts the 60-step cooldown for its stuck set.
- (void)confirmRestartIssued;
@end

// Same screen for 4 steps: swipe up. If that screen is still here, the next step forces back, then
// restart (forcing back is the last step when restart is not allowed). If the screen is still there
// after the last step, recovery leaves that screen to the model for the rest of the run.
// A restart that leaves the screen cools that fingerprint for 60 steps, so coming straight back
// does not swipe, force back, or kill the app again.
// A moving picture changes the pixel hash every step. When at least four clickable nodes have
// identifiers, the signature is those identifiers. One node appearing or disappearing keeps it.
@interface PGBlockRecovery : NSObject
- (BOOL)matchesSignature:(NSString *)signature;
- (nullable PGOperate *)noteSignature:(NSString *)signature allowsRestart:(BOOL)allowsRestart;
// The RESTART returned this step ran. The cooldown starts once a later step leaves that screen.
- (void)confirmRestartIssued;
// The fingerprint is the step's screen hash (screenshot pixels, or the stub tree); the activity is
// used only when there is none. In combined mode one screen reports the bundle ID on screenshot
// steps and the page name on corrected steps, so mixing the activity in would reset the streak.
// Node paths are only index paths and would make every screen with the same node count match.
+ (NSString *)signatureForActivity:(nullable NSString *)activity fingerprint:(uint64_t)fingerprint;
// Identified clickable controls. Empty identifiers are left out, so an unlabeled animation frame
// does not change the set. Too few identified controls returns nil and the caller keeps the fingerprint.
+ (NSSet<NSString *> *)controlKeysInNodes:(nullable NSArray<PGElementNode *> *)nodes;
+ (nullable NSString *)controlSignatureForKeys:(nullable NSSet<NSString *> *)keys
                                        anchor:(nullable NSSet<NSString *> *)anchor
                                      keptKeys:(NSSet<NSString *> * _Nullable * _Nullable)keptKeys;
// Uses the control signature while it exists, and the fingerprint otherwise.
- (NSString *)signatureForNodes:(nullable NSArray<PGElementNode *> *)nodes
                    fingerprint:(uint64_t)fingerprint
                       activity:(nullable NSString *)activity;
@end

NS_ASSUME_NONNULL_END
