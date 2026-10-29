#import "PGOverlayRules.h"

static NSArray<NSString *> *PGSubscriptionWords(void)
{
    return @[
        @"订阅", @"免费试用", @"开始试用", @"开通会员", @"恢复购买", @"自动续费", @"连续包月", @"连续包年", @"随时取消",
        @"subscribe", @"subscription", @"free trial", @"start trial", @"try for free", @"try free",
        @"restore purchase", @"auto-renew", @"auto renew", @"cancel anytime",
        @"suscribir", @"suscripción", @"suscripcion", @"prueba gratis", @"prueba gratuita", @"restaurar compra",
        @"assinar", @"assinatura", @"teste grátis", @"teste gratis", @"restaurar compra",
        @"abonner", @"abonnement", @"essai gratuit", @"acheter un abonnement",
        @"abonnieren", @"kostenlos testen",
        @"購読", @"無料トライアル", @"購入を復元",
        @"구독", @"무료 체험", @"구입 복원",
        @"abbonati", @"abbonamento", @"prova gratuita", @"ripristina acquisto",
        @"подписк", @"бесплатн", @"пробный период", @"восстановить покуп",
        @"اشتراك", @"تجربة مجانية", @"استعادة الشراء",
        @"berlangganan", @"uji coba gratis", @"pulihkan pembelian",
        @"abone", @"ücretsiz dene", @"satın almayı geri yükle",
        @"đăng ký", @"dùng thử miễn phí", @"khôi phục giao dịch",
        @"สมัครสมาชิก", @"ทดลองฟรี", @"คืนค่าการซื้อ",
        @"सदस्यता", @"मुफ़्त ट्रायल", @"खरीदारी पुनर्स्थापित"
    ];
}

// "close ad" also matches Close Advertisement. A bare close control is not enough on its own.
static NSArray<NSString *> *PGExplicitDismissPhrases(void)
{
    return @[
        @"跳过广告", @"关闭广告", @"skip ad", @"close ad",
        @"saltar anuncio", @"cerrar anuncio", @"cerrar publicidad",
        @"pular anúncio", @"pular anuncio", @"fechar anúncio", @"fechar anuncio",
        @"passer la pub", @"fermer la pub",
        @"werbung überspringen", @"werbung schließen", @"werbung schliessen",
        @"広告を閉じる", @"広告をスキップ",
        @"광고 닫기", @"광고 건너뛰기",
        @"salta annuncio", @"chiudi annuncio",
        @"пропустить рекламу", @"закрыть рекламу",
        @"تخطي الإعلان", @"إغلاق الإعلان",
        @"lewati iklan", @"tutup iklan",
        @"reklamı geç", @"reklamı kapat",
        @"bỏ qua quảng cáo", @"đóng quảng cáo",
        @"ข้ามโฆษณา", @"ปิดโฆษณา",
        @"विज्ञापन छोड़ें", @"विज्ञापन बंद"
    ];
}

static NSArray<NSString *> *PGAdContentWords(void)
{
    return @[
        @"advertisement", @"sponsored", @"rewarded", @"激励视频",
        @"patrocinado", @"video recompensa", @"vídeo recompensa",
        @"publicité", @"publicite", @"vidéo récompense",
        @"gesponsert", @"belohntes video",
        @"報酬動画", @"리워드 광고", @"video premiato", @"видео с наградой",
        @"فيديو بمكافأة", @"إعلان مدفوع",
        @"video berhadiah", @"bersponsor",
        @"ödüllü video", @"sponsorlu",
        @"video có thưởng", @"được tài trợ",
        @"วิดีโอรับรางวัล", @"पुरस्कृत वीडियो"
    ];
}

