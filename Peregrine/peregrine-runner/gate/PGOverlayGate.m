#import "PGOverlayGate.h"
#import "PGSnapshotTree.h"
#import "PGOverlayRules.h"
#import "PGActionFilter.h"

static NSArray<NSString *> *PGCloseWords(void)
{
    return @[
        @"关闭", @"以后再说", @"暂不", @"取消", @"下次再说", @"不了",
        @"not now", @"no thanks", @"maybe later", @"later", @"cancel", @"dismiss", @"close", @"back",
        @"返回", @"返回上一页",
        @"ahora no", @"más tarde", @"mas tarde", @"cancelar", @"cerrar",
        @"agora não", @"agora nao", @"mais tarde", @"fechar",
        @"plus tard", @"annuler", @"fermer",
        @"nicht jetzt", @"später", @"spaeter", @"abbrechen", @"schließen", @"schliessen",
        @"後で", @"キャンセル", @"閉じる",
        @"나중에", @"취소", @"닫기",
        @"non ora", @"più tardi", @"piu tardi", @"annulla", @"chiudi",
        @"не сейчас", @"позже", @"отмена", @"закрыть",
        @"ليس الآن", @"إلغاء", @"إغلاق",
        @"nanti", @"batal", @"tutup",
        @"şimdi değil", @"simdi degil", @"iptal", @"kapat",
        @"để sau", @"hủy", @"đóng",
        @"ภายหลัง", @"ยกเลิก", @"ปิด",
        @"अभी नहीं", @"रद्द", @"बंद",
        @"×", @"✕", @"✖"
    ];
}

static NSArray<NSString *> *PGPaywallAvoidWords(void)
{
    return @[
        @"订阅", @"开通", @"试用", @"购买", @"继续", @"恢复购买", @"会员",
        @"subscribe", @"subscription", @"trial", @"purchase", @"buy", @"continue", @"restore", @"premium", @"upgrade",
        @"continuar", @"continuer", @"fortfahren", @"weiter",
        @"続ける", @"계속", @"continua", @"продолжить",
        @"متابعة", @"lanjut", @"devam", @"tiếp tục", @"ดำเนินการต่อ", @"जारी",
        @"miembro", @"membro", @"membre", @"mitglied", @"会員", @"회원",
        @"suscribir", @"suscripción", @"suscripcion", @"comprar", @"pagar",
        @"assinar", @"assinatura", @"acheter", @"payer", @"abonnement",
        @"abonnieren", @"kaufen", @"購読", @"購入", @"お試し",
        @"구독", @"구매", @"체험", @"abbonati", @"abbonamento", @"acquista",
        @"подписк", @"купить", @"اشتراك", @"شراء",
        @"berlangganan", @"beli", @"abone", @"satın",
        @"đăng ký", @"mua", @"สมัคร", @"ซื้อ", @"सदस्यता", @"खरीद"
    ];
}

static NSArray<NSString *> *PGAdAvoidWords(void)
{
    return @[
        @"安装", @"下载", @"打开", @"了解更多", @"install", @"download", @"open", @"learn more", @"get app",
        @"instalar", @"descargar", @"abrir", @"más información",
        @"baixar", @"saiba mais", @"télécharger", @"telecharger", @"ouvrir", @"en savoir plus",
        @"herunterladen", @"öffnen", @"oeffnen", @"mehr erfahren",
        @"インストール", @"ダウンロード", @"開く", @"설치", @"다운로드", @"열기",
        @"installa", @"scarica", @"apri", @"установить", @"скачать", @"открыть",
        @"تثبيت", @"تحميل", @"فتح", @"pasang", @"unduh", @"buka",
        @"yükle", @"indir", @"aç", @"tải xuống", @"cài đặt", @"mở",
        @"ดาวน์โหลด", @"เปิด", @"डाउनलोड", @"खोलें"
    ];
}

