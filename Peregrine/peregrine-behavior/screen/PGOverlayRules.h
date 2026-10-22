#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PGOverlayKind) {
    PGOverlayKindNone = 0,
    PGOverlayKindPaywall,
    PGOverlayKindAd,
};

// Classifies one screen from its node texts. A full-window container is present in almost every
// point tree, so area alone says little; the text has to carry most of the evidence.
//
// Paywall: largest node covers >= 70% of the screen, at most 12 clickable nodes, and either two
// nodes with subscription words, or one such node plus a price.
// Ad: largest node covers >= 15%, at most 8 clickable nodes, no subscription word, and either a
// countdown, an ad badge or explicit ad word, or two nodes with weaker words such as skip/install.
@interface PGOverlayRules : NSObject

+ (PGOverlayKind)kindForTexts:(NSArray<NSString *> *)texts
                    clickable:(NSInteger)clickable
                  largestArea:(double)largestArea;

+ (BOOL)text:(NSString *)text hasAny:(NSArray<NSString *> *)words;
// Latin keywords of three characters or fewer must not sit inside a longer word. CJK keywords
// match anywhere: every CJK character is a letter, so a boundary check would reject 立即订阅.
+ (BOOL)text:(NSString *)text containsKeyword:(NSString *)keyword;
+ (BOOL)textIsCountdown:(NSString *)text;
+ (BOOL)textHasPrice:(NSString *)text;

@end

NS_ASSUME_NONNULL_END
