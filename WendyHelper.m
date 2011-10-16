#import <Foundation/Foundation.h>
#import "ASAccount.h"
#import "ReportDownloadOperation.h"


int main(int argc, const char *argv[])
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    ASAccount *account = [ASAccount sharedAccount];

    BOOL getPath = NO;
    BOOL getUsername = NO;
    BOOL getPassword = NO;
    BOOL getVendorID = NO;
    for (int i = 1; i < argc; i++) {
        NSString *string = [NSString stringWithUTF8String:argv[i]];
        if (getPath) {
            account.path = string;
            getPath = NO;
        }
        else if (getUsername) {
            account.username = string;
            getUsername = NO;
        }
        else if (getPassword) {
            account.password = string;
            getPassword = NO;
        }
        else if (getVendorID) {
            account.vendorID = string;
            getVendorID = NO;
        } else {
            getPath = NO;
            getUsername = NO;
            getPassword = NO;
            getVendorID = NO;

            if (strcmp(argv[i], "-d") == 0) {
                getPath = YES;
            }
            else if (strcmp(argv[i], "-u") == 0) {
                getUsername = YES;
            }
            else if (strcmp(argv[i], "-p") == 0) {
                getPassword = YES;
            }
            else if (strcmp(argv[i], "-i") == 0) {
                getVendorID = YES;
            }
        }
    }

    if (account.path == nil || account.username == nil || account.password == nil || account.vendorID == nil) {
        fprintf(stderr, "Usage: %s -d <path to sales database> -u <username> -p <password> -i <vendorID>\n", argv[0]);
        return 1;
    }

    NSString *path = [account.path stringByAppendingPathComponent:@"OriginalReports"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        NSError *error;
        if (![[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error]) {
            fprintf(stderr, "Couldn't create reports directory\n");
            return 1;
        }
    }

    NSOperationQueue *reportDownloadQueue = [[NSOperationQueue alloc] init];
    reportDownloadQueue.maxConcurrentOperationCount = 1;

    ReportDownloadOperation *operation = [[[ReportDownloadOperation alloc] initWithAccount:account] autorelease];
    account.isDownloadingReports = YES;
    account.downloadStatus = NSLocalizedString(@"Waiting...", nil);
    account.downloadProgress = 0.0;

    __block BOOL shouldKeepRunning = YES;

    [operation setCompletionBlock:^ {
        dispatch_async(dispatch_get_main_queue(), ^ {
            account.isDownloadingReports = NO;
            shouldKeepRunning = NO;
        });
    }];
    [reportDownloadQueue addOperation:operation];

    NSRunLoop *loop = [NSRunLoop currentRunLoop];
    while (shouldKeepRunning && [loop runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]]) {
        // ...
    }

    [reportDownloadQueue release];

    printf("Done.\n");

    [pool drain];

    return 0;
}
