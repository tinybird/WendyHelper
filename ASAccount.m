// Fake account to simplify changes in other places.

#import "ASAccount.h"


@implementation ASAccount

@synthesize username = _username;
@synthesize password = _password;
@synthesize vendorID = _vendorID;
@synthesize path = _path;
@synthesize isDownloadingReports = _isDownloadingReports;
@synthesize downloadStatus = _downloadStatus;
@synthesize downloadProgress = _downloadProgress;

+ (ASAccount *)sharedAccount
{
    static ASAccount *account;
    if (account == nil) {
        account = [[self alloc] init];
    }
    return account;
}

- (void)setDownloadStatus:(NSString *)downloadStatus
{
    [_downloadStatus release];
    _downloadStatus = [downloadStatus retain];
    printf(" %s\n", [downloadStatus UTF8String]);
}

@end
