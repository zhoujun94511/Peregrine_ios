#import "PGStepShots.h"
#import "PGScreenGrab.h"

static NSString * const PGShotsFolder = @"peregrine-shots";
static NSString * const PGShotsArchive = @"peregrine-shots.zip";
static const CGFloat PGShotsQuality = 0.6;

@interface PGStepShots ()
@property (nonatomic, assign, readwrite) PGStepShotsMode mode;
@property (nonatomic, copy) NSString *folder;
@property (nonatomic, copy) NSString *archive;
@property (nonatomic, assign) NSInteger limit;
@property (nonatomic, assign) NSInteger step;
@property (nonatomic, assign) uint64_t lastFingerprint;
@property (nonatomic, strong) NSMutableArray<NSString *> *files;
@property (nonatomic, strong) NSFileHandle *index;
@property (nonatomic, assign) BOOL reportedLimit;
@end

@implementation PGStepShots

+ (PGStepShotsMode)modeFromText:(NSString *)text
{
    NSString *value = [text lowercaseString] ?: @"";
    if([value isEqualToString:@"all"])
    {
        return PGStepShotsModeAll;
    }
    if([value isEqualToString:@"change"])
    {
        return PGStepShotsModeChange;
    }
    return PGStepShotsModeOff;
}

- (instancetype)initWithMode:(PGStepShotsMode)mode directory:(NSString *)directory limit:(NSInteger)limit
{
    self = [super init];
    if(self != nil)
    {
        NSString *root = directory.length > 0 ? directory : NSTemporaryDirectory();
        _mode = mode;
        _folder = [root stringByAppendingPathComponent:PGShotsFolder];
        _archive = [root stringByAppendingPathComponent:PGShotsArchive];
        _limit = MAX(limit, 1);
        _files = [NSMutableArray array];
        if(mode != PGStepShotsModeOff)
        {
            [self openFolder];
        }
    }
    return self;
}

- (void)openFolder
{
    NSError *error = nil;
    if(![[NSFileManager defaultManager] createDirectoryAtPath:self.folder withIntermediateDirectories:YES attributes:nil error:&error])
    {
        NSLog(@"shots folder failed %@", error.localizedDescription);
        self.mode = PGStepShotsModeOff;
        return;
    }
    NSString *indexPath = [self.folder stringByAppendingPathComponent:@"index.jsonl"];
    [[NSFileManager defaultManager] createFileAtPath:indexPath contents:nil attributes:nil];
    self.index = [NSFileHandle fileHandleForWritingAtPath:indexPath];
    NSLog(@"shots %@ limit %ld", self.mode == PGStepShotsModeAll ? @"all" : @"change", (long)self.limit);
}

- (void)recordScreen:(PGStepScreen *)screen operate:(PGOperate *)operate application:(XCUIApplication *)application
{
    if(self.mode == PGStepShotsModeOff)
    {
        return;
    }
    self.step += 1;
    if(self.mode == PGStepShotsModeChange && screen.fingerprint != 0 && screen.fingerprint == self.lastFingerprint)
    {
        return;
    }
    self.lastFingerprint = screen.fingerprint;
    UIImage *image = screen.image ?: [PGScreenGrab uprightScreenshotOfApplication:application];
    if(image == nil)
    {
        return;
    }
    NSString *act = operate.act.length > 0 ? operate.act.uppercaseString : @"NONE";
    NSString *name = [NSString stringWithFormat:@"%04ld-%@.jpg", (long)self.step, act];
    NSData *jpeg = UIImageJPEGRepresentation([self markedImage:image screen:screen operate:operate act:act], PGShotsQuality);
    if(jpeg == nil || ![jpeg writeToFile:[self.folder stringByAppendingPathComponent:name] atomically:NO])
    {
        return;
    }
    [self.files addObject:name];
    [self appendIndexForName:name screen:screen operate:operate act:act];
    [self dropOldest];
}

- (void)dropOldest
{
    while((NSInteger)self.files.count > self.limit)
    {
        [[NSFileManager defaultManager] removeItemAtPath:[self.folder stringByAppendingPathComponent:self.files.firstObject] error:nil];
        [self.files removeObjectAtIndex:0];
        if(!self.reportedLimit)
        {
            self.reportedLimit = YES;
            NSLog(@"shots limit %ld reached, oldest dropped", (long)self.limit);
        }
    }
}

