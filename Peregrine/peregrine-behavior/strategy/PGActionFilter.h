#import "PGBehavior.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PGActionFilterKind) {
    PGActionFilterAll = 0,
    PGActionFilterValid,
    PGActionFilterEnabled,
    PGActionFilterUnvisited,
};

// Decides whether a node can be chosen, and which type is preferred.
// Enabled means visible, a positive size, and clickable or interactive.
// Unvisited also requires a visit count below 1.
@interface PGActionFilter : NSObject
+ (BOOL)includeNode:(PGElementNode *)node kind:(PGActionFilterKind)kind visits:(NSInteger)visits;
+ (BOOL)includeNode:(PGElementNode *)node
               kind:(PGActionFilterKind)kind
             visits:(NSInteger)visits
             target:(nullable NSString *)target;
+ (NSInteger)priorityForNode:(PGElementNode *)node;
@end

NS_ASSUME_NONNULL_END
