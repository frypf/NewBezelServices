//
//  AppDelegate.h
//  NewBezelServices
//
//  Created by Kelian on 05/07/2015.
//  Copyright © 2015 MLforAll. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "HUDWindowController.h"
#import "VolumeKeyTap.h"

@class HUDWindowController;

@interface NSAppSubclass : NSApplication;

@property (readwrite) HUDWindowController *hudCtrl;

@end


@interface AppDelegate : NSObject <NSApplicationDelegate, NSXPCListenerDelegate>
{
    HUDWindowController *_hudCtrl;
    NSXPCListener *_listener;
    SPMediaKeyTap *keyTap;
    CGEventSourceRef _eventSource;
}
@end
