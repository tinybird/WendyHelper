#import <Foundation/Foundation.h>
#import "ReportManager.h"


int main(int argc, const char *argv[])
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    BOOL getPath = NO;
    BOOL getUsername = NO;
    BOOL getPassword = NO;
    NSString *path = nil;
    NSString *username = nil;
    NSString *password = nil;
    for (int i = 1; i < argc; i++) {
        NSString *string = [NSString stringWithUTF8String:argv[i]];
        if (getPath) {
            path = string;
            getPath = NO;
        }
        else if (getUsername) {
            username = string;
            getUsername = NO;
        }
        else if (getPassword) {
            password = string;
            getPassword = NO;
        }
        else if (strcmp(argv[i], "-d") == 0) {
            getPath = YES;
            getUsername = NO;
            getPassword = NO;
        }
        else if (strcmp(argv[i], "-u") == 0) {
            getPath = NO;
            getUsername = YES;
            getPassword = NO;
        }
        else if (strcmp(argv[i], "-p") == 0) {
            getPath = NO;
            getUsername = NO;
            getPassword = YES;
        }
    }

    if (path == nil || username == nil || password == nil) {
        fprintf(stderr, "Usage: %s -d <path to sales database> -u <username> -p <password>\n", argv[0]);
        return 1;
    }
    
    ReportManager *reportManager = [[ReportManager alloc] init];
    reportManager.basePath = path;

    [reportManager downloadReportsWithUsername:username password:password];

    [[NSRunLoop mainRunLoop] run];

    [reportManager release];
    
    [pool drain];

    return 0;
}
