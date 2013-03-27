/******
TappEventTracker.m

Copyright (c) 2013, Tappister, LLC.
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of Tappister, LLC nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL TAPPISTER, LLC BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
******/

#import "TappEventTracker.h"

static TappEventTracker *__TappEventTracker__instance = nil;

@interface TappEventTracker () {
    NSTimeInterval _reportInterval;
}

@property (nonatomic, strong) NSMutableArray *trackedEvents;
@property (nonatomic, strong) NSTimer *reportTimer;
@property (atomic, assign) BOOL reportRequestIsActive;

- (void)logMessage:(NSString *)message, ...;
- (void)logVerboseMessage:(NSString *)message, ...;

@end

@implementation TappEventTracker


+ (TappEventTracker *)sharedInstance
{
    static dispatch_once_t onceToken = 0;

    dispatch_once(&onceToken, ^{
        __TappEventTracker__instance = [[[TappEventTracker alloc] init] retain];
    });

    return __TappEventTracker__instance;
}

+ (void)trackEvent:(NSString *)eventName
{
	[TappEventTracker trackEvent:eventName withValue:@"-"];
}

+ (void)trackEvent:(NSString *)eventName
		 withValue:(NSString *)value
{
    TappEventTracker *tracker = [TappEventTracker sharedInstance];

    @synchronized(tracker) {
        [tracker.trackedEvents addObject:[NSString stringWithFormat:@"%@[]=%@", eventName, value]];
    }
}



- (id)init
{
    self = [super init];
    if (self) {
        [self logVerboseMessage:@"Starting up"];
        
        self->_trackedEvents = [[NSMutableArray alloc] init];
        self.reportRequestIsActive = NO;
        self->_reportInterval = 60.0;
        

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidEnterBackground:)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:[UIApplication sharedApplication]];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidBecomeActive:)
                                                     name:UIApplicationDidBecomeActiveNotification
                                                   object:[UIApplication sharedApplication]];

        [self ensureReportTimerIsRunning];
    }

    return self;
}

#pragma mark -- app lifecycle monitoring

- (void)applicationDidBecomeActive:(id)data
{
    [self logVerboseMessage:@"Application has become active, restarting report timer with interval %.2f", self.reportInterval];
    
    [self ensureReportTimerIsRunning];
}

- (void)applicationDidEnterBackground:(id)data
{
    [self logVerboseMessage:@"Application is going to the background"];
    
    [self stopReportTimer];
    [self sendTrackedDataWhenBackgrounding];
}


#pragma mark -- properties

@synthesize trackedEvents = _trackedEvents;
@synthesize reportTimer = _reportTimer;
@synthesize reportRequestIsActive = _reportRequestIsActive;
@synthesize uniqueId = _uniqueId;
@synthesize reportURL = _reportURL;
@synthesize reportAtShutdown = _reportAtShutdown;
@synthesize beVerbose = _beVerbose;

- (void)setUniqueId:(NSString *)uniqueId
{
    @synchronized(self) {
        [self->_uniqueId release];
        self->_uniqueId = [uniqueId retain];
        
        [self logVerboseMessage:@"Using custom uniqueId %@", uniqueId];
    }
}
- (NSString *)uniqueId
{
    @synchronized(self) {
        if (! self->_uniqueId.length) {
            if ([[UIDevice currentDevice] respondsToSelector:@selector(identifierForVendor)]) {
                self->_uniqueId = [[[UIDevice currentDevice].identifierForVendor UUIDString] retain];

                [self logVerboseMessage:@"Using device uniqueId %@", self->_uniqueId];
            }
            else {
                self->_uniqueId = [@"Unknown" retain];

                [self logVerboseMessage:@"This device does not have a hardware uniqueId, you might want to supply your own using [TappEventTracker sharedInstance].uniqueId = @\"...\";"];
            }
        }
        return self->_uniqueId;
    }
}

- (NSTimeInterval)reportInterval
{
    @synchronized(self) {
        return self->_reportInterval;
    }
}
- (void)setReportInterval:(NSTimeInterval)interval
{
    @synchronized(self) {
        if (self->_reportInterval != interval) {
            self->_reportInterval = interval;
            [self stopReportTimer];
            [self ensureReportTimerIsRunning];
        }
    }
}


#pragma mark -- manage the report timer
- (void)ensureReportTimerIsRunning
{
    if (! [self.reportTimer isValid]) {
        self.reportTimer = [[NSTimer scheduledTimerWithTimeInterval:self.reportInterval
                                                             target:self
                                                           selector:@selector(sendTrackedData)
                                                           userInfo:[NSNumber numberWithBool:YES]
                                                            repeats:YES] retain];

        [self logVerboseMessage:@"Changing report interval to %.2f", self.reportInterval];
    }
}

