//
//  ReportManager.m
//  AppSalesMobile
//
//  Created by Ole Zorn on 10.09.09.
//  Copyright 2009 omz:software. All rights reserved.
//

#include <sqlite3.h>
#import "ReportManager.h"
#import "NSDictionary+HTTP.h"
#import "RegexKitLite.h"


@implementation ReportManager

@synthesize days, weeks, basePath;

- (NSString *)documentsPath
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
    [outFormatter setDateFormat:@"MM/dd/yyyy"];

    for (int i = 0; i < argc; i++) {
        NSDate *date = [inFormatter dateFromString:[NSString stringWithUTF8String:argv[i]]];
        NSString *string = [outFormatter stringFromDate:date];
        [days setValue:@"foo" forKey:string];
    }
    
    [inFormatter release];
    [outFormatter release];

    return 0;
}

- (void)readDays
{
    // Fill in days with the already downloaded days.
    sqlite3 *db;
    if (sqlite3_open([[basePath stringByAppendingPathComponent:@"sales.sqlite"] UTF8String], &db) != SQLITE_OK) {
        fprintf(stderr, "Can't open database: %s\n", sqlite3_errmsg(db));
        sqlite3_close(db);
        exit(1);
    }

    char *zErrMsg = NULL;
    if (sqlite3_exec(db, [@"SELECT DISTINCT date FROM sales" UTF8String], callback, days, &zErrMsg) != SQLITE_OK) {
        fprintf(stderr, "SQL error: %s\n", zErrMsg);
    }
    sqlite3_close(db);
}

- (id)init
{
	self = [super init];
	if (self) {
		days = [NSMutableDictionary new];
		weeks = [NSMutableDictionary new];
        basePath = [[self documentsPath] copy];
	}
	return self;
}

- (void)dealloc
{
	[days release];
	[weeks release];
    [basePath release];
	
	[super dealloc];
}

- (void)setProgress:(NSString *)status
{
    fprintf(stdout, "Status: %s\n", [status UTF8String]);
}

- (NSString *)originalReportsPath
{
	NSString *path = [basePath stringByAppendingPathComponent:@"OriginalReports"];
	if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
		NSError *error;
		if (![[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error]) {
			[NSException raise:NSGenericException format:@"%@", error];
		}
	}
	return path;
}

#pragma mark -
#pragma mark Report Download
- (void)downloadReportsWithUsername:(NSString *)username password:(NSString *)password
{
	if ([username length] == 0 || [password length] == 0) {
		fprintf(stderr, "Missing username/password");
		return;
	}

    [self readDays];

	NSArray *daysToSkip = [days allKeys];
	NSArray *weeksToSkip = [weeks allKeys];
	NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
							  username, @"username", 
							  password, @"password", 
							  weeksToSkip, @"weeksToSkip", 
							  daysToSkip, @"daysToSkip", 
							  [self originalReportsPath], @"originalReportsPath",
                              nil];
	[self performSelectorInBackground:@selector(fetchReportsWithUserInfo:) withObject:userInfo];
}

#define ITTS_VENDOR_DEFAULT_URL @"https://reportingitc.apple.com/vendor_default.faces"
#define ITTS_SALES_PAGE_URL @"https://reportingitc.apple.com/sales.faces"

static NSMutableArray *extractFormOptions(NSString *htmlPage, NSString *formID)
{
    NSScanner *scanner = [NSScanner scannerWithString:htmlPage];
    NSString *selectionForm = nil;
    [scanner scanUpToString:formID intoString:nil];
    if (! [scanner scanString:formID intoString:nil]) {
        return nil;
    }
    [scanner scanUpToString:@"</select>" intoString:&selectionForm];
    if (! [scanner scanString:@"</select>" intoString:nil]) {
        return nil;
    }
    
    NSMutableArray *options = [NSMutableArray array];
    NSScanner *selectionScanner = [NSScanner scannerWithString:selectionForm];
    while ([selectionScanner scanUpToString:@"<option value=\"" intoString:nil] && [selectionScanner scanString:@"<option value=\"" intoString:nil]) {
        NSString *selectorValue = nil;
        [selectionScanner scanUpToString:@"\"" intoString:&selectorValue];
        if (! [selectionScanner scanString:@"\"" intoString:nil]) {
            return nil;
        }
        
        [options addObject:selectorValue];
    }
    return options;
}

