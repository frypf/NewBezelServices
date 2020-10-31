//
//  HUDWindowController.m
//  NewBezelServices
//
//  Created by Kelian on 29/11/2019.
//  Copyright © 2019 MLforAll. All rights reserved.
//

#import "HUDWindowController.h"
#import "VolumeControl.h"
#import "BrightnessControl.h"
#import "NSImage+ColorInvert.h"
#import "JNWThrottledBlock.h"

static BOOL isDarkModeEnabled(void)
{
    if (@available(macOS 10.10, *))
    {
        NSDictionary *udsDict = [NSUserDefaults.standardUserDefaults persistentDomainForName:NSGlobalDomain];
        NSString *style = [udsDict valueForKey:@"AppleInterfaceStyle"];
        return (style && [style.lowercaseString isEqualToString:@"dark"]);
    }
    return NO;
}

                                        #pragma mark - Interface
@interface HUDWindowController ()

@property (weak) IBOutlet NSTabView *tabView;
@property (weak) IBOutlet NSSlider *slider;
@property (weak) IBOutlet NSTextField *text;
@property (weak) IBOutlet NSImageView *image;

@end

                                        #pragma mark - Implementation
@implementation HUDWindowController
- (NSImage *)_cornerMask
{
    CGFloat radius = 12.0;
    CGFloat dimension = 2 * radius;
    NSSize size = NSMakeSize(dimension, dimension);
    NSImage *image = [NSImage imageWithSize:size flipped:NO drawingHandler:^BOOL(NSRect dstRect) {
        NSBezierPath *bezierPath = [NSBezierPath bezierPathWithRoundedRect:dstRect xRadius:radius yRadius:radius];
        //        [[NSColor blackColor] set];
        [bezierPath fill];
        return YES;
    }];
    image.capInsets = NSEdgeInsetsMake(radius, radius, radius, radius);
    image.resizingMode = NSImageResizingModeStretch;
    return image;
}

- (NSImage *)cornerMask
{
    return [self _cornerMask];
}

- (void)adaptUI
{
    BOOL themeState = isDarkModeEnabled();

    if (_bezelImages && themeState == _previousThemeState)
        return ;
    _previousThemeState = themeState;

    if (@available(macOS 10.10, *))
    {
        NSAppearanceName vappn = (themeState) ? NSAppearanceNameVibrantDark : NSAppearanceNameVibrantLight;
        [_visualEffectView setAppearance:[NSAppearance appearanceNamed:vappn]];
        if (themeState)
        {
            if (@available(macOS 10.14, *))
                [_visualEffectView setMaterial:NSVisualEffectMaterialHUDWindow];
        }
        else
            [_visualEffectView setMaterial:NSVisualEffectMaterialMenu];
        if (@available(macOS 10.14, *))
        {
            NSAppearanceName cvappn = (themeState) ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua;
            [self.window.contentView setAppearance:[NSAppearance appearanceNamed:cvappn]];
        }
        _visualEffectView.maskImage = self.cornerMask;
    }

    NSArray *imagePathContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:_imagesPath error:nil];

    NSMutableArray *hudImagesFilenames = [NSMutableArray new];
    for (NSString *filename in imagePathContents)
        if ([filename hasSuffix:@".pdf"])
            [hudImagesFilenames addObject:filename];

    NSMutableArray *dictNSImages = [NSMutableArray new];
    for (NSString *filename in hudImagesFilenames)
    {
        NSImage *hudImg = [[NSImage alloc] initWithContentsOfFile:[NSString stringWithFormat:@"%@/%@", _imagesPath, filename]];
        if (themeState)
            hudImg = [hudImg imageByInvertingColors];
        NSColor *textColor = (themeState) ? [NSColor whiteColor] : [NSColor blackColor];

        [_text setTextColor:textColor];
        [dictNSImages addObject:hudImg];
    }

    _bezelImages = [NSDictionary dictionaryWithObjects:dictNSImages forKeys:hudImagesFilenames];
    [_image setImage:[_bezelImages valueForKey:_currImgName]];
}

                                        #pragma mark - Set HUD Type
- (void)updateImageForAction:(bezel_action_t)action
{
    NSString *imageName;
    NSString *names[] = {
        @"Volume.pdf", @"Mute.pdf", @"Brightness.pdf",
        @"kBright.pdf", @"kBrightOff.pdf",
        @"Eject.pdf"
    };

    if (action >= kBezelActionMax || _currImgName == (imageName = names[action]))
        return ;

    [_image setImage:_bezelImages[imageName]];
    _currImgName = imageName;
}

                                        #pragma mark - HUD Interaction
