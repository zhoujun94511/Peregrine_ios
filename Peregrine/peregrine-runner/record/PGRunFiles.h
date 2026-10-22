#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// A new run moves the previous run's outputs into peregrine-previous and drops the run before that,
// so a run whose pull failed can still be pulled once the next run has started.
// The reuse model is not a per-run output and stays.
@interface PGRunFiles : NSObject
+ (void)keepPreviousRunInDirectory:(NSString *)directory;
@end

NS_ASSUME_NONNULL_END
