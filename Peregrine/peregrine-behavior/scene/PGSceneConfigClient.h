#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Loads a scene list from a URL. A failed request returns nil so the caller keeps the local list.
@interface PGSceneConfigClient : NSObject
+ (nullable NSArray *)scenesFromURL:(NSString *)urlString timeout:(NSTimeInterval)timeout;
@end

NS_ASSUME_NONNULL_END
