#import <XCTest/XCTest.h>
#import "PGBehavior.h"
#import "PGModel.h"
#import "PGPreference.h"
#import "PGStubClient.h"
#import "PGSegmentation.h"
#import "PGSession.h"
#import "PGConfig.h"

NS_ASSUME_NONNULL_BEGIN

// Turns the current tree into one operate. The session loop does not choose inside itself.
@interface PGOperateChoice : NSObject
+ (NSString *)activityInNodes:(NSArray<PGElementNode *> *)nodes;
// Waits at most 5 seconds; an empty array means no tree this step.
+ (NSArray *)treeFromClient:(PGStubClient *)client port:(NSInteger)port;
+ (PGOperate *)operateForNodes:(NSArray<PGElementNode *> *)nodes
                          tree:(NSString *)treeText
                         cycle:(PGActionCycle *)cycle
                         model:(PGModel *)model
                    preference:(PGPreference *)preference
                       session:(PGSession *)session
                      activity:(NSString *)activity
                  actionSource:(NSUInteger)actionSource
                        screen:(CGSize)screen;
+ (PGOperate *)operateForScreenshotNodes:(NSArray<PGElementNode *> *)nodes
                                   model:(PGModel *)model
                              preference:(PGPreference *)preference
                                activity:(NSString *)activity
                                  pixels:(CGSize)pixels
                                  screen:(CGSize)screen;
@end

NS_ASSUME_NONNULL_END