static NSArray<NSString *> *PGAdCloseWords(void)
{
    return @[
        @"跳过", @"关闭广告", @"关闭", @"skip ad", @"skip", @"close ad", @"close",
        @"saltar", @"cerrar", @"pular", @"fechar", @"passer", @"fermer",
        @"überspringen", @"ueberspringen", @"schließen", @"schliessen",
        @"スキップ", @"閉じる", @"건너뛰기", @"닫기", @"salta", @"chiudi",
        @"пропустить", @"закрыть", @"تخطي", @"إغلاق", @"lewati", @"tutup",
        @"geç", @"kapat", @"bỏ qua", @"đóng", @"ข้าม", @"ปิด", @"छोड़ें", @"बंद",
        @"×", @"✕", @"✖"
    ];
}

static NSArray<NSString *> *PGExitWords(void)
{
    return @[
        @"放弃奖励", @"仍要退出", @"确认退出", @"关闭广告", @"give up reward", @"close anyway",
        @"give up", @"exit", @"leave", @"放弃", @"退出", @"关闭", @"close",
        @"perder recompensa", @"renunciar", @"salir", @"cerrar",
        @"perder a recompensa", @"sair", @"fechar",
        @"perdre", @"quitter", @"fermer",
        @"aufgeben", @"beenden", @"schließen", @"schliessen",
        @"放棄", @"終了", @"閉じる", @"포기", @"종료", @"닫기",
        @"rinuncia", @"esci", @"chiudi",
        @"выйти", @"закрыть", @"خروج", @"إغلاق",
        @"keluar", @"tutup", @"çık", @"cik", @"kapat",
        @"thoát", @"đóng", @"ออก", @"ปิด", @"बाहर", @"बंद"
    ];
}

static NSArray<NSString *> *PGExitPhraseWords(void)
{
    return @[
        @"放弃奖励", @"仍要退出", @"确认退出", @"give up reward", @"close anyway",
        @"perder recompensa", @"renunciar recompensa", @"perder a recompensa",
        @"perdre la récompense", @"perdre la recompense", @"belohnung aufgeben",
        @"報酬を放棄", @"보상 포기", @"perdere ricompensa", @"потерять награду",
        @"فقدان المكافأة", @"kehilangan hadiah", @"ödülü kaybet",
        @"mất phần thưởng", @"เสียรางวัล", @"इनाम छोड़ें"
    ];
}

static NSArray<NSString *> *PGContinueWords(void)
{
    return @[
        @"继续观看", @"继续播放", @"continue watching", @"keep watching", @"resume", @"继续", @"continue",
        @"seguir viendo", @"continuar viendo", @"continuar assistindo",
        @"continuer à regarder", @"continuer a regarder", @"weiter ansehen",
        @"視聴を続ける", @"계속 시청", @"continua a guardare", @"продолжить просмотр",
        @"متابعة المشاهدة", @"lanjut menonton", @"izlemeye devam",
        @"tiếp tục xem", @"ดูต่อ", @"देखना जारी"
    ];
}

@implementation PGOverlayDecision
@end

@implementation PGOverlayGate
{
    uint64_t _fingerprint;
    NSInteger _repeats;
    NSInteger _streak;
    PGOverlayKind _kind;
    NSInteger _absent;
    BOOL _tappedLeft;
    BOOL _tappedRight;
    BOOL _sentBack;
    BOOL _confirming;
    BOOL _tappedExit;
    BOOL _membership;
    NSInteger _formSteps;
    NSTimeInterval _adWaitStarted;
    NSArray<PGElementNode *> *_snapshotNodes;
    uint64_t _snapshotFingerprint;
    NSInteger _snapshotSkip;
}

