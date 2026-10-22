#import <Foundation/Foundation.h>
#import "PGSceneLimit.h"
#import "PGPreference.h"

NS_ASSUME_NONNULL_BEGIN

// Reads the editable JSON under peregrine-behavior/config.
// testconfig.json supplies SkipCheckBlock, SkipRestart, SkipHome and GestureRatio.
// default.jsonsetting supplies events and named actions.
// appconfig.json may supply sceneLimit and cases.
@interface PGConfig : NSObject
@property (nonatomic, assign) BOOL skipCheckBlock;
@property (nonatomic, assign) BOOL skipRestart;
@property (nonatomic, assign) BOOL skipHome;
@property (nonatomic, copy) NSDictionary *gestureRatios;
@property (nonatomic, copy) NSString *channel;
@property (nonatomic, copy) NSArray *events;
@property (nonatomic, copy) NSArray *actions;
@property (nonatomic, copy) NSArray *cases;
@property (nonatomic, copy) NSArray *sceneLimits;
@property (nonatomic, copy) NSString *sceneScheme;
@property (nonatomic, copy) NSArray<NSString *> *allowViewControllers;
@property (nonatomic, copy) NSArray<NSString *> *blockViewControllers;
@property (nonatomic, assign) NSTimeInterval sceneDuration;
@property (nonatomic, copy) NSString *sceneCallbackURL;
@property (nonatomic, copy) NSString *appletSchema;
@property (nonatomic, copy) NSArray *excludeRects;
@property (nonatomic, copy) NSArray<NSString *> *excludeElements;
@property (nonatomic, copy) NSString *sceneConfigURL;
@property (nonatomic, copy) NSArray *sequences;

+ (instancetype)loadedConfig;
- (void)applyToSceneLimit:(PGSceneLimit *)sceneLimit;
- (void)applyToPreference:(PGPreference *)preference;
@end

NS_ASSUME_NONNULL_END
