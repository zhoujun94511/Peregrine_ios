#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@class PGElementNode;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PGPreferenceDecisionKind) {
    PGPreferenceDecisionNone = 0,
    PGPreferenceDecisionCommand,
    PGPreferenceDecisionSuppressModel,
};

@interface PGPreferenceDecision : NSObject
@property (nonatomic, assign) PGPreferenceDecisionKind kind;
@property (nonatomic, copy, nullable) NSString *command;
@end

// Events and named actions come from default.jsonsetting.
// A matching event with NO_CLICK suppresses the model for that step.
// A matching event with other commands is used before model selection.
@interface PGPreference : NSObject
- (void)addCommand:(NSString *)command matchingText:(NSString *)text;
- (void)loadEvents:(NSArray *)events actions:(NSArray *)actions;
- (void)loadSequences:(NSArray *)sequences;
- (nullable NSString *)commandMatchingScreenText:(nullable NSString *)screenText;
- (PGPreferenceDecision *)decisionForNodes:(NSArray<PGElementNode *> *)nodes
                                 activity:(nullable NSString *)activity
                               screenSize:(CGSize)screenSize;
@end

NS_ASSUME_NONNULL_END