- (PGOverlayDecision *)decisionForScreen:(PGStepScreen *)screen application:(XCUIApplication *)application
{
    PGOverlayDecision *decision = [[PGOverlayDecision alloc] init];
    if(screen.fingerprint == 0)
    {
        return decision;
    }
    if(screen.fingerprint != _fingerprint)
    {
        _fingerprint = screen.fingerprint;
        _repeats = 1;
        _formSteps = 0;
    }
    else
    {
        _repeats += 1;
    }
    BOOL points = screen.usePoints;
    CGSize space = points ? screen.screenSize : screen.pixelSize;
    NSArray<PGElementNode *> *nodes = [PGElementNode flattenedNodes:screen.nodes];
    if(![self nodesHaveText:nodes] && _repeats >= 2)
    {
        nodes = [self snapshotNodesForScreen:screen application:application];
        points = YES;
        space = screen.screenSize;
    }
    space = [self space:space coveringNodes:nodes];
    PGOverlayKind overlay = [self kindOfNodes:nodes inSpace:space];
    if(overlay == PGOverlayKindNone && _kind == PGOverlayKindAd && [self nodesConfirmExit:nodes])
    {
        overlay = PGOverlayKindAd;
        NSLog(@"overlay ad keep exit");
    }
    if(overlay == PGOverlayKindNone && [self nodesLookLikeWordBank:nodes])
    {
        _formSteps += 1;
        decision.action = PGOverlayActionOperate;
        if(_formSteps == 1)
        {
            PGElementNode *field = [self emptyEntryIn:nodes];
            if(field != nil)
            {
                decision.operate = [PGOperate clickOnNode:field];
                decision.operate.act = @"TYPE";
                decision.operate.text = @"peregrine";
                NSLog(@"overlay form step %ld type", (long)_formSteps);
                return decision;
            }
            PGElementNode *close = [self closeNodeIn:nodes space:space paywall:YES points:points side:-1];
            if(close != nil)
            {
                decision.operate = [PGOperate clickOnNode:close];
                [self aimClose:decision.operate node:close end:0];
                NSLog(@"overlay form step %ld close %@ point %ld,%ld", (long)_formSteps, decision.operate.text ?: @"", (long)decision.operate.rect.left, (long)decision.operate.rect.top);
                return decision;
            }
            decision.operate = [self topLeftOperateInSpace:space];
            NSLog(@"overlay form step %ld corner", (long)_formSteps);
            return decision;
        }
        decision.operate = [self backOperate];
        NSLog(@"overlay form step %ld back", (long)_formSteps);
        return decision;
    }
    else if(overlay == PGOverlayKindNone)
    {
        _formSteps = 0;
    }
    if(overlay == PGOverlayKindNone)
    {
        if(_kind != PGOverlayKindNone && _absent < 1)
        {
            _absent += 1;
            decision.action = PGOverlayActionOperate;
            decision.operate = [self waitOperate];
            NSLog(@"overlay %@ absent", _kind == PGOverlayKindPaywall ? @"paywall" : @"ad");
            return decision;
        }
        [self clearRound];
        return decision;
    }
    _absent = 0;
    if(overlay != _kind)
    {
        _kind = overlay;
        _streak = 0;
        _adWaitStarted = 0;
        _tappedLeft = NO;
        _tappedRight = NO;
        _sentBack = NO;
        _confirming = NO;
        _tappedExit = NO;
    }
    BOOL paywall = overlay == PGOverlayKindPaywall;
    if(!paywall)
    {
        [self decideAd:decision nodes:nodes space:space points:points];
        return decision;
    }
    PGElementNode *close = [self closeNodeIn:nodes space:space paywall:YES points:points side:-1];
    if(close != nil)
    {
        _adWaitStarted = 0;
    }
    _streak += 1;
    if(_streak >= 3)
    {
        decision.action = PGOverlayActionOperate;
        decision.operate = [PGOperate restart];
        NSLog(@"overlay paywall step %ld restart", (long)_streak);
        _streak = 0;
        return decision;
    }
    decision.action = PGOverlayActionOperate;
    if(_streak == 2)
    {
        decision.operate = [self backOperate];
        NSLog(@"overlay paywall step %ld back repeat", (long)_streak);
        return decision;
    }
    if(close != nil)
    {
        decision.operate = [PGOperate clickOnNode:close];
        [self aimClose:decision.operate node:close end:0];
        NSLog(@"overlay paywall step %ld close %@ %@ point %ld,%ld", (long)_streak, [self cornerNameForRect:close.rect space:space], decision.operate.text ?: @"", (long)decision.operate.rect.left, (long)decision.operate.rect.top);
        return decision;
    }
    if(_membership)
    {
        decision.operate = [self topLeftOperateInSpace:space];
        NSLog(@"overlay paywall step %ld corner", (long)_streak);
        return decision;
    }
    decision.operate = [self backOperate];
    NSLog(@"overlay paywall step %ld back no-close", (long)_streak);
    return decision;
}

