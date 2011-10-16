//
//  Utilities.m
//  WendyHelper
//
//  Created by Richard Hult on 2011-10-16.
//  Copyright (c) 2011 Tinybird Interactive AB. All rights reserved.
//

#include <sqlite3.h>
#import "Utilities.h"
#import "ASAccount.h"


@implementation Utilities

+ (NSString *)originalReportsPath
{
	NSString *path = [[ASAccount sharedAccount].path stringByAppendingPathComponent:@"OriginalReports"];
	if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
		NSError *error;
		if (![[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error]) {
			[NSException raise:NSGenericException format:@"%@", error];
		}
	}
	return path;
}

+ (NSString *)documentsPath
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return [[paths objectAtIndex:0] stringByAppendingPathComponent:@"WendyHelper"];
}

static int callback(void *daysPtr, int argc, char **argv, char **azColName)
{
    NSMutableDictionary *days = daysPtr;

    NSDateFormatter *inFormatter = [[NSDateFormatter alloc] init];
    [inFormatter setDateFormat:@"yyyy-MM-dd"];

    NSDateFormatter *outFormatter = [[NSDateFormatter alloc] init];
    [outFormatter setDateFormat:@"yyyyMMdd"];

    for (int i = 0; i < argc; i++) {
        NSDate *date = [inFormatter dateFromString:[NSString stringWithUTF8String:argv[i]]];
        NSString *string = [outFormatter stringFromDate:date];
        [days setValue:@"foo" forKey:string];
    }

    [inFormatter release];
    [outFormatter release];

    return 0;
}

+ (NSArray *)availableDays
{
    // Fill in days with the already downloaded days.
    sqlite3 *db;
    if (sqlite3_open([[[ASAccount sharedAccount].path stringByAppendingPathComponent:@"sales.sqlite"] UTF8String], &db) != SQLITE_OK) {
        fprintf(stderr, "Can't open database: %s\n", sqlite3_errmsg(db));
        sqlite3_close(db);
        exit(1);
    }

    NSMutableDictionary *days = [NSMutableDictionary dictionary];
    char *zErrMsg = NULL;
    if (sqlite3_exec(db, [@"SELECT DISTINCT date FROM sales" UTF8String], callback, days, &zErrMsg) != SQLITE_OK) {
        fprintf(stderr, "SQL error: %s\n", zErrMsg);
    }
    sqlite3_close(db);

    return [days allKeys];
}

@end
