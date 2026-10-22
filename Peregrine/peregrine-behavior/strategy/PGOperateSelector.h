#import <CoreGraphics/CoreGraphics.h>
#import "PGOperate.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PGAgentKind) {
    PGAgentKindUnspecified = 0,
    PGAgentKindSataRL = 1,
    PGAgentKindNStepQ = 3,
};

@class PGReuseModel;
@class PGGestureMix;

@interface PGOperateSelector : NSObject
@property (nonatomic, assign) PGAgentKind kind;
// SataRL explores when a random unit value is below this. 0 keeps every pick greedy.
@property (nonatomic, assign) double epsilon;
// The reward updates the oldest action in a five-step window.
// A learning rate of 0 selects 0.5 down to 0.25 from graphObservations.
@property (nonatomic, assign) double learningRate;
// Bootstrap factor for that window. 0.8 matches the reusable Android agent.
@property (nonatomic, assign) double discount;
@property (nonatomic, assign) NSInteger graphObservations;
@property (nonatomic, assign, readonly) NSInteger storedStepCount;
// When set, only nodes whose id, label, value, or type contain this text stay eligible.
@property (nonatomic, copy, nullable) NSString *target;
// Chance of a random pick after every eligible action has been tried. 0 keeps that branch greedy.
@property (nonatomic, assign) double stallExploration;
// One string per entry. An empty text field uses a random entry. Nil keeps "peregrine".
@property (nonatomic, copy, nullable) NSArray<NSString *> *inputTexts;
@property (nonatomic, strong, nullable) PGReuseModel *reuseModel;
@property (nonatomic, copy, nullable) NSSet<NSString *> *seenActivities;
// Nil keeps every chosen node a tap, with lists swiped up.
@property (nonatomic, strong, nullable) PGGestureMix *gestures;
// Coordinate space of the nodes: screenshot pixels or screen points. Screen gestures and corners need it.
@property (nonatomic, assign) CGSize space;

- (instancetype)initWithKind:(PGAgentKind)kind;
- (double)reuseRewardForNodes:(NSArray<PGElementNode *> *)nodes stateVisits:(NSInteger)stateVisits;
- (void)absorbReward:(double)reward;
// Drops the latest action; if its reward has not arrived yet it also leaves the n-step window.
- (void)forgetLatestAction;
// Empties the n-step window so a restart does not chain rewards across sessions.
- (void)resetLearningWindow;
- (void)blacklistActionID:(nullable NSString *)actionID;
- (void)clearBlockedActions;
- (void)decayActionValues:(double)factor;
- (PGOperate *)operateForNodes:(NSArray<PGElementNode *> *)roots
                      activity:(nullable NSString *)activity
                        reward:(double)reward;
- (PGOperate *)operateForNodes:(NSArray<PGElementNode *> *)roots
                      activity:(nullable NSString *)activity
                        reward:(double)reward
                      avoiding:(nullable NSSet<NSString *> *)banned
                   forceRandom:(BOOL)forceRandom;
// Smallest operable node in a top corner, or nil when none sits there.
- (nullable PGOperate *)cornerOperateForNodes:(NSArray<PGElementNode *> *)roots activity:(nullable NSString *)activity;
@end

NS_ASSUME_NONNULL_END
