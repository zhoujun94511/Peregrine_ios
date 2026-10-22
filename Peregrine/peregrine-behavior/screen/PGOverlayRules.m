#import "PGOverlayRules.h"

static NSArray<NSString *> *PGSubscriptionWords(void)
{
    return @[
        @"订阅", @"免费试用", @"开始试用", @"开通会员", @"恢复购买", @"自动续费", @"连续包月", @"连续包年", @"随时取消",
        @"subscribe", @"subscription", @"free trial", @"start trial", @"try for free", @"try free",
        @"restore purchase", @"auto-renew", @"auto renew", @"cancel anytime"
    ];
}

static NSArray<NSString *> *PGStrongAdWords(void)
{
    return @[
        @"跳过广告", @"关闭广告", @"激励视频", @"领取奖励",
        @"advertisement", @"sponsored", @"skip ad", @"close ad", @"rewarded"
    ];
}

// Ad badges count only as the whole text, so a setting such as 个性化广告 does not.
static NSArray<NSString *> *PGAdBadges(void)
{
    return @[@"广告", @"赞助", @"推广", @"ad", @"ads"];
}

static BOOL PGTextIsBadge(NSString *text)
{
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    for(NSString *badge in PGAdBadges())
    {
        if([trimmed caseInsensitiveCompare:badge] == NSOrderedSame)
        {
            return YES;
        }
    }
    return NO;
}

static NSArray<NSString *> *PGWeakAdWords(void)
{
    return @[
        @"跳过", @"安装", @"下载", @"了解更多", @"立即打开",
        @"skip", @"install", @"download", @"learn more", @"get app", @"reward"
    ];
}

static NSRegularExpression *PGPriceExpression(void)
{
    static NSRegularExpression *expr;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *pattern = @"[¥￥$€£₩]\\s?[0-9]"
                             "|[0-9](?:[.,][0-9]+)?\\s?(?:元|美元|円|USD|CNY|EUR)"
                             "|/\\s?(?:月|年|周|季|month|year|week|mo|yr|wk)\\b"
                             "|每(?:月|年|周|季)"
                             "|\\bper\\s(?:month|year|week)\\b";
        expr = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:nil];
    });
    return expr;
}

static NSRegularExpression *PGCountdownExpression(void)
{
    static NSRegularExpression *expr;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        expr = [NSRegularExpression regularExpressionWithPattern:@"^(?:跳过|skip)?\\s*[0-9]{1,2}\\s*(?:s|秒)?$" options:NSRegularExpressionCaseInsensitive error:nil];
    });
    return expr;
}

@implementation PGOverlayRules

+ (PGOverlayKind)kindForTexts:(NSArray<NSString *> *)texts clickable:(NSInteger)clickable largestArea:(double)largestArea
{
    NSInteger subscription = 0;
    NSInteger strongAd = 0;
    NSInteger weakAd = 0;
    BOOL price = NO;
    BOOL countdown = NO;
    for(NSString *text in texts)
    {
        if(text.length == 0)
        {
            continue;
        }
        if([self text:text hasAny:PGSubscriptionWords()])
        {
            subscription += 1;
        }
        if(PGTextIsBadge(text) || [self text:text hasAny:PGStrongAdWords()])
        {
            strongAd += 1;
        }
        else if([self text:text hasAny:PGWeakAdWords()])
        {
            weakAd += 1;
        }
        price = price || [self textHasPrice:text];
        countdown = countdown || [self textIsCountdown:text];
    }
    if(largestArea >= 0.70 && clickable <= 12 && (subscription >= 2 || (subscription >= 1 && price)))
    {
        return PGOverlayKindPaywall;
    }
    if(largestArea >= 0.15 && clickable > 0 && clickable <= 8 && subscription == 0 && (countdown || strongAd >= 1 || weakAd >= 2))
    {
        return PGOverlayKindAd;
    }
    return PGOverlayKindNone;
}

+ (BOOL)text:(NSString *)text hasAny:(NSArray<NSString *> *)words
{
    for(NSString *word in words)
    {
        if([self text:text containsKeyword:word])
        {
            return YES;
        }
    }
    return NO;
}

+ (BOOL)text:(NSString *)text containsKeyword:(NSString *)keyword
{
    if(text.length == 0 || keyword.length == 0)
    {
        return NO;
    }
    NSRange range = [text rangeOfString:keyword options:NSCaseInsensitiveSearch];
    if(range.location == NSNotFound)
    {
        return NO;
    }
    if(keyword.length > 3)
    {
        return YES;
    }
    NSCharacterSet *letters = [NSCharacterSet letterCharacterSet];
    unichar first = [keyword characterAtIndex:0];
    if(first > 0x7F)
    {
        return YES;
    }
    if(range.location > 0 && [letters characterIsMember:[text characterAtIndex:range.location - 1]])
    {
        return NO;
    }
    NSUInteger end = NSMaxRange(range);
    if(end < text.length && [letters characterIsMember:[text characterAtIndex:end]])
    {
        return NO;
    }
    return YES;
}

+ (BOOL)textIsCountdown:(NSString *)text
{
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if(trimmed.length == 0 || trimmed.length > 12)
    {
        return NO;
    }
    return [PGCountdownExpression() numberOfMatchesInString:trimmed options:0 range:NSMakeRange(0, trimmed.length)] > 0;
}

+ (BOOL)textHasPrice:(NSString *)text
{
    if(text.length == 0)
    {
        return NO;
    }
    return [PGPriceExpression() numberOfMatchesInString:text options:0 range:NSMakeRange(0, text.length)] > 0;
}

@end
