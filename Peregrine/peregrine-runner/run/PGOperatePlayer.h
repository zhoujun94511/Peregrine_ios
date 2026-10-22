#import <XCTest/XCTest.h>
#import "PGBehavior.h"
#import "PGCaseSchedule.h"
#import "PGEventLog.h"

NS_ASSUME_NONNULL_BEGIN

// Performs one operate and writes its action events.
@interface PGOperatePlayer : NSObject
+ (BOOL)openURL:(NSURL *)url application:(XCUIApplication *)application;
+ (void)traceOperate:(PGOperate *)operate
               nodes:(NSArray<PGElementNode *> *)nodes
               inApp:(XCUIApplication *)application
               cases:(PGCaseSchedule *)cases
                 log:(PGEventLog *)log
       timeoutMillis:(NSInteger)timeoutMillis
     resolveElement:(BOOL)resolveElement
              screen:(CGSize)screen;
@end

NS_ASSUME_NONNULL_END