- (NSArray<PGElementNode *> *)snapshotNodesForScreen:(PGStepScreen *)screen application:(XCUIApplication *)application
{
    uint64_t fingerprint = screen.fingerprint;
    if(_snapshotSkip > 0)
    {
        _snapshotSkip -= 1;
        return @[];
    }
    if(_snapshotFingerprint == fingerprint && _snapshotNodes != nil)
    {
        return _snapshotNodes;
    }
    PGStepSnapshot *snapshot = [screen snapshotInApplication:application];
    if(snapshot.failure != nil)
    {
        NSLog(@"overlay snapshot failed %@", snapshot.failure);
        _snapshotSkip = 5;
        return @[];
    }
    NSArray<PGElementNode *> *nodes = snapshot.nodes;
    BOOL outside = snapshot.outside;
    NSInteger elapsed = snapshot.elapsedMillis;
    if(elapsed > 1500)
    {
        NSLog(@"overlay snapshot slow %ld", (long)elapsed);
        _snapshotSkip = 5;
        return @[];
    }
    if(outside)
    {
        NSLog(@"overlay snapshot outside");
        return @[];
    }
    _snapshotNodes = nodes ?: @[];
    _snapshotFingerprint = fingerprint;
    return _snapshotNodes;
}

- (PGOverlayKind)kindOfNodes:(NSArray<PGElementNode *> *)nodes inSpace:(CGSize)space
{
    if(space.width < 2 || space.height < 2)
    {
        return PGOverlayKindNone;
    }
    NSInteger clickable = 0;
    CGFloat maxArea = 0;
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    for(PGElementNode *node in nodes)
    {
        CGRect rect = [self rect:node.rect inSpace:space];
        maxArea = MAX(maxArea, rect.size.width * rect.size.height);
        if(node.clickable)
        {
            clickable += 1;
        }
        NSString *text = [self textOfNode:node];
        if(text.length > 0)
        {
            [texts addObject:text];
        }
    }
    PGOverlayKind kind = [PGOverlayRules kindForTexts:texts clickable:clickable largestArea:maxArea];
    // A membership page can fill the screen and still have a back control at the top left.
    // Prices on it open the system payment sheet, so this path closes the page instead of exploring them.
    _membership = NO;
    if(kind == PGOverlayKindNone && [self nodesLookLikeMembership:nodes])
    {
        _membership = YES;
        NSLog(@"overlay paywall membership");
        return PGOverlayKindPaywall;
    }
    // Purchase buttons are not explored. When they are the only clickable controls, edge back
    // does not leave the sheet, so the paywall path closes it and then relaunches.
    if(kind == PGOverlayKindNone && [self nodesArePurchaseOnly:nodes])
    {
        NSLog(@"overlay paywall purchase-only");
        return PGOverlayKindPaywall;
    }
    return kind;
}

- (BOOL)nodesLookLikeMembership:(NSArray<PGElementNode *> *)nodes
{
    BOOL price = NO;
    BOOL member = NO;
    for(PGElementNode *node in nodes)
    {
        NSString *text = [self textOfNode:node];
        if([PGOverlayRules textHasPrice:text])
        {
            price = YES;
        }
        if([PGOverlayRules textIsMembership:text])
        {
            member = YES;
        }
    }
    return price && member;
}

- (BOOL)nodesLookLikeWordBank:(NSArray<PGElementNode *> *)nodes
{
    NSInteger clickable = 0;
    NSInteger chips = 0;
    NSCharacterSet *spaces = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    for(PGElementNode *node in nodes)
    {
        if(!node.clickable)
        {
            continue;
        }
        clickable += 1;
        if(node.identifier.length > 0)
        {
            continue;
        }
        NSString *text = node.label.length > 0 ? node.label : (node.value ?: @"");
        text = [text stringByTrimmingCharactersInSet:spaces];
        if(text.length == 0 || text.length > 16)
        {
            continue;
        }
        NSInteger words = 0;
        for(NSString *part in [text componentsSeparatedByCharactersInSet:spaces])
        {
            if(part.length > 0)
            {
                words += 1;
            }
        }
        if(words > 0 && words <= 2)
        {
            chips += 1;
        }
    }
    return chips >= 6 && chips * 2 >= clickable;
}