static NSArray<NSString *> *PGPurchaseWords(void)
{
    return @[
        @"subscribe", @"subscription", @"purchase", @"buy", @"premium", @"payment", @"free trial", @"start trial", @"restore purchase",
        @"订阅", @"购买", @"试用", @"恢复购买", @"付款", @"支付",
        @"suscribir", @"suscripción", @"suscripcion", @"comprar", @"pagar", @"prueba gratis", @"prueba gratuita", @"restaurar compra",
        @"assinar", @"assinatura", @"teste grátis", @"teste gratis", @"restaurar compra",
        @"abonner", @"abonnement", @"acheter", @"payer", @"essai gratuit",
        @"abonnieren", @"kaufen", @"kostenlos testen", @"kauf wiederherstellen",
        @"購読", @"購入", @"お試し", @"購入を復元",
        @"구독", @"구매", @"체험", @"구입 복원",
        @"abbonati", @"abbonamento", @"acquista", @"prova gratuita", @"ripristina acquisto",
        @"подписк", @"купить", @"пробн", @"восстановить покуп",
        @"اشتراك", @"شراء", @"تجربة مجانية",
        @"berlangganan", @"beli", @"uji coba",
        @"abone", @"satın al", @"deneme",
        @"đăng ký", @"mua", @"dùng thử",
        @"สมัครสมาชิก", @"ซื้อ", @"ทดลองใช้",
        @"सदस्यता", @"खरीद"
    ];
}

static NSArray<NSString *> *PGConfirmGiveUpMarkers(void)
{
    return @[
        @"lose your reward", @"lose reward", @"give up your reward", @"give up reward",
        @"放弃奖励", @"确认退出", @"仍要退出",
        @"perder recompensa", @"renunciar recompensa", @"perder a recompensa",
        @"perdre la récompense", @"perdre la recompense", @"belohnung aufgeben",
        @"報酬を放棄", @"보상 포기", @"perdere ricompensa", @"потерять награду",
        @"فقدان المكافأة", @"kehilangan hadiah", @"ödülü kaybet",
        @"mất phần thưởng", @"เสียรางวัล", @"इनाम छोड़ें"
    ];
}

static BOOL PGTextIsShortClose(NSString *text)
{
    NSArray<NSString *> *words = @[
        @"close", @"关闭", @"skip", @"跳过", @"x", @"×", @"✕", @"✖",
        @"cerrar", @"saltar", @"fechar", @"pular", @"fermer", @"passer",
        @"schließen", @"schliessen", @"überspringen", @"ueberspringen",
        @"閉じる", @"スキップ", @"닫기", @"건너뛰기", @"chiudi", @"salta",
        @"закрыть", @"пропустить", @"إغلاق", @"تخطي", @"tutup", @"lewati",
        @"kapat", @"geç", @"đóng", @"bỏ qua", @"ปิด", @"ข้าม", @"बंद", @"छोड़ें"
    ];
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSArray<NSString *> *tokens = [trimmed componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if(tokens.count > 1)
    {
        tokens = [tokens arrayByAddingObject:trimmed];
    }
    for(NSString *token in tokens)
    {
        if(token.length == 0)
        {
            continue;
        }
        for(NSString *word in words)
        {
            if([token caseInsensitiveCompare:word] == NSOrderedSame)
            {
                return YES;
            }
        }
    }
    return NO;
}

// Ad badges count only as the whole text, so a setting such as 个性化广告 does not.
static NSArray<NSString *> *PGAdBadges(void)
{
    return @[
        @"广告", @"赞助", @"推广", @"ad", @"ads",
        @"anuncio", @"publicidad", @"anúncio", @"anuncio", @"pub",
        @"werbung", @"広告", @"광고", @"annuncio", @"реклама",
        @"إعلان", @"iklan", @"reklam", @"quảng cáo", @"โฆษณา", @"विज्ञापन"
    ];
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
        @"skip", @"install", @"download", @"learn more", @"get app", @"reward",
        @"instalar", @"descargar", @"más información", @"baixar", @"saiba mais",
        @"télécharger", @"telecharger", @"en savoir plus",
        @"herunterladen", @"mehr erfahren",
        @"インストール", @"ダウンロード", @"설치", @"다운로드", @"자세히",
        @"installa", @"scarica", @"maggiori informazioni",
        @"установить", @"скачать", @"подробнее",
        @"تثبيت", @"تحميل", @"pasang", @"unduh", @"yükle", @"indir",
        @"tải xuống", @"cài đặt", @"ดาวน์โหลด", @"डाउनलोड"
    ];
}