static NSData *getPostRequestAsData(NSString *urlString, NSDictionary *postDict, NSHTTPURLResponse **downloadResponse)
{
    NSString *postDictString = [postDict formatForHTTP];
    NSData *httpBody = [postDictString dataUsingEncoding:NSASCIIStringEncoding];
    NSMutableURLRequest *urlRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    [urlRequest setHTTPMethod:@"POST"];
    [urlRequest setHTTPBody:httpBody];
    return [NSURLConnection sendSynchronousRequest:urlRequest returningResponse:downloadResponse error:NULL];
}

static NSString *getPostRequestAsString(NSString *urlString, NSDictionary *postDict)
{
    return [[[NSString alloc] initWithData:getPostRequestAsData(urlString, postDict, nil) encoding:NSUTF8StringEncoding] autorelease];
}

static NSString *parseViewState(NSString *htmlPage)
{
    return [htmlPage stringByMatching:@"\"javax.faces.ViewState\" value=\"(.*?)\"" capture:1];
}

// code path shared for both day and week downloads
static BOOL downloadReport(NSString *originalReportsPath, NSString *ajaxName, NSString *dayString, 
                           NSString *weekString, NSString *selectName, NSString **viewState, BOOL *error)
{
    // set the date within the web page
    NSDictionary *postDict = [NSDictionary dictionaryWithObjectsAndKeys:
                              ajaxName, @"AJAXREQUEST",
                              @"theForm", @"theForm",
                              @"theForm:xyz", @"notnormal",
                              @"Y", @"theForm:vendorType",
                              dayString, @"theForm:datePickerSourceSelectElementSales",
                              weekString, @"theForm:weekPickerSourceSelectElement",
                              *viewState, @"javax.faces.ViewState",
                              selectName, selectName,
                              nil];
    NSString *responseString = getPostRequestAsString(ITTS_SALES_PAGE_URL, postDict);
    *viewState = parseViewState(responseString);
    
    // iTC shows a (fixed?) number of date ranges in the form, even if all of them are not available 
    // if trying to download a report that doesn't exist, it'll return an error page instead of the report
    if ([responseString rangeOfString:@"theForm:errorPanel"].location != NSNotFound) {
        return NO;
    }
    
    // and finally...we're ready to download the report
    postDict = [NSDictionary dictionaryWithObjectsAndKeys:
                @"theForm", @"theForm",
                @"notnormal", @"theForm:xyz",
                @"Y", @"theForm:vendorType",
                dayString, @"theForm:datePickerSourceSelectElementSales",
                weekString, @"theForm:weekPickerSourceSelectElement",
                *viewState, @"javax.faces.ViewState",
                @"theForm:downloadLabel2", @"theForm:downloadLabel2",
                nil];
    NSHTTPURLResponse *downloadResponse = nil;
    NSData *requestResponseData = getPostRequestAsData(ITTS_SALES_PAGE_URL, postDict, &downloadResponse);
    NSString *originalFilename = [[downloadResponse allHeaderFields] objectForKey:@"Filename"];
    if (originalFilename) {
        [requestResponseData writeToFile:[originalReportsPath stringByAppendingPathComponent:originalFilename] atomically:YES];
        return YES;
    } else {
        responseString = [[[NSString alloc] initWithData:requestResponseData encoding:NSUTF8StringEncoding] autorelease];
        fprintf(stderr, "unexpected response: %s", [responseString UTF8String]);
        *error = YES;
        return NO;
    }   
}

