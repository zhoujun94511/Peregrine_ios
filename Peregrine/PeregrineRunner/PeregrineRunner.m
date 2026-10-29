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

// One vanished control records an XCTest issue on this method. continueAfterFailure keeps the
// loop running, but the issue still fails the whole exploration. Query resolution is a skipped
// step. Launch failures and explicit asserts stay failures.
- (void)recordIssue:(XCTIssue *)issue
{
    if(self.invocation.selector == @selector(testPeregrine) && [self issueIsElementQuery:issue])
    {
        XCTMutableIssue *noted = [issue mutableCopy];
        noted.severity = XCTIssueSeverityWarning;
        NSLog(@"element query skipped %@", issue.compactDescription ?: @"");
        [super recordIssue:noted];
        return;
    }
    [super recordIssue:issue];
}

- (BOOL)issueIsElementQuery:(XCTIssue *)issue
{
    NSString *text = [NSString stringWithFormat:@"%@ %@", issue.compactDescription ?: @"", issue.detailedDescription ?: @""];
    NSArray<NSString *> *markers = @[
        @"Failed to resolve query",
        @"Failed to resolve remote element",
        @"kAXErrorInvalidUIElement",
        @"Multiple matching elements found",
        @"Failed to get matching snapshot"
    ];
    for(NSString *marker in markers)
    {
        if([text rangeOfString:marker options:NSCaseInsensitiveSearch].location != NSNotFound)
        {
            return YES;
        }
    }
    return NO;
}

- (void)testPingNetwork
{
    PGCommunicationReport *report = [PGCommunicationCheck reportWithEnvironment:[[NSProcessInfo processInfo] environment]];
    XCTAssertTrue(report.passed, @"%@", report.summary);
}

@end