- (PGElementNode *)emptyEntryIn:(NSArray<PGElementNode *> *)nodes
{
    for(PGElementNode *node in nodes)
    {
        NSString *type = node.type.lowercaseString ?: @"";
        BOOL entry = [type containsString:@"field"] || [type containsString:@"textview"] || [type containsString:@"search"];
        if(!entry || [type containsString:@"secure"])
        {
            continue;
        }
        if((node.value ?: @"").length == 0)
        {
            return node;
        }
    }
    return nil;
}

- (PGOperate *)topLeftOperateInSpace:(CGSize)space
{
    NSInteger left = MAX(8, (NSInteger)(space.width * 0.02));
    NSInteger top = MAX(48, (NSInteger)(space.height * 0.06));
    PGOperate *operate = [[PGOperate alloc] init];
    operate.act = @"CLICK";
    operate.rect = (PGElementRect){left, top, 44, 44};
    operate.text = @"corner";
    return operate;
}

- (BOOL)nodesArePurchaseOnly:(NSArray<PGElementNode *> *)nodes
{
    BOOL purchase = NO;
    for(PGElementNode *node in nodes)
    {
        if([PGActionFilter includeNode:node kind:PGActionFilterEnabled visits:0])
        {
            return NO;
        }
        if([PGOverlayRules textIsPurchase:[self textOfNode:node]])
        {
            purchase = YES;
        }
    }
    return purchase;
}

- (void)decideAd:(PGOverlayDecision *)decision nodes:(NSArray<PGElementNode *> *)nodes space:(CGSize)space points:(BOOL)points
{
    if([self nodesConfirmExit:nodes])
    {
        if(!_confirming)
        {
            _confirming = YES;
            _tappedExit = NO;
            _sentBack = NO;
            _adWaitStarted = 0;
        }
        [self decideConfirmExit:decision nodes:nodes space:space points:points];
        return;
    }
    if(_confirming)
    {
        _confirming = NO;
        _tappedExit = NO;
    }
    PGElementNode *left = [self closeNodeIn:nodes space:space paywall:NO points:points side:0];
    PGElementNode *right = [self closeNodeIn:nodes space:space paywall:NO points:points side:1];
    BOOL wide = [self nodeIsWide:left] || [self nodeIsWide:right];
    BOOL rightDistinct = right != nil && (right != left || wide);
    BOOL leftNamed = [self nodeIsNamedClose:left];
    BOOL rightNamed = [self nodeIsNamedClose:right];
    if(leftNamed && !_tappedLeft)
    {
        _tappedLeft = YES;
        [self tapClose:decision node:left end:[self nodeIsWide:left] ? -1 : 0 name:@"left" space:space];
        return;
    }
    if(rightDistinct && rightNamed && !_tappedRight)
    {
        _tappedRight = YES;
        [self tapClose:decision node:right end:[self nodeIsWide:right] ? 1 : 0 name:@"right" space:space];
        return;
    }
    BOOL leftPending = !_tappedLeft && !leftNamed;
    BOOL rightPending = !_tappedRight && !rightNamed;
    if((leftPending || rightPending) && [self adCloseStillLoading])
    {
        decision.action = PGOverlayActionOperate;
        decision.operate = [self waitOperate];
        NSLog(@"overlay ad wait close");
        return;
    }
    if(left != nil && !_tappedLeft)
    {
        _tappedLeft = YES;
        [self tapClose:decision node:left end:[self nodeIsWide:left] ? -1 : 0 name:@"left" space:space];
        return;
    }
    if(rightDistinct && !_tappedRight)
    {
        _tappedRight = YES;
        [self tapClose:decision node:right end:[self nodeIsWide:right] ? 1 : 0 name:@"right" space:space];
        return;
    }
    decision.action = PGOverlayActionOperate;
    if(!_sentBack)
    {
        _sentBack = YES;
        decision.operate = [self backOperate];
        NSLog(@"overlay ad back");
        return;
    }
    decision.operate = [PGOperate restart];
    NSLog(@"overlay ad restart");
    _tappedLeft = NO;
    _tappedRight = NO;
    _sentBack = NO;
    _confirming = NO;
    _tappedExit = NO;
    _adWaitStarted = 0;
}