- (void)fetchReportsWithUserInfo:(NSDictionary *)userInfo
{
	NSAutoreleasePool *pool = [NSAutoreleasePool new];
    NSScanner *scanner;
    [self performSelectorOnMainThread:@selector(setProgress:) withObject:NSLocalizedString(@"Starting Download...",nil) waitUntilDone:NO];
 
    NSArray *daysToSkip = [userInfo objectForKey:@"daysToSkip"];
    
#if 0
	NSArray *daysToSkipDates = [userInfo objectForKey:@"daysToSkip"];
	NSArray *weeksToSkipDates = [userInfo objectForKey:@"weeksToSkip"];
	NSMutableArray *daysToSkip = [NSMutableArray array];

	NSMutableArray *weeksToSkip = [NSMutableArray array];
	NSDateFormatter *nameFormatter = [[[NSDateFormatter alloc] init] autorelease];
	[nameFormatter setDateFormat:@"MM/dd/yyyy"];
	for (NSDate *date in daysToSkipDates) {
		NSString *dayName = [nameFormatter stringFromDate:date];
		[daysToSkip addObject:dayName];
	}
	for (NSDate *date in weeksToSkipDates) {
		NSDate *toDate = [[[NSDate alloc] initWithTimeInterval:60*60*24*6.5 sinceDate:date] autorelease];
		NSString *weekName = [nameFormatter stringFromDate:toDate];
		[weeksToSkip addObject:weekName];
	}
#endif

	NSString *originalReportsPath = [userInfo objectForKey:@"originalReportsPath"];
	NSString *username = [userInfo objectForKey:@"username"];
	NSString *password = [userInfo objectForKey:@"password"];
	
    NSString *ittsBaseURL = @"https://itunesconnect.apple.com";
	NSString *ittsLoginPageAction = @"/WebObjects/iTunesConnect.woa";
    NSString *signoutSentinel = @"name=\"signOutForm\"";
    
    NSURL *loginURL = [NSURL URLWithString:[ittsBaseURL stringByAppendingString:ittsLoginPageAction]];
    NSString *loginPage = [NSString stringWithContentsOfURL:loginURL usedEncoding:NULL error:NULL];
    if ([loginPage rangeOfString:signoutSentinel].location == NSNotFound) {
        [self performSelectorOnMainThread:@selector(setProgress:) withObject:NSLocalizedString(@"Logging in...",nil) waitUntilDone:NO];
        
        // find the login action
        scanner = [NSScanner scannerWithString:loginPage];
        [scanner scanUpToString:@"action=\"" intoString:nil];
        if (! [scanner scanString:@"action=\"" intoString:nil]) {
            [self performSelectorOnMainThread:@selector(downloadFailed:) withObject:@"could not parse iTunes Connect login page" waitUntilDone:NO];
            [pool release];
            return;
        }
        NSString *loginAction = nil;
        [scanner scanUpToString:@"\"" intoString:&loginAction];
        
        NSDictionary *postDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                  username, @"theAccountName",
                                  password, @"theAccountPW", 
                                  @"39", @"1.Continue.x", // coordinates of submit button on screen.  any values seem to work
                                  @"7", @"1.Continue.y",
                                  nil];
        loginPage = getPostRequestAsString([ittsBaseURL stringByAppendingString:loginAction], postDict);
        if (loginPage == nil || [loginPage rangeOfString:signoutSentinel].location == NSNotFound) {
            [self performSelectorOnMainThread:@selector(downloadFailed:) withObject:@"could not load iTunes Connect login page" waitUntilDone:NO];
            [pool release];
            return;
        }
    } // else, already logged in
    
    NSString *salesAction = [loginPage stringByMatching:@"/WebObjects/iTunesConnect.woa/wo/[0-9]\\.0\\.9\\.7\\.2\\.9\\.1\\.0\\.0\\.[0-9]"];
    if (salesAction.length == 0) {
        [self performSelectorOnMainThread:@selector(downloadFailed:) withObject:@"could parse sales/trend action" waitUntilDone:NO];
        [pool release];
        return;
    }
    
    // load sales/trends page.
    NSError *error = nil;
    NSString *salesRedirectPage = [NSString stringWithContentsOfURL:[NSURL URLWithString:[ittsBaseURL stringByAppendingString:salesAction]]
                                                       usedEncoding:NULL error:&error];
    if (error) {
        NSLog(@"unexpected error: %@", salesRedirectPage);
        [self performSelectorOnMainThread:@selector(downloadFailed:) withObject:@"could not load iTunes Connect sales/trend page" waitUntilDone:NO];
        [pool release];
        return;
    }
    
    scanner = [NSScanner scannerWithString:salesRedirectPage];
    NSString *viewState = parseViewState(salesRedirectPage);
    //[scanner scanUpToString:@"script id=\"defaultVendorPage:" intoString:nil];
    [scanner scanUpToString:@"script id=\"defaultVendorPage:" intoString:nil];
    if (! [scanner scanString:@"script id=\"defaultVendorPage:" intoString:nil]) {
        [self performSelectorOnMainThread:@selector(downloadFailed:) withObject:@"could not parse sales redirect page" waitUntilDone:NO];
        [pool release];
        return;
    }
    NSString *defaultVendorPage = nil;
    [scanner scanUpToString:@"\"" intoString:&defaultVendorPage];

    // click though from the dashboard to the sales page
    NSDictionary *reportPostData = [NSDictionary dictionaryWithObjectsAndKeys:
                                    [defaultVendorPage stringByReplacingOccurrencesOfString:@"_2" withString:@"_0"], @"AJAXREQUEST",
                                    viewState, @"javax.faces.ViewState",
                                    defaultVendorPage, @"defaultVendorPage",
                                    [@"defaultVendorPage:" stringByAppendingString:defaultVendorPage],[@"defaultVendorPage:" stringByAppendingString:defaultVendorPage],
                                    nil];
    NSString *reportResponse = getPostRequestAsString(ITTS_VENDOR_DEFAULT_URL, reportPostData);
    
    // get the form field names needed to download the report
    NSString *salesPage = [NSString stringWithContentsOfURL:[NSURL URLWithString:ITTS_SALES_PAGE_URL] usedEncoding:NULL error:NULL];
    if (salesPage.length == 0) {
        NSLog(@"cannot load sales page: %@", salesPage);
        [self performSelectorOnMainThread:@selector(downloadFailed:) withObject:@"could not load sales/trends page" waitUntilDone:NO];
        [pool release];
        return;
    }

    viewState = parseViewState(salesPage);    
    NSString *dailyName = [salesPage stringByMatching:@"theForm:j_id_jsp_[0-9]*_6"];
    NSString *weeklyName = [dailyName stringByReplacingOccurrencesOfString:@"_6" withString:@"_22"];
    NSString *ajaxName = [dailyName stringByReplacingOccurrencesOfString:@"_6" withString:@"_2"];
    NSString *daySelectName = [dailyName stringByReplacingOccurrencesOfString:@"_6" withString:@"_32"];
    NSString *weekSelectName = [dailyName stringByReplacingOccurrencesOfString:@"_6" withString:@"_35"];
    
    // parse days available
    NSMutableArray *availableDays = extractFormOptions(salesPage, @"theForm:datePickerSourceSelectElement");
    if (availableDays == nil) {
        NSLog(@"cannot find selection form: %@", salesPage);
        [self performSelectorOnMainThread:@selector(downloadFailed:) withObject:@"unexpected date selector html form" waitUntilDone:NO];
        [pool release];
        return;
    }
