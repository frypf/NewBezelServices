//
//  AppDelegate.m
//  NewBezelServices
//
//  Created by Kelian on 05/07/2015.
//  Copyright © 2015 MLforAll. All rights reserved.
//

#import "AppDelegate.h"
#import "OSDUIHelper.h"
#import "VolumeControl.h"
#import "BrightnessControl.h"
#import "HUDWindowController.h"

#define kPrefs [NSUserDefaults standardUserDefaults]

@implementation NSAppSubclass
-(void)sendEvent:(NSEvent *)theEvent
{
    if([theEvent type] == NSEventTypeSystemDefined && [theEvent subtype] == SPSystemDefinedEventMediaKeys) {
        [(id)[self delegate] mediaKeyTap:nil receivedMediaKeyEvent:theEvent];
    }
    [super sendEvent:theEvent];
}
@end

#pragma mark -
@implementation AppDelegate
-(void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];

    _hudCtrl = [[HUDWindowController alloc] initWithWindowNibName:@"HUDWindow"];
    [_hudCtrl loadWindow];
    
#ifdef DEBUG
    NSLog(@"debugging…");
    NSLog(@"key remap is %@ at startup", [kPrefs boolForKey:@"RemapKeys"] ? @"ON" : @"OFF");
    [(NSAppSubclass *)NSApp setHudCtrl:_hudCtrl];
#else
    _listener = [[NSXPCListener alloc] initWithMachServiceName:@"com.apple.OSDUIHelper"];
    [_listener setDelegate:self];
    [_listener resume];
#endif
    
    /// functionality to remap volume keys to smaller increments
    keyTap = [[SPMediaKeyTap alloc] initWithDelegate:self];
    _eventSource = [keyTap eventSource];

    BOOL keyTapEnabled = [self toggleKeyTap:([kPrefs boolForKey:@"RemapKeys"] == 1)];
    [kPrefs setBool:keyTapEnabled forKey:@"RemapKeys"];
    [kPrefs synchronize];

    /// watch for changes to Accessibility access
    [[NSDistributedNotificationCenter defaultCenter] addObserver:self
                    selector:@selector(accessibilityChanged)
                    name:@"com.apple.accessibility.api"
                    object:nil
                    suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];

    /// watch for changes to defaults preference for key remapping
    [kPrefs addObserver:self
             forKeyPath:@"RemapKeys"
                options:NSKeyValueObservingOptionNew
                context:NULL];
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context
{
    BOOL newPref = [[change objectForKey:NSKeyValueChangeNewKey] boolValue];
    NSLog(@"key remap switched %@", newPref ? @"ON" : @"OFF");
    newPref = [self toggleKeyTap:newPref];
    [kPrefs setBool:newPref forKey:@"RemapKeys"];
    [kPrefs synchronize];
}

-(BOOL)toggleKeyTap:(BOOL)pref
{
    BOOL shouldEnableKeyTap = pref;
    NSString *keyBehaviour = @"standard increments";
    
    if (shouldEnableKeyTap) {
        shouldEnableKeyTap = [self accessibilityStatus];
        if (!shouldEnableKeyTap) {
            [self accessibilityRequest];
        }
    }
    
    if (shouldEnableKeyTap) {
        keyBehaviour = @"small increments";
        [keyTap startWatchingMediaKeys];
        NSLog(@"key remap START");
    } else {
        [keyTap stopWatchingMediaKeys];
        NSLog(@"key remap STOP");
    }
    
    [self->_hudCtrl showHUDForAction:kBezelActionVolume sliderFilled:0.0f sliderMax:0.0f textStringValue:keyBehaviour];
    return shouldEnableKeyTap;
}

#pragma mark - Accessibility Access
/// (required for key remapping on 10.14)
-(BOOL)accessibilityStatus
{
    NSDictionary *options = @{(id)CFBridgingRelease(kAXTrustedCheckOptionPrompt): @NO};
    BOOL accessibilityAccess = AXIsProcessTrustedWithOptions((CFDictionaryRef)options);
    return accessibilityAccess;
}

-(void)accessibilityChanged
{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        BOOL newPref = [self accessibilityStatus];
        NSLog(@"accessibility access switched %@", newPref ? @"ON" : @"OFF");
        [kPrefs setBool:newPref forKey:@"RemapKeys"];
        [kPrefs synchronize];
    });
}

