#import "PGAppletSession.h"

@interface PGAppletSession ()
@property (nonatomic, copy) NSString *schema;
@property (nonatomic, assign) NSInteger attempts;
@property (nonatomic, assign, readwrite) BOOL entered;
@property (nonatomic, assign, readwrite) NSInteger failures;
@property (nonatomic, assign, readwrite) BOOL openAttempted;
@end

@implementation PGAppletSession

- (instancetype)initWithSchema:(NSString *)schema
{
    self = [super init];
    if(self != nil)
    {
        _schema = schema ?: @"";
    }
    return self;
}

+ (NSURL *)openableURLFromSchema:(NSString *)schema
{
    NSURL *url = [NSURL URLWithString:schema ?: @""];
    if(url.scheme.length == 0)
    {
        return nil;
    }
    return url;
}

- (NSURL *)URLToOpenOnce
{
    if(self.openAttempted)
    {
        return nil;
    }
    self.openAttempted = YES;
    return [PGAppletSession openableURLFromSchema:self.schema];
}

- (void)observeActivity:(NSString *)activity
{
    if(self.schema.length == 0 || self.entered)
    {
        return;
    }
    if(activity.length > 0 && [activity containsString:self.schema])
    {
        self.entered = YES;
        return;
    }
    self.attempts += 1;
    if(self.attempts == 5)
    {
        self.failures += 1;
    }
}

- (NSString *)summary
{
    if(self.schema.length == 0)
    {
        return @"applet schema none";
    }
    return [NSString stringWithFormat:@"applet %@ entered %d failures %ld", self.schema, self.entered, (long)self.failures];
}

- (BOOL)writeSummaryToDirectory:(NSString *)directory error:(NSError **)error
{
    NSString *folder = directory.length > 0 ? directory : NSTemporaryDirectory();
    NSString *path = [folder stringByAppendingPathComponent:@"peregrine-applet.txt"];
    NSString *body = [NSString stringWithFormat:@"%@\n%@\n", [NSDate date].description, [self summary]];
    return [body writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:error];
}

@end