- (void)decideConfirmExit:(PGOverlayDecision *)decision nodes:(NSArray<PGElementNode *> *)nodes space:(CGSize)space points:(BOOL)points
{
    PGElementNode *exit = [self exitNodeIn:nodes space:space points:points];
    if(exit != nil && !_tappedExit)
    {
        _tappedExit = YES;
        [self tapClose:decision node:exit end:0 name:@"exit" space:space];
        return;
    }
    if(exit == nil && [self adCloseStillLoading])
    {
        decision.action = PGOverlayActionOperate;
        decision.operate = [self waitOperate];
        NSLog(@"overlay ad wait exit");
        return;
    }
    decision.action = PGOverlayActionOperate;
    if(!_sentBack)
    {
        _sentBack = YES;
        decision.operate = [self backOperate];
        NSLog(@"overlay ad back");
        return;
    }
    decision.operate = [PGOperate restart];
    NSLog(@"overlay ad restart");
    _tappedLeft = NO;
    _tappedRight = NO;
    _sentBack = NO;
    _confirming = NO;
    _tappedExit = NO;
    _adWaitStarted = 0;
}

- (BOOL)nodesConfirmExit:(NSArray<PGElementNode *> *)nodes
{
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    for(PGElementNode *node in nodes)
    {
        for(NSString *part in @[node.label ?: @"", node.value ?: @"", node.identifier ?: @""])
        {
            if(part.length > 0)
            {
                [texts addObject:part];
            }
        }
    }
    return [PGOverlayRules textsConfirmExit:texts];
}

- (PGElementNode *)exitNodeIn:(NSArray<PGElementNode *> *)nodes space:(CGSize)space points:(BOOL)points
{
    if(!points || space.width < 2 || space.height < 2)
    {
        return nil;
    }
    PGElementNode *best = nil;
    NSInteger bestScore = 0;
    CGFloat bestArea = 2;
    for(PGElementNode *node in nodes)
    {
        if(!node.clickable && ![self nodeIsShortClose:node])
        {
            continue;
        }
        NSString *text = [self textOfNode:node];
        if([PGOverlayRules textIsCountdown:text] || [PGOverlayRules text:text hasAny:PGContinueWords()] || [PGOverlayRules text:text hasAny:PGAdAvoidWords()])
        {
            continue;
        }
        CGRect rect = [self rect:node.rect inSpace:space];
        CGFloat area = rect.size.width * rect.size.height;
        if(area > 0.25)
        {
            continue;
        }
        NSInteger score = 0;
        BOOL giveUp = NO;
        for(NSString *part in @[node.label ?: @"", node.value ?: @"", node.identifier ?: @""])
        {
            if([PGOverlayRules textIsGiveUp:part])
            {
                giveUp = YES;
                break;
            }
        }
        if(giveUp || [PGOverlayRules text:text hasAny:PGExitPhraseWords()])
        {
            score = 120;
        }
        else if([PGOverlayRules text:text hasAny:PGExitWords()] || [self nodeIsShortClose:node] || [self textIsMark:text])
        {
            score = 100;
        }
        if(score == 0)
        {
            continue;
        }
        if(score > bestScore || (score == bestScore && area < bestArea))
        {
            best = node;
            bestScore = score;
            bestArea = area;
        }
    }
    return best;
}

