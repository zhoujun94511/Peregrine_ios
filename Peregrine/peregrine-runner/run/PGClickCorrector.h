#import <XCTest/XCTest.h>
#import "PGBehavior.h"
#import "PGStepScreen.h"

NS_ASSUME_NONNULL_BEGIN

// Result of correcting one screenshot click with a public snapshot.
@interface PGClickCorrection : NSObject
@property (nonatomic, strong) PGOperate *operate;
@property (nonatomic, copy) NSArray<PGElementNode *> *nodes;
@property (nonatomic, copy, nullable) NSString *pageName;
@property (nonatomic, assign) BOOL outside;
@property (nonatomic, assign) BOOL slow;
@property (nonatomic, assign) BOOL corrected;
@end

// Asks for a snapshot only when a click has no name or is a thin strip.
@interface PGClickCorrector : NSObject
- (BOOL)allowsCorrectionForOperate:(PGOperate *)operate modelClick:(BOOL)modelClick usePoints:(BOOL)usePoints correctionDone:(BOOL)correctionDone;
- (PGClickCorrection *)correctOperate:(PGOperate *)operate application:(XCUIApplication *)application screen:(PGStepScreen *)screen pixelNodes:(nullable NSArray<PGElementNode *> *)pixelNodes pixelSize:(CGSize)pixelSize;
@end

NS_ASSUME_NONNULL_END
