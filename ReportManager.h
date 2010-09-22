//
//  ReportManager.h
//  AppSalesMobile
//
//  Created by Ole Zorn on 10.09.09.
//  Copyright 2009 omz:software. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface ReportManager : NSObject {
	NSMutableDictionary *days;
	NSMutableDictionary *weeks;
    NSString *basePath;
}

@property(readonly) NSDictionary *days;
@property(readonly) NSDictionary *weeks;
@property(copy) NSString *basePath;

- (void)downloadReportsWithUsername:(NSString *)username password:(NSString *)password;

@end
