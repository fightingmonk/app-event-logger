app-event-logger
================

A simple iOS mobile app event logger / flight data recorder

# How it works

You upload tapp-tracker.php to your web server, add the TappEventTracker class to your iOS app, configure it when your app starts, and when you have something to track you call 

`[TappEventTracker trackEvent:@"my_event" withValue:@"value"];`

TappEventTracker takes care of periodically pushing your tracked events to the server and you get a nice CSV with timestamp, client IP address, device id, and event info. You can process it, parse it, or load it into Google Docs if you're of a mind to.

# Installing the PHP tracker

To use the tapp-tracker.php script you will need a web hosting account or server with PHP 5. Simply customize the log file path and name in the script if desired and then upload the script into your web site account.

You may want to specify a directory for your log files that is not within your web site's html files area, otherwise people may be able to retrieve your log files through your web server.

# Installing the iOS library

Add `TappEventTracker.h` and `TappEventTracker.m` to your iOS app in Xcode. If you are using ARC for your project (you probably are if you don't know what that is) then you will need to disable ARC for the TappEventTracker.m file:
* Click on your project name in the Project Navigator
* Under Targets select your app name
* Select the Build Phases tab
* Expand the Compile Sources section
* Double-click on TappEventTracker.m
* In the popup add the test `-fno-objc-arc`

# Using the iOS library

At the top of your AppDelegate.m file include the TappEventTracker header:

```#include "TappEventTracker.h"
```

In your AppDelegate's application:didFinishLaunchingWithOptions: method configure the tracking service:

```// You can set this to YES to log lots of messages to the console via NSLog()
[TappEventTracker sharedInstance].beVerbose = NO;
// Point this to the tracker script you installed on your web site
[TappEventTracker sharedInstance].reportURL = [NSURL URLWithString:@"http://www.example.com/path/to/tapp-tracker.php"];
// Control whether to perform a last-minute data push when the app goes to the background
[TappEventTracker sharedInstance].reportAtShutdown = YES;
// Control how many seconds elapse between attempts to push data up to the server
[TappEventTracker sharedInstance].reportInterval = 60;
```

Whenever you need to record an event simply call:

```[TappEventTracker trackEvent:@"MY_EVENT_NAME"];
```

or

```[TappEventTracker trackEvent:@"MY_EVENT_NAME" withValue:@"VALUE"];
```

