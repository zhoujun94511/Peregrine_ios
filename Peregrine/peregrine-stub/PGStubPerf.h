#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Resource sample of the host app, answered off the main thread.
// The main-thread watch starts at launch when the runner sets stubPerf=1, otherwise with the first
// sample, and stops 10 seconds after the last one, so an app that is not being asked pays nothing.
// main_max_ms, main_slow and memory_warnings cover the time since the previous sample; memory warnings
// are counted from the first startWatch or sample on.
@interface PGStubPerf : NSObject
+ (instancetype)shared;
- (void)startWatch;
// {footprint_bytes, cpu_percent, threads, main_max_ms, main_slow, memory_warnings, thermal_state}
// thermal_state is nominal, fair, serious or critical.
- (NSDictionary *)sample;
@end

NS_ASSUME_NONNULL_END
