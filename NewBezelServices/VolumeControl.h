//
//  VolumeControl.h
//  NewBezelServices
//
//  Created by Kelian on 04/11/2016.
//  Copyright © 2016 MLforAll. All rights reserved.
//

#import <Foundation/Foundation.h>
//#import <Cocoa/Cocoa.h>

#define kVolumeControlMinValue  0.0f
#define kVolumeControlMaxValue  1.0f

#define kVolumeFeedbackSound [[NSSound alloc] initWithContentsOfFile:@"/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff" byReference:YES]

@interface VolumeControl : NSObject

@property (readwrite, class, getter=getVolumeLevel) Float32 volumeLevel;
@property (readwrite, class, getter=isAudioMuted) BOOL muted;

+ (BOOL)getVolumeFeedbackSoundEnabled;

@end
