#import <Foundation/Foundation.h>
#import "PGElementTree.h"

NS_ASSUME_NONNULL_BEGIN

// Elements listed in appconfig.json excludeElements, matched by exact identifier or label.
// A floating element can be dragged anywhere, so its frame comes from each step instead of a fixed box.
@interface PGElementExclusion : NSObject
@property (nonatomic, copy, readonly) NSArray<NSString *> *names;
- (instancetype)initWithNames:(NSArray<NSString *> *)names;
- (BOOL)matchesNode:(PGElementNode *)node;
// Matching nodes found anywhere in the tree, children included.
- (NSArray<PGElementNode *> *)coversInNodes:(NSArray<PGElementNode *> *)nodes;
// Drops matching nodes with their children, and leaves whose center lies inside a cover.
// Covers and nodes must use the same coordinates.
- (NSArray<PGElementNode *> *)nodes:(NSArray<PGElementNode *> *)nodes clearOfCovers:(NSArray<PGElementNode *> *)covers;
@end

NS_ASSUME_NONNULL_END