static NSRegularExpression *PGPriceExpression(void)
{
    static NSRegularExpression *expr;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *pattern = @"(?:[¥￥$€£₩₹₽₺]|R\\$)\\s?[0-9]"
                             "|[0-9](?:[.,][0-9]+)?\\s?(?:[¥￥$€£₩₹₽₺]|元|美元|円|원|USD|CNY|EUR|GBP|KRW|INR|RUB|TRY|TL)"
                             "|/\\s?(?:月|年|周|季|month|year|week|mo|yr|wk|mes|mês|mois|monat|개월|месяц|bulan|ay|tháng|เดือน|महीना)\\b"
                             "|每(?:月|年|周|季)"
                             "|\\bper\\s(?:month|year|week)\\b"
                             "|\\bpor\\s(?:m[eê]s|ano|semana)\\b"
                             "|\\bal\\s(?:mes|año)\\b"
                             "|\\bpar\\s(?:mois|an)\\b"
                             "|\\bpro\\s(?:monat|jahr|woche)\\b";
        expr = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:nil];
    });
    return expr;
}

static NSRegularExpression *PGCountdownExpression(void)
{
    static NSRegularExpression *expr;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        expr = [NSRegularExpression regularExpressionWithPattern:@"^(?:跳过|skip|saltar|pular|passer|salta|スキップ|건너뛰기|überspringen|ueberspringen|пропустить|تخطي|lewati|geç|gec|bỏ qua|bo qua|ข้าม|छोड़ें)\\s*[0-9]{1,2}\\s*(?:s|sec|秒|초|с|ث|detik|sn|giây|วินาที|सेकंड)?$|^[0-9]{1,2}\\s*(?:s|sec|秒|초|с|ث|detik|sn|giây|วินาที|सेकंड)$" options:NSRegularExpressionCaseInsensitive error:nil];
    });
    return expr;
}

@implementation PGOverlayRules

+ (PGOverlayKind)kindForTexts:(NSArray<NSString *> *)texts clickable:(NSInteger)clickable largestArea:(double)largestArea
{
    NSInteger subscription = 0;
    NSInteger weakAd = 0;
    BOOL price = NO;
    BOOL countdown = NO;
    BOOL explicitDismiss = NO;
    BOOL adContent = NO;
    BOOL shortClose = NO;
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
        if([self text:text hasAny:PGExplicitDismissPhrases()])
        {
            explicitDismiss = YES;
            adContent = YES;
        }
        else if(PGTextIsBadge(text) || [self text:text hasAny:PGAdContentWords()])
        {
            adContent = YES;
        }
        else if([self text:text hasAny:PGWeakAdWords()])
        {
            weakAd += 1;
        }
        if(PGTextIsShortClose(text))
        {
            shortClose = YES;
        }
        price = price || [self textHasPrice:text];
        countdown = countdown || [self textIsCountdown:text];
    }
    if(largestArea >= 0.70 && clickable <= 12 && (subscription >= 2 || (subscription >= 1 && price)))
    {
        return PGOverlayKindPaywall;
    }
    // The splash picture itself is dropped, so a close control labeled as an ad can be the largest node left and still cover far less than 15%.
    if(subscription == 0 && clickable > 0 && clickable <= 16 && (explicitDismiss || (adContent && shortClose)))
    {
        return PGOverlayKindAd;
    }
    if(largestArea >= 0.15 && clickable > 0 && clickable <= 8 && subscription == 0 && (countdown || (weakAd >= 2 && shortClose)))
    {
        return PGOverlayKindAd;
    }
    return PGOverlayKindNone;
}

+ (BOOL)textsConfirmExit:(NSArray<NSString *> *)texts
{
    for(NSString *text in texts)
    {
        NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        for(NSString *marker in PGConfirmGiveUpMarkers())
        {
            // A button or title is about as long as the phrase. Ad copy that mentions it is longer.
            if(trimmed.length > 0 && trimmed.length <= marker.length + 6 && [self text:trimmed hasAny:@[marker]])
            {
                return YES;
            }
        }
    }
    return NO;
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
    NSCharacterSet *letters = [NSCharacterSet letterCharacterSet];
    unichar first = [keyword characterAtIndex:0];
    NSRange search = NSMakeRange(0, text.length);
    while(search.length > 0)
    {
        NSRange range = [text rangeOfString:keyword options:NSCaseInsensitiveSearch range:search];
        if(range.location == NSNotFound)
        {
            return NO;
        }
        if(first > 0x7F)
        {
            return YES;
        }
        BOOL insideWord = (range.location > 0 && [letters characterIsMember:[text characterAtIndex:range.location - 1]]);
        NSUInteger end = NSMaxRange(range);
        if(!insideWord && end < text.length && [letters characterIsMember:[text characterAtIndex:end]])
        {
            insideWord = YES;
        }
        if(!insideWord)
        {
            return YES;
        }
        if(end >= text.length)
        {
            return NO;
        }
        search = NSMakeRange(end, text.length - end);
    }
    return NO;
}

