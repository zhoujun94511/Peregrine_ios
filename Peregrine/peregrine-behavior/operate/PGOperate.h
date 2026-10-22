#import "PGElementTree.h"

NS_ASSUME_NONNULL_BEGIN

@interface PGOperate : NSObject
@property (nonatomic, copy) NSString *act;
@property (nonatomic, assign) PGElementRect rect;
@property (nonatomic, copy) NSString *stateID;
@property (nonatomic, copy) NSString *actionID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy, nullable) NSString *queryIdentifier;
@property (nonatomic, copy, nullable) NSString *queryText;
@property (nonatomic, copy, nullable) NSArray<NSDictionary *> *path;
@property (nonatomic, assign) NSInteger waitTime;
@property (nonatomic, assign) double throttle;

- (NSDictionary *)dictionary;
- (NSString *)jsonString;
+ (PGOperate *)restart;
+ (PGOperate *)clickOnNode:(PGElementNode *)node;
+ (nullable PGOperate *)operateFromDictionary:(nullable NSDictionary *)json;
// Accepts {"act","pos","id","text","path"} JSON or a bare act name such as HOME.
+ (nullable PGOperate *)operateFromCommand:(nullable NSString *)command;
@end

NS_ASSUME_NONNULL_END
