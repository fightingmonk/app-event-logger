//
//  WW404Tracker.h
//  weetwoo
//
//  Created by Jonathan Karon on 3/6/13.
//
//

#import <Foundation/Foundation.h>

@interface TappEventTracker : NSObject

@property (atomic, strong) NSString *uniqueId;
@property (atomic, strong) NSURL *reportURL;
@property (atomic, assign) BOOL reportAtShutdown;
@property (atomic, assign) NSTimeInterval reportInterval;
@property (atomic, assign) BOOL beVerbose;



+ (TappEventTracker *)sharedInstance;

+ (void)trackEvent:(NSString *)eventName;
+ (void)trackEvent:(NSString *)eventName withValue:(NSString *)value;



@end
