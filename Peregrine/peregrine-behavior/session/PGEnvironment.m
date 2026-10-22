#import "PGEnvironment.h"

@implementation PGEnvironment

+ (NSString *)usableString:(id)value
{
    if(![value isKindOfClass:[NSString class]])
    {
        return nil;
    }
    NSString *text = [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if(text.length == 0 || [text hasPrefix:@"$"])
    {
        return nil;
    }
    return text;
}

+ (NSString *)stringForKey:(NSString *)key inEnvironment:(NSDictionary *)environment
{
    NSDictionary *source = environment ?: NSProcessInfo.processInfo.environment;
    return [self usableString:source[key]];
}

@end