- (void)tapClose:(PGOverlayDecision *)decision node:(PGElementNode *)node end:(NSInteger)end name:(NSString *)name space:(CGSize)space
{
    decision.action = PGOverlayActionOperate;
    decision.operate = [PGOperate clickOnNode:node];
    [self aimClose:decision.operate node:node end:end];
    NSLog(@"overlay ad close %@ %@ %@ point %ld,%ld", name, [self cornerNameForRect:node.rect space:space], decision.operate.text ?: @"", (long)decision.operate.rect.left, (long)decision.operate.rect.top);
}
- (PGElementNode *)closeNodeIn:(NSArray<PGElementNode *> *)nodes space:(CGSize)space paywall:(BOOL)paywall points:(BOOL)points side:(NSInteger)side
{
    if(!points || space.width < 2 || space.height < 2)
    {
        return nil;
    }
    NSArray<NSString *> *safe = paywall ? PGCloseWords() : PGAdCloseWords();
    NSArray<NSString *> *avoid = paywall ? PGPaywallAvoidWords() : PGAdAvoidWords();
    PGElementNode *best = nil;
    NSInteger bestScore = 0;
    CGFloat bestArea = 2;
    for(PGElementNode *node in nodes)
    {
        if(![self node:node coversSide:side space:space])
        {
            continue;
        }
        if(!node.clickable && ![self nodeIsShortClose:node])
        {
            continue;
        }
        NSString *text = [self textOfNode:node];
        if([PGOverlayRules textIsCountdown:text] || [PGOverlayRules text:text hasAny:avoid] || (paywall && ([PGOverlayRules textIsPurchase:text] || [PGOverlayRules textHasPrice:text])))
        {
            continue;
        }
        NSInteger score = 0;
        if([self nodeIsShortClose:node])
        {
            score = 120;
        }
        else if(!node.clickable)
        {
            continue;
        }
        else if([PGOverlayRules text:text hasAny:safe] || [self textIsMark:text])
        {
            score = 100;
        }
        else if([self rectIsCorner:node.rect inSpace:space])
        {
            if(paywall && ![self rectIsTopCorner:node.rect inSpace:space])
            {
                continue;
            }
            score = 80;
        }
        if(score == 0)
        {
            continue;
        }
        CGRect rect = [self rect:node.rect inSpace:space];
        CGFloat area = rect.size.width * rect.size.height;
        if(area > 0.25)
        {
            continue;
        }
        if(score > bestScore || (score == bestScore && area < bestArea))
        {
            best = node;
            bestScore = score;
            bestArea = area;
        }
    }
    return best;
}

- (BOOL)node:(PGElementNode *)node coversSide:(NSInteger)side space:(CGSize)space
{
    if(side < 0)
    {
        return YES;
    }
    CGRect rect = [self rect:node.rect inSpace:space];
    if(side == 0)
    {
        return CGRectGetMinX(rect) < 0.50 && CGRectGetMidX(rect) <= 0.62;
    }
    return CGRectGetMaxX(rect) > 0.50 && CGRectGetMidX(rect) >= 0.38;
}

- (BOOL)nodeIsNamedClose:(PGElementNode *)node
{
    if(node == nil)
    {
        return NO;
    }
    if([self nodeIsShortClose:node])
    {
        return YES;
    }
    NSString *text = [self textOfNode:node];
    return [PGOverlayRules text:text hasAny:PGAdCloseWords()] || [self textIsMark:text];
}

- (BOOL)nodeIsShortClose:(PGElementNode *)node
{
    for(NSString *part in @[node.label ?: @"", node.value ?: @"", node.identifier ?: @""])
    {
        if([PGOverlayRules textIsShortClose:part])
        {
            return YES;
        }
    }
    return NO;
}

- (BOOL)nodeIsWide:(PGElementNode *)node
{
    return node != nil && node.rect.height > 0 && node.rect.width > node.rect.height * 2;
}

- (BOOL)nodesHaveText:(NSArray<PGElementNode *> *)nodes
{
    for(PGElementNode *node in nodes)
    {
        if([self textOfNode:node].length > 0)
        {
            return YES;
        }
    }
    return NO;
}

- (NSString *)textOfNode:(PGElementNode *)node
{
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if(node.label.length > 0)
    {
        [parts addObject:node.label];
    }
    if(node.value.length > 0)
    {
        [parts addObject:node.value];
    }
    if(node.identifier.length > 0)
    {
        [parts addObject:node.identifier];
    }
    return [parts componentsJoinedByString:@" "];
}