- (void)setProgressVolumeWithSliderDoubleValue:(double)doubleValue maxValue:(double)maxValue
{
    /// pressing shift plays / mutes feedback sound according to inverse of current system setting
    if (NSApp.currentEvent.type == NSEventTypeLeftMouseUp) {
        BOOL volumeFeedbackSoundEnabled = [VolumeControl getVolumeFeedbackSoundEnabled];
        if ((volumeFeedbackSoundEnabled && !(NSApp.currentEvent.modifierFlags&NSEventModifierFlagShift)) || (!volumeFeedbackSoundEnabled && (NSApp.currentEvent.modifierFlags&NSEventModifierFlagShift)))
            [kVolumeFeedbackSound play];
    }
    
    /// basic throttling to reduce CPU load when changed via mouse
    [JNWThrottledBlock runBlock:^{
        Float32 currSliderVolumeEquivalent = doubleValue / maxValue;
        [VolumeControl setVolumeLevel:currSliderVolumeEquivalent];
        [self updateImageForAction:(VolumeControl.muted ? kBezelActionMute : kBezelActionVolume)];
    } withIdentifier:@"sliderAction" throttle:0.05];
}
- (IBAction)sliderAction:(id)sender
{
    assert(sender != nil);

    if (_closeWindowTimer.isValid)
        [_closeWindowTimer invalidate];

    bezel_action_t action = (bezel_action_t)[sender tag];

    double sliderValue = [sender doubleValue];
    double sliderMaxValue = [sender maxValue];

    switch (action)
    {
        case kBezelActionMute:
        case kBezelActionVolume:
            [self setProgressVolumeWithSliderDoubleValue:sliderValue maxValue:sliderMaxValue];
            break ;
        case kBezelActionBrightness:
            [BrightnessControl setBrightnessLevel:sliderValue / sliderMaxValue];
            break ;
        default:
            break ;
    }

    self.window.alphaValue = 1.0f;
    [self scheduleCloseTimerWithInterval:1.5f];
}

                                        #pragma mark - Show / Hide
- (void)showWindow:(id)sender
{
    NSScreen *mouseScreen;
    NSPoint mouseLoc = [NSEvent mouseLocation];

    for (NSScreen *screen in [NSScreen screens])
        if (NSMouseInRect(mouseLoc, screen.frame, NO))
            mouseScreen = screen;

    NSRect mouseScreenRect = mouseScreen.frame;
    
    NSPoint pt = NSMakePoint(mouseScreenRect.size.width - [self.window frame].size.width - 5, 5);

    [self.window setFrameOrigin:pt];

    [super showWindow:sender];
}

- (void)scheduleCloseTimerWithInterval:(NSTimeInterval)interval
{
    [_closeWindowTimer invalidate];
    _closeWindowTimer = [NSTimer scheduledTimerWithTimeInterval:interval target:self selector:@selector(fadeOut) userInfo:nil repeats:NO];
}

- (void)fadeOut
{
    [_closeWindowTimer invalidate];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.15f;
        self.window.animator.alphaValue = 0.0f;
    } completionHandler:^{
        close(0);
    }];
}

- (void)showHUDForAction:(bezel_action_t)action sliderFilled:(double)filled sliderMax:(double)max textStringValue:(NSString * __nullable)tsval
{
    if (_closeWindowTimer.isValid)
        [_closeWindowTimer invalidate];

    if (tsval || action == kBezelActionEject)
    {
        [_text setStringValue:tsval];
        [_tabView selectLastTabViewItem:nil];
    }
    else
    {
        [_slider setEnabled:max > 0 && action != kBezelActionKeyBrightness && action != kBezelActionKeyBrightnessOff];
        [_tabView selectFirstTabViewItem:nil];
    }

    [_slider setMaxValue:max];
    [_slider setDoubleValue:filled];
    [_slider setTag:(NSInteger)action];

    [self updateImageForAction:action];
    [self.window setAlphaValue: 1.0f];

    [self showWindow:nil];
    [self scheduleCloseTimerWithInterval:0.75f];
}

#pragma mark - Init

#define ELCAP_IMAGESPATH    @"/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/BezelUI/HiDPI"
#define SIERRA_IMAGESPATH   @"/System/Library/CoreServices/OSDUIHelper.app/Contents/Resources"

- (void)loadWindow
{
    [super loadWindow];

    if (@available(macOS 10.12, *))
        _imagesPath = SIERRA_IMAGESPATH;
    else
        _imagesPath = ELCAP_IMAGESPATH;

    [self.window setCanBecomeVisibleWithoutLogin:YES];
    [self.window setLevel:kCGMaximumWindowLevel];
    [self.window setMovable:NO];
    [_slider setDoubleValue:0];
    [_text setTextColor:[NSColor whiteColor]];

    if (@available(macOS 10.10, *))
    {
        NSVisualEffectView *vibrant = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0, 0, self.window.frame.size.width, self.window.frame.size.height)];

        [vibrant setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];
        [vibrant setBlendingMode:NSVisualEffectBlendingModeBehindWindow];
        [vibrant setState:NSVisualEffectStateActive];
        [vibrant setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameVibrantLight]];
        [self.window.contentView addSubview:vibrant positioned:NSWindowBelow relativeTo:nil];

        _visualEffectView = vibrant;
        [[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(adaptUI) name:@"AppleInterfaceThemeChangedNotification" object:nil];
    }

    _previousThemeState = isDarkModeEnabled();
    [self adaptUI];
}

@end
