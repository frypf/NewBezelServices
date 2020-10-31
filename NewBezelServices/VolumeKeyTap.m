/// simplified from nevyn/SPMediaKeyTap

// Copyright (c) 2010 Spotify AB
#import "VolumeKeyTap.h"

@interface SPMediaKeyTap ()
-(void)eventTapThread;
@end
static SPMediaKeyTap *singleton = nil;

static CGEventRef tapEventCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon);

@implementation SPMediaKeyTap

-(id)initWithDelegate:(id)delegate;
{
    _delegate = delegate;
    singleton = self;
    _tapThreadRL=nil;
    _eventPort=nil;
    _eventPortSource=nil;
    _eventSource=CGEventSourceCreate(kCGEventSourceStatePrivate);
    return self;
}
-(void)dealloc;
{
    [self stopWatchingMediaKeys];
    [super dealloc];
}

-(void)startWatchingMediaKeys
{
    // Prevent having multiple mediaKeys threads
    [self stopWatchingMediaKeys];
    
    // Add an event tap to intercept the system defined media key events
    _eventPort = CGEventTapCreate(kCGHIDEventTap, //kCGSessionEventTap,
                                  kCGHeadInsertEventTap,
                                  kCGEventTapOptionDefault,
                                  CGEventMaskBit(NX_SYSDEFINED),
                                  tapEventCallback,
                                  self);
//    assert(_eventPort != NULL);
    if (_eventPort == NULL) {
        NSLog(@"eventPort==NULL");//, reconfirming accessibility permission");
//        [self accessibilityAsk];
        NSLog(@"exiting");
        exit(1);
    }

    _eventPortSource = CFMachPortCreateRunLoopSource(kCFAllocatorSystemDefault, _eventPort, 0);
//    assert(_eventPortSource != NULL);
    if (_eventPortSource == NULL) {
        NSLog(@"eventPortSource==NULL, exiting");
        exit(1);
    }

    [NSThread detachNewThreadSelector:@selector(eventTapThread) toTarget:self withObject:nil];
}

-(void)stopWatchingMediaKeys
{
    // TODO<nevyn>: Shut down thread, remove event tap port and source
    if(_tapThreadRL){
        CFRunLoopStop(_tapThreadRL);
        _tapThreadRL=nil;
    }
    if(_eventPort){
        CFMachPortInvalidate(_eventPort);
        CFRelease(_eventPort);
        _eventPort=nil;
    }
    if(_eventPortSource){
        CFRelease(_eventPortSource);
        _eventPortSource=nil;
    }
}

static CGEventRef tapEventCallback2(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon)
{
    SPMediaKeyTap *self = refcon;

    if(type == kCGEventTapDisabledByTimeout) {
        NSLog(@"Media key event tap was disabled by timeout");
        CGEventTapEnable(self->_eventPort, TRUE);
        return event;
    } else if(type == kCGEventTapDisabledByUserInput) {
        return event;
    }
    NSEvent *nsEvent = nil;
    @try {
        nsEvent = [NSEvent eventWithCGEvent:event];
    }
    @catch (NSException * e) {
        NSLog(@"Strange CGEventType: %d: %@", type, e);
        assert(0);
        return event;
    }
    
    if (type != NX_SYSDEFINED || [nsEvent subtype] != SPSystemDefinedEventMediaKeys)
        return event;

    int keyCode = (([nsEvent data1] & 0xFFFF0000) >> 16);
    if (keyCode != NX_KEYTYPE_SOUND_UP && keyCode != NX_KEYTYPE_SOUND_DOWN && keyCode != NX_KEYTYPE_MUTE)
        return event;

    [nsEvent retain]; // matched in handleAndReleaseMediaKeyEvent:
    [self performSelectorOnMainThread:@selector(handleAndReleaseMediaKeyEvent:) withObject:nsEvent waitUntilDone:NO];
    
    return NULL;
}

static CGEventRef tapEventCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon)
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    CGEventRef ret = tapEventCallback2(proxy, type, event, refcon);
    [pool drain];
    return ret;
}

// event will have been retained in the other thread
-(void)handleAndReleaseMediaKeyEvent:(NSEvent *)event
{
    [event autorelease];
    [_delegate mediaKeyTap:self receivedMediaKeyEvent:event];
}

-(void)eventTapThread
{
    _tapThreadRL = CFRunLoopGetCurrent();
    CFRunLoopAddSource(_tapThreadRL, _eventPortSource, kCFRunLoopCommonModes);
    CFRunLoopRun();
}

@end
