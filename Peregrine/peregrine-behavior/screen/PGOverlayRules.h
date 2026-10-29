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
// Ad: no subscription word, and either an explicit dismiss phrase (close ad / skip ad / 关闭广告 /
// 跳过广告, including Close Advertisement) with at most 16 clickable nodes, or that same limit when
// an ad word and a separate close / skip control are both on screen, or a largest node covering
// >= 15% with at most 8 clickable nodes plus a countdown. A countdown is a skip word plus a
// number, or a number with a seconds unit. A bare number, or two weaker words with no close
// control, does not classify the page.
// A badge such as 广告 alone does not classify the page. Give-up copy and continue-watching
// do not either. The full-screen splash image is not in the tree, so the close control alone
// can sit under 15%.
// textsConfirmExit: a short give-up label such as 放弃奖励 or 确认退出. A longer sentence that
// only mentions it does not match, and 继续观看 does not match.
@interface PGOverlayRules : NSObject

+ (PGOverlayKind)kindForTexts:(NSArray<NSString *> *)texts
                    clickable:(NSInteger)clickable
                  largestArea:(double)largestArea;

+ (BOOL)textsConfirmExit:(NSArray<NSString *> *)texts;

+ (BOOL)text:(NSString *)text hasAny:(NSArray<NSString *> *)words;
// A Latin keyword must be a whole word, so subscribe does not match unsubscribe and share does
// not match shared. CJK keywords match anywhere: every CJK character is a letter, so a boundary
// check would reject 立即订阅. Short install words such as 更新 are limited in textIsInstall:.
+ (BOOL)text:(NSString *)text containsKeyword:(NSString *)keyword;
+ (BOOL)textIsCountdown:(NSString *)text;
+ (BOOL)textHasPrice:(NSString *)text;
// Subscription wording, plus vip / 会员 / premium. Used for a full-page membership screen.
+ (BOOL)textIsMembership:(NSString *)text;
// Subscribe, buy, and trial labels in common languages. Continue and 继续 are not included.
+ (BOOL)textIsPurchase:(NSString *)text;
// Share, 分享, compartir, and the same word in other common languages. Send is not included.
+ (BOOL)textIsShareEntry:(NSString *)text;
// Short give-up label such as 放弃奖励. Used to choose the exit control, not to classify a fresh page.
+ (BOOL)textIsGiveUp:(NSString *)text;
// Exact close / skip token, including cerrar, fechar, fermer and the same set in other common languages.
+ (BOOL)textIsShortClose:(NSString *)text;
// A wide close bar whose text asks to close, so the tap can move to one end.
+ (BOOL)textClosesWideBar:(NSString *)text;
+ (BOOL)textIsInstall:(NSString *)text;
+ (BOOL)textIsDestructive:(NSString *)text;

@end

NS_ASSUME_NONNULL_END