- (void)stopReportTimer
{
    [self.reportTimer invalidate];
    self.reportTimer = nil;

    [self logVerboseMessage:@"Stopping report timer"];
}



#pragma mark -- Sending track data to the server


- (void)sendTrackedDataWhenBackgrounding
{
    if ([[UIDevice currentDevice] respondsToSelector:@selector(isMultitaskingSupported)]
        && [[UIDevice currentDevice] isMultitaskingSupported])
    {
        if (self.reportAtShutdown) {
            [self logVerboseMessage:@"Attempting to report before going to background"];

            UIApplication *application = [UIApplication sharedApplication];
            __block UIBackgroundTaskIdentifier background_task;

            background_task = [application beginBackgroundTaskWithExpirationHandler: ^ {
                [application endBackgroundTask:background_task];
                background_task = UIBackgroundTaskInvalid;
            }];


            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

                // the point of this method, right here...
                [self sendTrackedData];

                [application endBackgroundTask: background_task];
                background_task = UIBackgroundTaskInvalid;
            });
        }
    }
    else if (self.reportAtShutdown) {
        [self logVerboseMessage:@"This device does not support background reporting"];
    }
}

- (void)sendTrackedData
{
    // run this on a background thread
    if ([NSThread isMainThread]) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
            [self sendTrackedData];
        });
        return;
    }

    NSArray *tempData = nil;

    @synchronized(self) {
        if (self.trackedEvents.count < 1) {
            return;
        }

        if (self.reportRequestIsActive) {
            [self logMessage:@"Previous data report request is still running so I'm skipping this one. You might want to increase your reportInterval if this happens often using [TappEventTracker sharedInstance].reportInterval = %.2f;", self.reportInterval*2];
            return;
        }

        tempData = [[NSArray arrayWithArray:self.trackedEvents] retain];
        [self.trackedEvents removeAllObjects];

        self.reportRequestIsActive = YES;
    }

    [self logVerboseMessage:@"Sending data to %@", [self.reportURL absoluteString]];
    
    NSData *requestBody = [self newPostBodyFromEvents:tempData];
    [tempData release];
    NSMutableURLRequest *request = [self newReportRequestWithBody:requestBody];
    [requestBody release];

    NSHTTPURLResponse *response = nil;
    NSError *error = nil;

    NSData *responseData = [[NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error] retain];

    if (response) {
        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            switch (response.statusCode) {
                case 200:
                case 201:
                    // all good
                    [self logVerboseMessage:@"Data reported."];
                    break;

                default:
                    // NOTE we're cheating here by assuming the response is ISO Latin 1, which is a pretty forgiving
                    //      encoding but will scramble a fair amount of stuff. You may need to change the encoding
                    //      or send me a pull request that actually looks at the Content-Encoding header ;)
                    [self logMessage:@"Error reporting event data: HTTP Status %d\n\t----\n%@\n\t----",
                     response.statusCode,
                     [[[NSString alloc] initWithData:responseData encoding:NSISOLatin1StringEncoding] autorelease]];
            }
        }
        else {
            // if it's not a NSHTTPURLResponse we don't get a status code...
            [self logMessage:@"Non-HTTP response from event report: %@", response.description];
        }
    }
    else {
        if (error) {
            [self logMessage:@"Error reporting data: %d/%@\n\t----\n%@\n\t----", error.code, error.domain, error.description];
        }
        else {
            [self logMessage:@"Error reporting data (no details available)"];
        }
    }

    [responseData release];
    [request release];

    // clean up our tracker
    @synchronized(self) {
        self.reportRequestIsActive = NO;
    }
}


- (NSData *)newPostBodyFromEvents:(NSArray *)events
{
    NSMutableString *payload = [[[NSMutableString alloc] init] autorelease];

    if (self.uniqueId.length) {
        [payload appendFormat:@"unique_id=%@", self.uniqueId];
    }

    for (NSString *record in events) {
        if (payload.length) {
            [payload appendString:@"&"];
        }
        [payload appendString:record];
    }

    return [[payload dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES] retain];
}

- (NSMutableURLRequest *)newReportRequestWithBody:(NSData *)bodyData
{
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:self.reportURL];
    request.timeoutInterval = 10;
    [request setHTTPMethod:@"POST"];

    [request setHTTPBody:bodyData];
    
    return request;
}

- (void)logMessage:(NSString *)message, ...
{
    va_list args;
    va_start(args, message);
    NSLogv([@"TappEventTracker:\t" stringByAppendingString:message], args);
    va_end(args);
}
         
- (void)logVerboseMessage:(NSString *)message, ...
{
    if (self.beVerbose) {
        va_list args;
        va_start(args, message);
        NSLogv([@"TappEventTracker:\t" stringByAppendingString:message], args);
        va_end(args);
    }
}

@end
