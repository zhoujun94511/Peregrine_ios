#import <Foundation/Foundation.h>
#import "PGAnomalyTrail.h"

NS_ASSUME_NONNULL_BEGIN

// Appends one JSON object per line for a single run.
// A failed write is logged once and does not stop exploration.
@interface PGEventLog : NSObject
@property (nonatomic, copy, readonly) NSString *taskID;
@property (nonatomic, copy, readonly) NSString *filePath;
// Page of the current step, written into every event while set.
@property (nonatomic, copy, nullable) NSString *activity;
@property (nonatomic, strong, readonly) PGAnomalyTrail *anomalies;

- (instancetype)initWithDirectory:(NSString *)directory;
- (void)recordEventType:(NSString *)type fields:(nullable NSDictionary *)fields;
// Waits until queued lines have been written.
- (void)finish;
@end

NS_ASSUME_NONNULL_END