#if 0
    NSString *arbitraryDay = [availableDays objectAtIndex:0];
#endif
    [availableDays removeObjectsInArray:daysToSkip];
    [availableDays sortUsingSelector:@selector(compare:)]; // download older reports first
    
    // parse weeks available
    NSMutableArray *availableWeeks = extractFormOptions(salesPage, @"theForm:weekPickerSourceSelectElement");
    if (availableWeeks == nil) {
        NSLog(@"cannot find selection form: %@", salesPage);
        [self performSelectorOnMainThread:@selector(downloadFailed:) withObject:@"unexpected week selector html form" waitUntilDone:NO];
        [pool release];
        return;
    }
    NSString *arbitraryWeek = [availableWeeks objectAtIndex:0];
#if 0
    [availableWeeks removeObjectsInArray:weeksToSkip];
    [availableWeeks sortUsingSelector:@selector(compare:)];
#endif    
    
    // click though from the dashboard to the sales page
    NSDictionary *postDict = [NSDictionary dictionaryWithObjectsAndKeys:
                              ajaxName, @"AJAXREQUEST",
                              @"theForm", @"theForm",
                              @"notnormal", @"theForm:xyz",
                              @"Y", @"theForm:vendorType",
                              viewState, @"javax.faces.ViewState",
                              dailyName, dailyName,
                              nil];
    NSString *responseString = getPostRequestAsString(ITTS_SALES_PAGE_URL, postDict);
    viewState = parseViewState(responseString);
    
    // download daily reports
    int count = 1;
    for (NSString *dayString in availableDays) {
        NSString *progressMessage = [NSString stringWithFormat:NSLocalizedString(@"Downloading day %d of %d",nil), count, availableDays.count];
        count++;
        [self performSelectorOnMainThread:@selector(setProgress:) withObject:progressMessage waitUntilDone:NO];
        BOOL error = false;
        BOOL day = downloadReport(originalReportsPath, ajaxName, dayString, arbitraryWeek, daySelectName, &viewState, &error);
        if (day) {
            [self performSelectorOnMainThread:@selector(successfullyDownloadedDay:) withObject:dayString waitUntilDone:NO];            
        } else if (error) {
            NSString *message = [@"could not download " stringByAppendingString:dayString];
            [self performSelectorOnMainThread:@selector(downloadFailed:) withObject:message waitUntilDone:NO];
            [pool release];
            return;            
        }
    }
    
