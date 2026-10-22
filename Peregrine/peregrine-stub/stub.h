#import <UIKit/UIKit.h>

// Injected into the app under test. Listens on 127.0.0.1:<stubPort> only when the
// stubPort environment variable is set. Peregrine talks to it over JSON-RPC:
//   get_ui_tree  -> result is an elem_info tree
//   kill_process -> result is true; the app stays alive
//   app_perf     -> result is a resource sample of the app (PGStubPerf.h)
//   other        -> error -32601
// To change which views appear, subclass, override shouldExposeView:, and name
// the subclass in the PGStubClass environment variable or Info.plist key.
@interface PGStub : NSObject

// Return NO to drop this view and its subtree from the tree Peregrine reads.
- (BOOL)shouldExposeView:(UIView *)view;

@end
