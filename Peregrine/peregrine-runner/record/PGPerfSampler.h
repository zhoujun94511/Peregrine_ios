#import <Foundation/Foundation.h>
#import "PGStubClient.h"
#import "PGEventLog.h"

NS_ASSUME_NONNULL_BEGIN

// Asks the stub for a resource sample after a step and writes it as a perf event.
// Runs only while the stub is the screen source; without the stub there is nothing to ask.
// Samples are at least 1 second apart, and a missing reply never holds up the step for more than 1 second.
@interface PGPerfSampler : NSObject
- (instancetype)initWithEnabled:(BOOL)enabled client:(PGStubClient *)client port:(NSInteger)port log:(PGEventLog *)log;
- (void)sampleWithStubAlive:(BOOL)stubAlive;
// perf samples <n> peak_mb <x> peak_sample <n> main_max_ms <n> main_slow <n> memory_warnings <n> thermal_max <state|none> missed <n>
- (nullable NSString *)line;
// {"perf": {samples, peak_bytes, peak_sample, main_max_ms, main_slow, memory_warnings, thermal_max, missed}} for task_end;
// empty when sampling is off. thermal_max is empty when no sample carried a thermal state.
- (NSDictionary *)fields;
@end

NS_ASSUME_NONNULL_END