+ (BOOL)textIsCountdown:(NSString *)text
{
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if(trimmed.length == 0 || trimmed.length > 28)
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

+ (BOOL)textIsMembership:(NSString *)text
{
    return [self text:text hasAny:PGSubscriptionWords()] || [self text:text hasAny:@[@"vip", @"会员", @"premium"]];
}

+ (BOOL)textIsPurchase:(NSString *)text
{
    return [self text:text hasAny:PGPurchaseWords()];
}

+ (BOOL)textIsShareEntry:(NSString *)text
{
    return [self text:text hasAny:@[
        @"share", @"分享", @"共享",
        @"comparte", @"compartir", @"compartilhar", @"partager", @"teilen",
        @"共有", @"シェア", @"공유", @"condividi", @"поделиться",
        @"مشاركة", @"bagikan", @"paylaş", @"chia sẻ", @"แชร์", @"साझा"
    ]];
}

+ (BOOL)textIsGiveUp:(NSString *)text
{
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    for(NSString *marker in PGConfirmGiveUpMarkers())
    {
        if(trimmed.length > 0 && trimmed.length <= marker.length + 6 && [self text:trimmed hasAny:@[marker]])
        {
            return YES;
        }
    }
    return NO;
}

+ (BOOL)textIsShortClose:(NSString *)text
{
    return PGTextIsShortClose(text);
}

+ (BOOL)textClosesWideBar:(NSString *)text
{
    return [self text:text hasAny:@[
        @"close", @"关闭", @"cerrar", @"fechar", @"fermer", @"schließen", @"schliessen",
        @"閉じる", @"닫기", @"chiudi", @"закрыть", @"إغلاق", @"tutup", @"kapat", @"đóng", @"ปิด", @"बंद"
    ]];
}

+ (BOOL)textIsInstall:(NSString *)text
{
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSArray<NSString *> *words = @[
        @"install", @"update", @"upgrade", @"software update",
        @"安装", @"更新", @"升级", @"软件更新", @"系统更新",
        @"instalar", @"actualizar", @"atualizar", @"installer", @"mettre à jour", @"mise à jour",
        @"installieren", @"aktualisieren",
        @"インストール", @"アップデート", @"설치", @"업데이트",
        @"installa", @"aggiorna", @"установить", @"обновить",
        @"تثبيت", @"تحديث", @"pasang", @"perbarui", @"yükle", @"güncelle",
        @"cài đặt", @"cập nhật", @"ติดตั้ง", @"อัปเดต", @"इंस्टॉल", @"अपडेट"
    ];
    for(NSString *word in words)
    {
        if(![self text:trimmed containsKeyword:word])
        {
            continue;
        }
        // 更新 inside 内容已更新 is ordinary copy. 立即更新 and 软件更新 stay install prompts.
        unichar first = [word characterAtIndex:0];
        if(first > 0x7F && word.length <= 2 && trimmed.length > word.length + 2)
        {
            continue;
        }
        return YES;
    }
    return NO;
}

+ (BOOL)textIsDestructive:(NSString *)text
{
    return [self text:text hasAny:@[
        @"delete", @"remove", @"erase", @"log out", @"logout", @"sign out", @"reset", @"clear",
        @"删除", @"移除", @"抹掉", @"退出登录", @"登出", @"注销", @"清空", @"清除", @"重置",
        @"eliminar", @"borrar", @"cerrar sesión", @"cerrar sesion", @"excluir", @"sair",
        @"supprimer", @"effacer", @"déconnexion", @"deconnexion",
        @"löschen", @"loeschen", @"abmelden",
        @"削除", @"ログアウト", @"삭제", @"로그아웃",
        @"elimina", @"esci", @"удалить", @"выйти",
        @"hapus", @"keluar", @"sil", @"çıkış", @"cikis",
        @"xóa", @"đăng xuất", @"ลบ", @"ออกจากระบบ", @"हटाएं", @"लॉग आउट",
        @"حذف", @"إزالة", @"مسح", @"تسجيل الخروج", @"إعادة تعيين"
    ]];
}

@end