- (void)appendIndexForName:(NSString *)name screen:(PGStepScreen *)screen operate:(PGOperate *)operate act:(NSString *)act
{
    PGElementRect rect = operate.rect;
    NSDictionary *entry = @{
        @"step": @(self.step),
        @"file": name,
        @"time": @((long long)([[NSDate date] timeIntervalSince1970] * 1000)),
        @"act": act,
        @"target": @[@(rect.left), @(rect.top), @(rect.width), @(rect.height)],
        @"text": operate.text ?: @"",
        @"source": screen.source ?: @"",
        @"activity": screen.activity ?: @"",
        @"nodes": @([PGElementNode flattenedNodes:screen.nodes].count),
        @"fingerprint": [NSString stringWithFormat:@"%016llx", screen.fingerprint]
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:entry options:0 error:nil];
    if(data == nil)
    {
        return;
    }
    NSMutableData *line = [data mutableCopy];
    [line appendBytes:"\n" length:1];
    @try
    {
        [self.index writeData:line];
    }
    @catch(NSException *exception)
    {
        NSLog(@"shots index failed %@", exception.reason);
        self.index = nil;
    }
}

// Drawn in points: node rects come in pixels when the nodes were cut from the screenshot.
- (UIImage *)markedImage:(UIImage *)image screen:(PGStepScreen *)screen operate:(PGOperate *)operate act:(NSString *)act
{
    CGSize size = screen.screenSize.width > 0 && screen.screenSize.height > 0 ? screen.screenSize : CGSizeMake(image.size.width / 3, image.size.height / 3);
    CGFloat nodeScaleX = 1;
    CGFloat nodeScaleY = 1;
    if(!screen.usePoints && screen.pixelSize.width > 0 && screen.pixelSize.height > 0)
    {
        nodeScaleX = size.width / screen.pixelSize.width;
        nodeScaleY = size.height / screen.pixelSize.height;
    }
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1;
    format.opaque = YES;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [image drawInRect:CGRectMake(0, 0, size.width, size.height)];
        CGContextRef cg = context.CGContext;
        CGContextSetLineWidth(cg, 1);
        for(PGElementNode *node in [PGElementNode flattenedNodes:screen.nodes])
        {
            if(!node.clickable || node.rect.width <= 0 || node.rect.height <= 0)
            {
                continue;
            }
            CGContextSetStrokeColorWithColor(cg, [UIColor colorWithRed:0 green:0.85 blue:0.3 alpha:0.9].CGColor);
            CGContextStrokeRect(cg, CGRectMake(node.rect.left * nodeScaleX, node.rect.top * nodeScaleY, node.rect.width * nodeScaleX, node.rect.height * nodeScaleY));
        }
        CGContextSetStrokeColorWithColor(cg, [UIColor redColor].CGColor);
        CGContextSetLineWidth(cg, 3);
        PGElementRect target = operate.rect;
        if(target.width > 0 && target.height > 0)
        {
            CGContextStrokeRect(cg, CGRectMake(target.left, target.top, target.width, target.height));
        }
        if(operate.path.count >= 2)
        {
            for(NSUInteger i = 0; i < operate.path.count; i++)
            {
                CGPoint point = CGPointMake([operate.path[i][@"x"] doubleValue], [operate.path[i][@"y"] doubleValue]);
                if(i == 0)
                {
                    CGContextMoveToPoint(cg, point.x, point.y);
                }
                else
                {
                    CGContextAddLineToPoint(cg, point.x, point.y);
                }
            }
            CGContextStrokePath(cg);
        }
        NSString *caption = [NSString stringWithFormat:@"#%ld %@ %@ %@", (long)self.step, act, screen.source ?: @"", operate.text ?: @""];
        NSDictionary *attributes = @{
            NSFontAttributeName: [UIFont systemFontOfSize:11 weight:UIFontWeightMedium],
            NSForegroundColorAttributeName: [UIColor whiteColor]
        };
        CGRect band = CGRectMake(0, size.height - 18, size.width, 18);
        [[UIColor colorWithWhite:0 alpha:0.65] setFill];
        UIRectFill(band);
        [caption drawInRect:CGRectInset(band, 4, 2) withAttributes:attributes];
    }];
}

- (void)finish
{
    if(self.mode == PGStepShotsModeOff)
    {
        return;
    }
    [self.index closeFile];
    self.index = nil;
    NSURL *folderURL = [NSURL fileURLWithPath:self.folder isDirectory:YES];
    NSURL *archiveURL = [NSURL fileURLWithPath:self.archive];
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    __block NSError *copyError = nil;
    __block BOOL copied = NO;
    NSError *readError = nil;
    // Reading a folder for uploading hands back a zip of it; Foundation has no other public zip API.
    [coordinator coordinateReadingItemAtURL:folderURL options:NSFileCoordinatorReadingForUploading error:&readError byAccessor:^(NSURL *zipURL) {
        copied = [[NSFileManager defaultManager] copyItemAtURL:zipURL toURL:archiveURL error:&copyError];
    }];
    if(!copied)
    {
        NSLog(@"shots archive failed %@", (readError ?: copyError).localizedDescription ?: @"");
        return;
    }
    [[NSFileManager defaultManager] removeItemAtPath:self.folder error:nil];
    NSLog(@"shots archive success %lu", (unsigned long)self.files.count);
}

@end
