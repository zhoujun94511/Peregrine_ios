#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Counts suspected crashes, action timeouts, and foreground losses from the event stream.
// Each suspected crash or timeout is logged as a "peregrine anomaly" line followed by the
// steps before it; tools/crash/collect.py matches those lines to the device crash reports.
@interface PGAnomalyTrail : NSObject
- (void)noteEvent:(NSDictionary *)event;
// {"anomalies": {kind: count}} for task_end.
- (NSDictionary *)fields;
- (NSString *)line;
@end

NS_ASSUME_NONNULL_END