-(void)accessibilityRequest
/// uses applescript / shell to grant access if SIP is disabled, if not then just opens Security-Accessibility prefpane
{
    NSLog(@"requesting accessibility access");
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    
    NSString *accessibilityGrantShell = [NSString stringWithFormat:@"sudo sqlite3 <<EOF\n.open '/Library/Application Support/com.apple.TCC/TCC.db'\ndelete from access where client='com.mlforall.NewBezelServices';\ninsert or replace into access values('kTCCServiceAccessibility','%@',0,1,1,NULL,NULL,NULL,'UNUSED',NULL,0,$(date +%%s));\n.quit\nEOF", [[NSBundle mainBundle] bundleIdentifier]];
    
    NSAppleScript* accessibilityAskApplescript = [[NSAppleScript alloc] initWithSource:[NSString stringWithFormat:@"\
        display dialog \"Accessibility permission is required to remap standard volume key behaviour to smaller increments.\" buttons {\"Grant\", \"Deny\"} default button \"Grant\" cancel button \"Deny\" with title \"NewBezelServices\" with icon \"System:Library:PreferencePanes:Sound.prefPane:Contents:Resources:SoundPref.icns\" as alias \n\
        if (do shell script \"csrutil status\") is \"System Integrity Protection status: disabled.\" then \n\
        do shell script \"%@\" with administrator privileges \n\
        return 1 \n\
        else \n\
        tell application \"System Preferences\" \n reveal anchor \"Privacy_Accessibility\" of pane id \"com.apple.preference.security\" \n activate \n end tell \n\
        return 0 \n\
        end if", accessibilityGrantShell]];
/// possible useful icons for dialog:
///     \"System:Library:PreferencePanes:UniversalAccessPref.prefPane:Contents:Resources:UniversalAccessPref.icns\"
///     \"System:Library:CoreServices:CoreTypes.bundle:Contents:Resources:LockedIcon.icns\"
///     \"System:Library:PreferencePanes:Sound.prefPane:Contents:Resources:SoundPref.icns\"

    NSDictionary *errors = nil;
    NSAppleEventDescriptor *result = [accessibilityAskApplescript executeAndReturnError:&errors];
    BOOL accessibilityAccess = [result booleanValue];
    accessibilityAskApplescript = nil;
//    NSLog(@"result: %@", result);
//    NSLog(@"errors: %@", errors);

    [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    NSLog(@"accessibility access %@", accessibilityAccess ? @"GRANTED" : @"DENIED");
    
    /// an app restart is necessary to properly register permission if granted via shell
    /// release version can rely on launchctl to restart and maintain XPC handling
    if (accessibilityAccess) {
#ifdef DEBUG
        /// use applescript to restart within XCode (maintaining access to debug logging)
        [self shellTask:@"osascript -e 'tell application \"Xcode\"' -e 'activate' -e 'run workspace document \"NewBezelServices.xcodeproj\"' -e 'end tell'"];
        
        /// use shell to restart directly
//        NSString *appPath = [[NSBundle mainBundle] bundlePath];
//        NSLog(@"%@", appPath);
//        [self shellTask:[NSString stringWithFormat:@"open %@", appPath]];
#endif
        exit(2);
    }
}

-(void)shellTask:(NSString*)command
{
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/bin/zsh"];
    [task setArguments:@[ @"-c", command]];
    [task launch];
}

#pragma mark - Key Remapping
/// changes volume key behaviour:
///     switchable via shell with 'defaults write com.mlforall.NewBezelServices RemapKeys -bool [true|false]'
///     default behaviour becomes smaller increments (as normally accessed with alt + shift + key)
///     pressing cmd, alt or ctrl reverts to standard increments
///     pressing shift still plays / mutes feedback sound according to inverse of current system setting
///     removes shortcut to Sound prefpane (as normally accessed with alt + key)
-(void)mediaKeyTap:(SPMediaKeyTap*)keyTap receivedMediaKeyEvent:(NSEvent*)event;
{
    if ([kPrefs boolForKey:@"RemapKeys"] == 1) {
        if (CGEventGetIntegerValueField([event CGEvent], kCGEventSourceStateID) == CGEventSourceGetSourceStateID(_eventSource))
            return;
    }

    int keyCode = (([event data1] & 0xFFFF0000) >> 16);
    int keyFlags = ([event data1] & 0x0000FFFF);
    int keyPressed = (((keyFlags & 0xFF00) >> 8)) == 0xA;
    int keyRepeat = (keyFlags & 0x1);
    int keyModifiers = [event modifierFlags] & NSEventModifierFlagDeviceIndependentFlagsMask;

    int newKeyModifiers = NSEventModifierFlagOption|NSEventModifierFlagShift;
    if (keyModifiers&NSEventModifierFlagCommand || keyModifiers&NSEventModifierFlagOption || keyModifiers&NSEventModifierFlagControl)
        newKeyModifiers = 0;
    
    switch (keyCode) {
        case NX_KEYTYPE_SOUND_UP:
            if ([kPrefs boolForKey:@"RemapKeys"] == 1) {
                if (!keyPressed && keyModifiers & NSEventModifierFlagShift) {
                    [self dispatchEvent:[event data1] withModifiers:NSEventModifierFlagShift];
                } else {
                    if (keyModifiers & NSEventModifierFlagShift && ((VolumeControl.volumeLevel > 0.9374 && newKeyModifiers == 0) || (VolumeControl.volumeLevel > 0.984374 && newKeyModifiers != 0))) {
                        [self dispatchEvent:[event data1] withModifiers:NSEventModifierFlagShift];
                    } else {
                        [self dispatchEvent:[event data1] withModifiers:newKeyModifiers];
                    }
                }
            }
#ifdef DEBUG
            [self debugHUD:keyCode];
#endif
            break;
        case NX_KEYTYPE_SOUND_DOWN:
            if ([kPrefs boolForKey:@"RemapKeys"] == 1) {
                if (!keyPressed && keyModifiers & NSEventModifierFlagShift) {
                    [self dispatchEvent:[event data1] withModifiers:NSEventModifierFlagShift];
                } else {
                    [self dispatchEvent:[event data1] withModifiers:newKeyModifiers];
                }
            }
#ifdef DEBUG
            [self debugHUD:keyCode];
#endif
            break;
        case NX_KEYTYPE_MUTE:
            if ([kPrefs boolForKey:@"RemapKeys"] == 1) {
                if (keyPressed && !keyRepeat) {
                    [self dispatchEvent:((NX_KEYTYPE_MUTE << 16) | (0xA << 8)) withModifiers:0];
                    if (keyModifiers & NSEventModifierFlagShift) {
                        [self dispatchEvent:((NX_KEYTYPE_MUTE << 16) | (0xB << 8)) withModifiers:NSEventModifierFlagShift];
                    } else {
                        [self dispatchEvent:((NX_KEYTYPE_MUTE << 16) | (0xB << 8)) withModifiers:0];
                    }
                }
            }
#ifdef DEBUG
            [self debugHUD:keyCode];
#endif
            break;
#ifdef DEBUG
        case NX_KEYTYPE_BRIGHTNESS_UP:
        case NX_KEYTYPE_BRIGHTNESS_DOWN:
        case NX_KEYTYPE_EJECT:
            [self debugHUD:keyCode];
            break;
#endif
        default:
            return;
    }
}

-(void)dispatchEvent:(long)keyData
       withModifiers:(long)keyModifiers
{
    NSEvent* ev = [NSEvent otherEventWithType:NSEventTypeSystemDefined
                                     location:NSZeroPoint
                                modifierFlags:keyModifiers
                                    timestamp:0
                                 windowNumber:0
                                      context:nil
                                      subtype:8
                                        data1:keyData
                                        data2:-1];
    CGEventRef cgEv = [ev CGEvent];
    CGEventSetSource(cgEv, _eventSource);
    CGEventPost(kCGSessionEventTap, cgEv);
}

#ifdef DEBUG
-(void)debugHUD:(long)keyCode
{
    bezel_action_t keyAction = kBezelActionUndef;
    double filled = 0;
    switch (keyCode) {
        case NX_KEYTYPE_SOUND_UP:
        case NX_KEYTYPE_SOUND_DOWN:
        case NX_KEYTYPE_MUTE:
            keyAction = VolumeControl.muted ? kBezelActionMute : kBezelActionVolume;
            filled = VolumeControl.muted ? 0 : VolumeControl.volumeLevel;
            break;
        case NX_KEYTYPE_BRIGHTNESS_UP:
        case NX_KEYTYPE_BRIGHTNESS_DOWN:
            keyAction = kBezelActionBrightness;
            filled = BrightnessControl.brightnessLevel;
            break;
        case NX_KEYTYPE_EJECT:
            keyAction = kBezelActionEject;
            break;
        default:
            return;
    }
    if (keyAction == kBezelActionUndef)
        return;
    [_hudCtrl showHUDForAction:keyAction sliderFilled:filled sliderMax:1.0f textStringValue:nil];
}
#endif

#pragma mark - XPC Delegate (10.12+)
#ifndef DEBUG
- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection
{
#pragma unused(listener)
    [newConnection setExportedInterface:[NSXPCInterface interfaceWithProtocol:@protocol(OSDUIHelperProtocol)]];
    [newConnection setExportedObject:self];
    [newConnection resume];
    return YES;
}

#pragma mark - OSDUIHelper Protocol (10.12+)
- (void)showImage:(long long)img onDisplayID:(CGDirectDisplayID)did priority:(unsigned int)prio msecUntilFade:(unsigned int)msec filledChiclets:(unsigned int)filled totalChiclets:(unsigned int)total locked:(int8_t)locked
{
#pragma unused(did, prio, msec)
    bezel_action_t action = kBezelActionUndef;
    switch (img)
    {
        case 4:
            action = kBezelActionMute;
            break ;
        case 5:
        case 23:
            action = kBezelActionVolume;
            break ;
        case 1:
            action = kBezelActionBrightness;
            break ;
        case 25:
            action = kBezelActionKeyBrightness;
            break ;
        case 26: // old keyboards (2007-): kbBright off key; new keyboards: kbBright = 0
        case 28: // disabled (too much light detected by ALS)
            action = kBezelActionKeyBrightnessOff;
            break ;
    }
    if (action == kBezelActionUndef)
        return ;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_hudCtrl showHUDForAction:action sliderFilled:filled sliderMax:locked ? 0.0f : total textStringValue:nil];
    });
}
#endif

@end
