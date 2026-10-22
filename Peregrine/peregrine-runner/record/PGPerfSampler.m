#import "PGPerfSampler.h"

static const NSTimeInterval PGPerfIntervalSeconds = 1;
static const NSTimeInterval PGPerfWaitSeconds = 1;

static NSInteger PGThermalRank(NSString *state)
{
    NSUInteger rank = [@[@"nominal", @"fair", @"serious", @"critical"] indexOfObject:state ?: @""];
    return rank == NSNotFound ? -1 : (NSInteger)rank;
}

@implementation PGPerfSampler
{
    BOOL _enabled;
    PGStubClient *_client;
    NSInteger _port;
    PGEventLog *_log;
    NSDate *_lastSample;
    NSInteger _samples;
    NSInteger _missed;
    uint64_t _peakBytes;
    NSInteger _peakSample;
    NSInteger _mainMaxMillis;
    NSInteger _mainSlow;
    NSInteger _memoryWarnings;
    NSString *_thermalMax;
}

- (instancetype)initWithEnabled:(BOOL)enabled client:(PGStubClient *)client port:(NSInteger)port log:(PGEventLog *)log
{
    self = [super init];
    if(self != nil)
    {
        _enabled = enabled && port > 0;
        _client = client;
        _port = port;
        _log = log;
        _thermalMax = @"";
        if(_enabled)
        {
            NSLog(@"perf sampling on port %ld", (long)port);
        }
    }
    return self;
}

- (void)sampleWithStubAlive:(BOOL)stubAlive
{
    if(!_enabled || !stubAlive)
    {
        return;
    }
    if(_lastSample != nil && [[NSDate date] timeIntervalSinceDate:_lastSample] < PGPerfIntervalSeconds)
    {
        return;
    }
    _lastSample = [NSDate date];
    dispatch_semaphore_t gate = dispatch_semaphore_create(0);
    __block NSDictionary *sample = nil;
    [_client fetchPerfOnPort:_port completion:^(NSDictionary *result) {
        sample = result;
        dispatch_semaphore_signal(gate);
    }];
    if(dispatch_semaphore_wait(gate, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(PGPerfWaitSeconds * NSEC_PER_SEC))) != 0 || sample == nil)
    {
        _missed += 1;
        return;
    }
    _samples += 1;
    uint64_t bytes = [sample[@"footprint_bytes"] unsignedLongLongValue];
    if(bytes > _peakBytes)
    {
        _peakBytes = bytes;
        _peakSample = _samples;
    }
    _mainMaxMillis = MAX(_mainMaxMillis, [sample[@"main_max_ms"] integerValue]);
    _mainSlow += [sample[@"main_slow"] integerValue];
    _memoryWarnings += [sample[@"memory_warnings"] integerValue];
    id thermal = sample[@"thermal_state"];
    if([thermal isKindOfClass:[NSString class]] && PGThermalRank(thermal) > PGThermalRank(_thermalMax))
    {
        _thermalMax = thermal;
    }
    NSMutableDictionary *record = [sample mutableCopy];
    id cpu = sample[@"cpu_percent"];
    if([cpu isKindOfClass:[NSNumber class]])
    {
        // The stub sends one decimal, but parsing turns it into a double that serializes as 6.4000000000000004.
        record[@"cpu_percent"] = [NSDecimalNumber decimalNumberWithString:[NSString stringWithFormat:@"%.1f", [cpu doubleValue]]
                                                                    locale:@{NSLocaleDecimalSeparator: @"."}];
    }
    [_log recordEventType:@"perf" fields:@{@"perf": record}];
}

- (NSString *)line
{
    if(!_enabled)
    {
        return nil;
    }
    return [NSString stringWithFormat:@"perf samples %ld peak_mb %.1f peak_sample %ld main_max_ms %ld main_slow %ld memory_warnings %ld thermal_max %@ missed %ld",
            (long)_samples, _peakBytes / 1048576.0, (long)_peakSample, (long)_mainMaxMillis, (long)_mainSlow,
            (long)_memoryWarnings, _thermalMax.length > 0 ? _thermalMax : @"none", (long)_missed];
}

- (NSDictionary *)fields
{
    if(!_enabled)
    {
        return @{};
    }
    return @{@"perf": @{
        @"samples": @(_samples),
        @"peak_bytes": @(_peakBytes),
        @"peak_sample": @(_peakSample),
        @"main_max_ms": @(_mainMaxMillis),
        @"main_slow": @(_mainSlow),
        @"memory_warnings": @(_memoryWarnings),
        @"thermal_max": _thermalMax,
        @"missed": @(_missed)
    }};
}

@end
