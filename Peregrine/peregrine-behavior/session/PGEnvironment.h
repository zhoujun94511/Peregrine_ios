#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Reads one test environment value. An empty value or an unexpanded
// ${...} scheme placeholder counts as unset.
@interface PGEnvironment : NSObject
+ (nullable NSString *)stringForKey:(NSString *)key
                    inEnvironment:(nullable NSDictionary *)environment;
@end

NS_ASSUME_NONNULL_END
