#import "PGEventLog.h"

@interface PGEventLog ()
@property (nonatomic, copy, readwrite) NSString *taskID;
@property (nonatomic, copy, readwrite) NSString *filePath;
@property (nonatomic, strong, readwrite) PGAnomalyTrail *anomalies;
@property (nonatomic, copy) NSString *directory;
@property (nonatomic, strong) NSDateFormatter *timestampFormatter;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, strong) NSFileHandle *handle;
@property (nonatomic, assign) NSInteger sequence;
@property (nonatomic, assign) BOOL reportedFailure;
@end

@implementation PGEventLog

- (instancetype)initWithDirectory:(NSString *)directory
{
    self = [super init];
    if(self != nil)
    {
        _directory = directory.length > 0 ? [directory copy] : [NSTemporaryDirectory() copy];
        _filePath = [_directory stringByAppendingPathComponent:@"peregrine-events.jsonl"];
        _queue = dispatch_queue_create("com.peregrine.eventlog", DISPATCH_QUEUE_SERIAL);
        _anomalies = [[PGAnomalyTrail alloc] init];
        _timestampFormatter = [[NSDateFormatter alloc] init];
        _timestampFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        _timestampFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        _timestampFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
        NSDateFormatter *identifierFormatter = [[NSDateFormatter alloc] init];
        identifierFormatter.locale = _timestampFormatter.locale;
        identifierFormatter.timeZone = _timestampFormatter.timeZone;
        identifierFormatter.dateFormat = @"yyyyMMdd_HHmmss";
        _taskID = [NSString stringWithFormat:@"run_%@", [identifierFormatter stringFromDate:[NSDate date]]];
    }
    return self;
}

- (void)recordEventType:(NSString *)type fields:(NSDictionary *)fields
{
    self.sequence += 1;
    NSMutableDictionary *event = [@{
        @"schema_version": @1,
        @"task_id": self.taskID ?: @"",
        @"event_type": type ?: @"",
        @"timestamp": [self.timestampFormatter stringFromDate:[NSDate date]] ?: @"",
        @"sequence": @(self.sequence)
    } mutableCopy];
    if(self.activity.length > 0)
    {
        event[@"activity"] = self.activity;
    }
    [fields enumerateKeysAndObjectsUsingBlock:^(id key, id object, BOOL *stop) {
        if([key isKindOfClass:[NSString class]] && object != nil)
        {
            event[key] = object;
        }
    }];
    [self.anomalies noteEvent:event];
    if(![NSJSONSerialization isValidJSONObject:event])
    {
        return;
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:event options:0 error:nil];
    if(data == nil)
    {
        return;
    }
    NSString *line = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] stringByAppendingString:@"\n"];
    if(line.length == 0)
    {
        return;
    }
    // Written before returning, so a runner crash keeps every event up to the crash.
    dispatch_sync(self.queue, ^{
        [self appendLine:line];
    });
}

- (void)finish
{
    dispatch_sync(self.queue, ^{
        [self.handle synchronizeFile];
    });
}

- (void)appendLine:(NSString *)line
{
    if(self.handle == nil)
    {
        NSError *error = nil;
        [[NSFileManager defaultManager] createDirectoryAtPath:self.directory
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:&error];
        if(![[NSFileManager defaultManager] fileExistsAtPath:self.filePath])
        {
            [[NSFileManager defaultManager] createFileAtPath:self.filePath contents:nil attributes:nil];
        }
        self.handle = [NSFileHandle fileHandleForWritingAtPath:self.filePath];
        [self.handle seekToEndOfFile];
        if(self.handle == nil && !self.reportedFailure)
        {
            self.reportedFailure = YES;
            NSLog(@"event log write failed: %@", error.localizedDescription ?: self.filePath);
            return;
        }
    }
    @try
    {
        [self.handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    }
    @catch(NSException *exception)
    {
        if(!self.reportedFailure)
        {
            self.reportedFailure = YES;
            NSLog(@"event log write failed: %@", exception.reason);
        }
    }
}

@end
