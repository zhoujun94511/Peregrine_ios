#import "PGRunFiles.h"

static NSString * const PGPreviousFolder = @"peregrine-previous";

@implementation PGRunFiles

+ (void)keepPreviousRunInDirectory:(NSString *)directory
{
    NSString *root = directory.length > 0 ? directory : NSTemporaryDirectory();
    NSFileManager *manager = [NSFileManager defaultManager];
    NSArray<NSString *> *names = @[@"peregrine-events.jsonl", @"peregrine-coverage.txt", @"peregrine-applet.txt", @"peregrine-shots.zip", @"peregrine-shots"];
    NSMutableArray<NSString *> *found = [NSMutableArray array];
    for(NSString *name in names)
    {
        if([manager fileExistsAtPath:[root stringByAppendingPathComponent:name]])
        {
            [found addObject:name];
        }
    }
    if(found.count == 0)
    {
        return;
    }
    NSString *previous = [root stringByAppendingPathComponent:PGPreviousFolder];
    [manager removeItemAtPath:previous error:nil];
    NSError *error = nil;
    BOOL keep = [manager createDirectoryAtPath:previous withIntermediateDirectories:YES attributes:nil error:&error];
    NSInteger kept = 0;
    for(NSString *name in found)
    {
        NSString *source = [root stringByAppendingPathComponent:name];
        if(keep && [manager moveItemAtPath:source toPath:[previous stringByAppendingPathComponent:name] error:nil])
        {
            kept += 1;
            continue;
        }
        [manager removeItemAtPath:source error:nil];
    }
    if(!keep)
    {
        NSLog(@"previous run keep failed %@", error.localizedDescription);
        return;
    }
    NSLog(@"previous run keep success %ld", (long)kept);
}

@end
