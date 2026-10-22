#import <XCTest/XCTest.h>
#import "PGTestRun.h"
#import "PGCommunicationCheck.h"

@interface PeregrineRunner : XCTestCase
@end

@implementation PeregrineRunner

- (void)testPeregrine
{
    [PGTestRun runWithEnvironment:[[NSProcessInfo processInfo] environment] testCase:self];
}

- (void)testPingNetwork
{
    PGCommunicationReport *report = [PGCommunicationCheck reportWithEnvironment:[[NSProcessInfo processInfo] environment]];
    XCTAssertTrue(report.passed, @"%@", report.summary);
}

@end
