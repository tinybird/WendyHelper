// Fake account to simplify changes in other places.

#import <Foundation/Foundation.h>


@interface ASAccount : NSObject

@property (nonatomic, retain) NSString *password;
@property (nonatomic, retain) NSString *username;
@property (nonatomic, retain) NSString *vendorID;
@property (nonatomic, retain) NSString *path;

@property (nonatomic, assign) BOOL isDownloadingReports;
@property (nonatomic, retain) NSString *downloadStatus;
@property (nonatomic, assign) float downloadProgress;

+ (ASAccount *)sharedAccount;

@end
