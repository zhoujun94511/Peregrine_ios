#import "PGConfig.h"
#import "PGEnvironment.h"

@implementation PGConfig

+ (instancetype)loadedConfig
{
    PGConfig *config = [[PGConfig alloc] init];
    config.channel = @"OS";
    NSDictionary *test = [self jsonNamed:@"testconfig.json"];
    config.skipCheckBlock = [test[@"SkipCheckBlock"] boolValue];
    config.skipRestart = [test[@"SkipRestart"] boolValue];
    config.skipHome = [test[@"SkipHome"] boolValue];
    config.gestureRatios = [test[@"GestureRatio"] isKindOfClass:[NSDictionary class]] ? test[@"GestureRatio"] : @{};
    NSDictionary *setting = [self jsonNamed:@"setting.json"];
    if([setting[@"channel"] isKindOfClass:[NSString class]])
    {
        config.channel = setting[@"channel"];
    }
    NSDictionary *actions = [self jsonNamed:@"default.jsonsetting"];
    config.events = [actions[@"events"] isKindOfClass:[NSArray class]] ? actions[@"events"] : @[];
    config.actions = [actions[@"actions"] isKindOfClass:[NSArray class]] ? actions[@"actions"] : @[];
    config.sequences = [actions[@"sequences"] isKindOfClass:[NSArray class]] ? actions[@"sequences"] : @[];
    NSDictionary *app = [self jsonNamed:@"appconfig.json"];
    config.cases = [app[@"cases"] isKindOfClass:[NSArray class]] ? app[@"cases"] : @[];
    NSDictionary *scene = [app[@"sceneLimit"] isKindOfClass:[NSDictionary class]] ? app[@"sceneLimit"] : @{};
    if([app[@"sceneLimits"] isKindOfClass:[NSArray class]])
    {
        config.sceneLimits = app[@"sceneLimits"];
    }
    else if(scene.count > 0)
    {
        config.sceneLimits = @[scene];
    }
    else
    {
        config.sceneLimits = @[];
    }
    config.sceneScheme = [scene[@"scheme"] isKindOfClass:[NSString class]] ? scene[@"scheme"] : @"";
    config.allowViewControllers = [self stringList:scene[@"allow"]];
    config.blockViewControllers = [self stringList:scene[@"block"]];
    config.sceneDuration = [scene[@"duration"] doubleValue];
    config.sceneCallbackURL = [app[@"sceneCallback"] isKindOfClass:[NSString class]] ? app[@"sceneCallback"] : @"";
    NSDictionary *applet = [app[@"applet"] isKindOfClass:[NSDictionary class]] ? app[@"applet"] : @{};
    config.appletSchema = [applet[@"schema"] isKindOfClass:[NSString class]] ? applet[@"schema"] : @"";
    config.excludeRects = [app[@"excludeRects"] isKindOfClass:[NSArray class]] ? app[@"excludeRects"] : @[];
    config.excludeElements = [self stringList:app[@"excludeElements"]];
    config.sceneConfigURL = [app[@"sceneConfigURL"] isKindOfClass:[NSString class]] ? app[@"sceneConfigURL"] : @"";
    return config;
}

- (void)applyToSceneLimit:(PGSceneLimit *)sceneLimit
{
    sceneLimit.scheme = self.sceneScheme;
    sceneLimit.allowViewControllers = self.allowViewControllers;
    sceneLimit.blockViewControllers = self.blockViewControllers;
    sceneLimit.duration = self.sceneDuration;
    sceneLimit.startedAt = [NSDate date];
    sceneLimit.state = PGSceneLimitStateRunning;
}

- (void)applyToPreference:(PGPreference *)preference
{
    [preference loadEvents:self.events actions:self.actions];
    [preference loadSequences:self.sequences];
}

+ (NSArray<NSString *> *)stringList:(id)value
{
    if(![value isKindOfClass:[NSArray class]])
    {
        return @[];
    }
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for(id item in (NSArray *)value)
    {
        if([item isKindOfClass:[NSString class]] && [(NSString *)item length] > 0)
        {
            [names addObject:item];
        }
    }
    return names;
}

+ (NSDictionary *)jsonNamed:(NSString *)name
{
    NSString *path = [self pathForResource:name];
    NSData *data = path == nil ? nil : [NSData dataWithContentsOfFile:path];
    id json = data == nil ? nil : [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [json isKindOfClass:[NSDictionary class]] ? json : @{};
}

+ (NSString *)pathForResource:(NSString *)name
{
    NSString *override = [PGEnvironment stringForKey:@"PEREGRINE_CONFIG" inEnvironment:nil];
    if(override.length > 0)
    {
        NSString *direct = [override stringByAppendingPathComponent:name];
        if([[NSFileManager defaultManager] fileExistsAtPath:direct])
        {
            return direct;
        }
    }
    NSBundle *bundle = [self configBundle];
    NSArray<NSString *> *paths = @[
        [bundle.bundlePath stringByAppendingPathComponent:name],
        [bundle.resourcePath stringByAppendingPathComponent:name]
    ];
    for(NSString *path in paths)
    {
        if([[NSFileManager defaultManager] fileExistsAtPath:path])
        {
            return path;
        }
    }
    return nil;
}

+ (NSBundle *)configBundle
{
    NSBundle *code = [NSBundle bundleForClass:self];
    NSArray<NSString *> *candidates = @[
        [code pathForResource:@"PGBehaviorConfig" ofType:@"bundle"] ?: @"",
        [code.bundlePath stringByAppendingPathComponent:@"PGBehaviorConfig.bundle"],
        [[code.bundlePath stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"PGBehaviorConfig.bundle"]
    ];
    for(NSString *path in candidates)
    {
        if(path.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:path])
        {
            NSBundle *bundle = [NSBundle bundleWithPath:path];
            if(bundle != nil)
            {
                return bundle;
            }
        }
    }
    return code;
}

@end
