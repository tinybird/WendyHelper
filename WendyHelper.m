#import <Foundation/Foundation.h>
#import "ReportManager.h"


int main(int argc, const char * argv[])
{
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];

    ReportManager *reportManager = [ReportManager sharedManager];
    
    [reportManager downloadReportsWithUsername:@"foo" password:@"bar"];
    
    while (1) {
        // Start the run loop but return after each source is handled.
        SInt32 result = CFRunLoopRunInMode(kCFRunLoopDefaultMode, 10, YES);
        
        // If a source explicitly stopped the run loop, or if there are no
        // sources or timers, go ahead and exit.
        if (result == kCFRunLoopRunStopped || result == kCFRunLoopRunFinished) {
            break;
        }
    }

    [pool drain];

    return 0;
}
