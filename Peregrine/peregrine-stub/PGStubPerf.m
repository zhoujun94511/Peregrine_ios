#import "PGStubPerf.h"
#import <mach/mach.h>

static const NSTimeInterval PGStubPerfPingSeconds = 0.1;
static const double PGStubPerfSlowMillis = 250;
static const NSTimeInterval PGStubPerfIdleSeconds = 10;
// Value of UIApplicationDidReceiveMemoryWarningNotification; the stub does not link UIKit.
static NSString * const PGStubMemoryWarning = @"UIApplicationDidReceiveMemoryWarningNotification";

@implementation PGStubPerf
{
    dispatch_queue_t _queue;
    dispatch_source_t _timer;
    CFAbsoluteTime _pingSent;
    CFAbsoluteTime _sampled;
    BOOL _pingPending;
    double _maxMillis;
    NSInteger _slowCount;
    NSInteger _memoryWarnings;
}

+ (instancetype)shared
{
    static PGStubPerf *perf = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        perf = [[PGStubPerf alloc] init];
    });
    return perf;
}

- (instancetype)init
{
    self = [super init];
    if(self != nil)
    {
        _queue = dispatch_queue_create("peregrine.stub.perf", DISPATCH_QUEUE_SERIAL);
        __weak typeof(self) weakSelf = self;
        [[NSNotificationCenter defaultCenter] addObserverForName:PGStubMemoryWarning object:nil queue:nil usingBlock:^(NSNotification *note) {
            PGStubPerf *strongSelf = weakSelf;
            if(strongSelf == nil)
            {
                return;
            }
            dispatch_async(strongSelf->_queue, ^{
                strongSelf->_memoryWarnings += 1;
            });
        }];
    }
    return self;
}

- (void)startWatch
{
    dispatch_async(_queue, ^{
        self->_sampled = CFAbsoluteTimeGetCurrent();
        [self startWatchIfNeeded];
    });
}

- (NSDictionary *)sample
{
    __block double maxMillis = 0;
    __block NSInteger slowCount = 0;
    __block NSInteger memoryWarnings = 0;
    dispatch_sync(_queue, ^{
        [self startWatchIfNeeded];
        self->_sampled = CFAbsoluteTimeGetCurrent();
        double pending = self->_pingPending ? (CFAbsoluteTimeGetCurrent() - self->_pingSent) * 1000.0 : 0;
        maxMillis = MAX(self->_maxMillis, pending);
        slowCount = self->_slowCount;
        memoryWarnings = self->_memoryWarnings;
        self->_maxMillis = 0;
        self->_slowCount = 0;
        self->_memoryWarnings = 0;
    });
    NSInteger threads = 0;
    double cpu = [self cpuPercentThreads:&threads];
    return @{
        @"footprint_bytes": @([self footprintBytes]),
        @"cpu_percent": [NSDecimalNumber decimalNumberWithMantissa:(unsigned long long)llround(cpu * 10) exponent:-1 isNegative:NO],
        @"threads": @(threads),
        @"main_max_ms": @((NSInteger)round(maxMillis)),
        @"main_slow": @(slowCount),
        @"memory_warnings": @(memoryWarnings),
        @"thermal_state": [self thermalStateName]
    };
}

- (NSString *)thermalStateName
{
    switch([NSProcessInfo processInfo].thermalState)
    {
        case NSProcessInfoThermalStateFair:
            return @"fair";
        case NSProcessInfoThermalStateSerious:
            return @"serious";
        case NSProcessInfoThermalStateCritical:
            return @"critical";
        default:
            return @"nominal";
    }
}

- (void)startWatchIfNeeded
{
    if(_timer != nil)
    {
        return;
    }
    _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _queue);
    uint64_t interval = (uint64_t)(PGStubPerfPingSeconds * NSEC_PER_SEC);
    dispatch_source_set_timer(_timer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)interval), interval, interval / 10);
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_timer, ^{
        [weakSelf ping];
    });
    dispatch_resume(_timer);
}

// One ping is in flight at a time, so a stuck main thread does not pile up blocks.
- (void)ping
{
    if(CFAbsoluteTimeGetCurrent() - _sampled > PGStubPerfIdleSeconds)
    {
        dispatch_source_cancel(_timer);
        _timer = nil;
        _pingPending = NO;
        _maxMillis = 0;
        _slowCount = 0;
        return;
    }
    if(_pingPending)
    {
        return;
    }
    _pingPending = YES;
    _pingSent = CFAbsoluteTimeGetCurrent();
    dispatch_queue_t queue = _queue;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        CFAbsoluteTime answered = CFAbsoluteTimeGetCurrent();
        dispatch_async(queue, ^{
            [weakSelf notePingAnsweredAt:answered];
        });
    });
}

- (void)notePingAnsweredAt:(CFAbsoluteTime)answered
{
    double millis = (answered - _pingSent) * 1000.0;
    _pingPending = NO;
    _maxMillis = MAX(_maxMillis, millis);
    if(millis >= PGStubPerfSlowMillis)
    {
        _slowCount += 1;
    }
}

- (uint64_t)footprintBytes
{
    task_vm_info_data_t info;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if(task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) != KERN_SUCCESS)
    {
        return 0;
    }
    return info.phys_footprint;
}

- (double)cpuPercentThreads:(NSInteger *)threads
{
    thread_act_array_t list = NULL;
    mach_msg_type_number_t count = 0;
    if(task_threads(mach_task_self(), &list, &count) != KERN_SUCCESS)
    {
        return 0;
    }
    double total = 0;
    for(mach_msg_type_number_t index = 0; index < count; index++)
    {
        thread_basic_info_data_t info;
        mach_msg_type_number_t infoCount = THREAD_BASIC_INFO_COUNT;
        if(thread_info(list[index], THREAD_BASIC_INFO, (thread_info_t)&info, &infoCount) == KERN_SUCCESS && !(info.flags & TH_FLAGS_IDLE))
        {
            total += info.cpu_usage / (double)TH_USAGE_SCALE * 100.0;
        }
        mach_port_deallocate(mach_task_self(), list[index]);
    }
    vm_deallocate(mach_task_self(), (vm_address_t)list, count * sizeof(thread_act_t));
    *threads = count;
    return total;
}

@end
