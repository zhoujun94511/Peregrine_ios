#import <XCTest/XCTest.h>
#import "PGSession.h"

NS_ASSUME_NONNULL_BEGIN

// Drives one Peregrine session with public XCTest.
// PeregrineRunner only forwards the test into this component.
@interface PGTestRun : NSObject
+ (void)runWithEnvironment:(NSDictionary *)environment testCase:(XCTestCase *)testCase;
@end

NS_ASSUME_NONNULL_END