#if 0
    // change to weeks instead of days
    if (false) { // this currently does not appear to be needed
        postDict = [NSDictionary dictionaryWithObjectsAndKeys:
                    ajaxName, @"AJAXREQUEST",
                    @"theForm", @"theForm",
                    @"notnormal", @"theForm:xyz",
                    @"Y", @"theForm:vendorType",
                    viewState, @"javax.faces.ViewState",
                    weeklyName, weeklyName,
                    nil];
        responseString = getPostRequestAsString(ITTS_SALES_PAGE_URL, postDict);
        viewState = parseViewState(responseString);
    }
    
    // download weekly reports
    count = 1;
    for (NSString *weekString in availableWeeks) {
        NSString *progressMessage = [NSString stringWithFormat:NSLocalizedString(@"Downloading week %d of %d",nil), count, availableWeeks.count];
        count++;
        [self performSelectorOnMainThread:@selector(setProgress:) withObject:progressMessage waitUntilDone:NO];
        BOOL error = false;
        Day *week = downloadReport(originalReportsPath, ajaxName, arbitraryDay, weekString, weekSelectName, &viewState, &error);
        if (week) {
            [self performSelectorOnMainThread:@selector(successfullyDownloadedWeek:) withObject:week waitUntilDone:NO];   
        } else if (error) {
            NSString *message = [@"could not download " stringByAppendingString:weekString];
            [self performSelectorOnMainThread:@selector(downloadFailed:) withObject:message waitUntilDone:NO];
            [pool release];
            return;
        }
    }
#endif
    
	if (availableDays.count == 0/* && availableWeeks.count == 0*/) {
		[self performSelectorOnMainThread:@selector(setProgress:) withObject:NSLocalizedString(@"No new reports found",nil) waitUntilDone:NO];
	} else {
		[self performSelectorOnMainThread:@selector(setProgress:) withObject:@"" waitUntilDone:NO];
		//[self performSelectorOnMainThread:@selector(saveData) withObject:nil waitUntilDone:NO];

	} 
    
	[self performSelectorOnMainThread:@selector(finishFetchingReports) withObject:nil waitUntilDone:NO];
	[pool release];
}

- (void) finishFetchingReports
{
    fprintf(stdout, "Finished downloading\n");
    exit(0);
}

- (void)downloadFailed:(NSString *)error
{
    NSAssert([NSThread isMainThread], nil);
	NSString *message = @"check your username, password and internet connection.";
	if (error) {
		message = error;
	}
    fprintf(stderr, "Download failed: %s\n", [message UTF8String]);
    exit(1);
}

- (void)successfullyDownloadedDay:(NSString *)day
{
    fprintf(stdout, "Downloaded day: %s\n", [day UTF8String]);
}

@end
