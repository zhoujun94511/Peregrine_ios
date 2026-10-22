#import <Foundation/Foundation.h>
#import "PGBehavior.h"

NS_ASSUME_NONNULL_BEGIN

@interface PGState : NSObject
@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy) NSString *activity;
@property (nonatomic, assign) NSInteger visits;
@end

@interface PGTransition : NSObject
@property (nonatomic, strong) PGState *from;
@property (nonatomic, strong) PGState *to;
@property (nonatomic, copy) NSString *actionID;
@end

@interface PGGraph : NSObject
@property (nonatomic, strong, readonly) NSArray<PGState *> *states;
@property (nonatomic, strong, readonly) NSArray<PGTransition *> *transitions;
// Incremented each time a screen is resolved. N-step Q uses it to choose the learning rate.
@property (nonatomic, assign, readonly) NSInteger observationCount;

- (PGState *)stateForNodes:(NSArray<PGElementNode *> *)nodes
                  activity:(nullable NSString *)activity
                   created:(BOOL * _Nullable)created;
- (nullable PGTransition *)transitionFrom:(PGState *)from
                                 actionID:(NSString *)actionID
                                       to:(PGState *)to;
- (PGTransition *)addTransitionFrom:(PGState *)from
                           actionID:(NSString *)actionID
                                 to:(PGState *)to;
// Actions whose edge stays inside the given state keys.
- (NSSet<NSString *> *)actionIDsTouchingStateKeys:(NSSet<NSString *> *)keys;
@end

NS_ASSUME_NONNULL_END
