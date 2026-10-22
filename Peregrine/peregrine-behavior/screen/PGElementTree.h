#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef struct {
    NSInteger left;
    NSInteger top;
    NSInteger width;
    NSInteger height;
} PGElementRect;

@interface PGElementNode : NSObject
@property (nonatomic, copy) NSString *type;
@property (nonatomic, assign) PGElementRect rect;
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *label;
@property (nonatomic, copy) NSString *value;
@property (nonatomic, copy) NSString *controller;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, assign) BOOL visible;
@property (nonatomic, assign) BOOL interactive;
@property (nonatomic, assign) BOOL scrollable;
@property (nonatomic, assign) BOOL clickable;
@property (nonatomic, copy) NSArray<PGElementNode *> *children;

+ (NSArray<PGElementNode *> *)nodesFromResult:(nullable id)result;
+ (void)assignPaths:(NSArray<PGElementNode *> *)nodes parentPath:(nullable NSString *)parent;
- (uint64_t)structureHashMixingIndex:(BOOL)mixIndex;
// Every node in depth-first order, parents before children. Flat input comes back unchanged.
+ (NSArray<PGElementNode *> *)flattenedNodes:(NSArray<PGElementNode *> *)nodes;
// Structure hash over all roots. Never 0, because 0 means "no fingerprint" to the gates.
+ (uint64_t)fingerprintOfNodes:(NSArray<PGElementNode *> *)nodes;

// Query is "Type" or "Type_index". An index selects one match.
// TableView and CollectionView queries name a list container. Matching stays by type.
+ (BOOL)queryNamesListContainer:(NSString *)query;
+ (NSArray<PGElementNode *> *)nodesMatchingQuery:(NSString *)query inNodes:(NSArray<PGElementNode *> *)nodes;
- (NSArray<PGElementNode *> *)nodesMatchingQuery:(NSString *)query;
- (NSString *)firstController;
// Deepest controller that is the screen itself. Skips navigation, tabs, and keyboard chrome.
// Later children are drawn on top, so they are searched first: a presented sheet wins
// over the screen still laid out beneath it.
- (NSString *)contentController;
+ (NSArray<PGElementNode *> *)combinedChildrenOfNodes:(NSArray<PGElementNode *> *)nodes;
+ (nullable PGElementNode *)nodeInNodes:(NSArray<PGElementNode *> *)nodes
                   matchingIdentifier:(nullable NSString *)identifier
                                 text:(nullable NSString *)text;
@end

NS_ASSUME_NONNULL_END
