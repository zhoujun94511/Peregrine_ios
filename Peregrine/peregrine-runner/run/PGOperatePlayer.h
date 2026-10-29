#import <XCTest/XCTest.h>
#import "PGBehavior.h"
#import "PGCaseSchedule.h"
#import "PGEventLog.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PGOperateResult) {
    PGOperateResultSuccess = 0,
    PGOperateResultTargetNotFound,
    PGOperateResultExecutionFailed,
    PGOperateResultSkipped,
};

// Performs one operate and writes its action events.
@interface PGOperatePlayer : NSObject
+ (BOOL)openURL:(NSURL *)url application:(XCUIApplication *)application;
+ (PGOperateResult)traceOperate:(PGOperate *)operate
               nodes:(NSArray<PGElementNode *> *)nodes
               inApp:(XCUIApplication *)application
               cases:(PGCaseSchedule *)cases
                 log:(PGEventLog *)log
       timeoutMillis:(NSInteger)timeoutMillis
     resolveElement:(BOOL)resolveElement
              screen:(CGSize)screen;
@end

NS_ASSUME_NONNULL_END