- (BOOL)textIsMark:(NSString *)text
{
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [trimmed isEqualToString:@"x"] || [trimmed isEqualToString:@"X"] || [trimmed isEqualToString:@"×"] || [trimmed isEqualToString:@"✕"] || [trimmed isEqualToString:@"✖"];
}

- (CGRect)rect:(PGElementRect)rect inSpace:(CGSize)space
{
    return CGRectMake(rect.left / space.width, rect.top / space.height, rect.width / space.width, rect.height / space.height);
}

- (NSString *)cornerNameForRect:(PGElementRect)rect space:(CGSize)space
{
    if(![self rectIsCorner:rect inSpace:space])
    {
        return @"text";
    }
    CGRect normal = [self rect:rect inSpace:space];
    BOOL top = CGRectGetMidY(normal) <= 0.50;
    BOOL left = CGRectGetMidX(normal) <= 0.50;
    if(top && left)
    {
        return @"top-left";
    }
    if(top)
    {
        return @"top-right";
    }
    return left ? @"bottom-left" : @"bottom-right";
}

- (BOOL)rectIsCorner:(PGElementRect)rect inSpace:(CGSize)space
{
    CGRect normal = [self rect:rect inSpace:space];
    if(normal.size.width <= 0 || normal.size.height <= 0 || normal.size.width > 0.28 || normal.size.height > 0.18)
    {
        return NO;
    }
    CGFloat midX = CGRectGetMidX(normal);
    CGFloat midY = CGRectGetMidY(normal);
    BOOL top = midY <= 0.28;
    BOOL bottom = midY >= 0.72;
    BOOL left = midX <= 0.30;
    BOOL right = midX >= 0.70;
    return (top || bottom) && (left || right);
}

- (BOOL)rectIsTopCorner:(PGElementRect)rect inSpace:(CGSize)space
{
    CGRect normal = [self rect:rect inSpace:space];
    return CGRectGetMidY(normal) <= 0.28 && [self rectIsCorner:rect inSpace:space];
}

- (CGSize)space:(CGSize)space coveringNodes:(NSArray<PGElementNode *> *)nodes
{
    if(space.width >= 2 && space.height >= 2)
    {
        return space;
    }
    NSInteger width = 0;
    NSInteger height = 0;
    for(PGElementNode *node in nodes)
    {
        width = MAX(width, node.rect.left + node.rect.width);
        height = MAX(height, node.rect.top + node.rect.height);
    }
    return CGSizeMake(MAX(width, 2), MAX(height, 2));
}

- (PGOperate *)backOperate
{
    PGOperate *operate = [[PGOperate alloc] init];
    operate.act = @"BACK";
    return operate;
}

- (void)clearRound
{
    _streak = 0;
    _kind = PGOverlayKindNone;
    _absent = 0;
    _adWaitStarted = 0;
    _tappedLeft = NO;
    _tappedRight = NO;
    _sentBack = NO;
    _confirming = NO;
    _tappedExit = NO;
    _membership = NO;
    _formSteps = 0;
}

- (PGOperate *)waitOperate
{
    PGOperate *operate = [[PGOperate alloc] init];
    operate.act = @"";
    return operate;
}

- (BOOL)adCloseStillLoading
{
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    if(_adWaitStarted <= 0)
    {
        _adWaitStarted = now;
    }
    return now - _adWaitStarted < 8.0;
}

- (void)aimClose:(PGOperate *)operate node:(PGElementNode *)node end:(NSInteger)end
{
    PGElementRect rect = node.rect;
    if(end == 0 || rect.height <= 0 || rect.width <= rect.height * 2)
    {
        return;
    }
    NSString *text = [self textOfNode:node];
    if(![PGOverlayRules textClosesWideBar:text])
    {
        return;
    }
    NSInteger x = end < 0 ? rect.left + rect.height / 2 : rect.left + rect.width - rect.height / 2;
    NSInteger y = rect.top + rect.height / 2;
    operate.rect = (PGElementRect){x, y, 1, 1};
}

@end
