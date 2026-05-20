//
//  FGAudioController.m
//  FgVadDemo
//

#import "FGAudioController.h"
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>

#define kChannelCount  1

@interface FGAudioController ()
{
    AudioComponentInstance _remoteIOUnit;
    volatile BOOL _threadCanClose;
}

@property (atomic, assign) BOOL isRunning;
@property (atomic, assign) FGAudioControllerStatus status;

@property (nonatomic, strong, nullable) NSThread *thread;
@property (nonatomic, assign, nullable) CFRunLoopRef runloop;

// 用来在 -performSelector:onThread: 之后取回返回值
@property (atomic, assign) OSStatus statusBuffer;

@end

@implementation FGAudioController

+ (instancetype)sharedInstance {
    static FGAudioController *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _status = FGAudioControllerStatusIdle;
    }
    return self;
}

#pragma mark - Public API（同步派发到内部 thread）

- (OSStatus)prepareWithSampleRate:(double)sampleRate {
    OSStatus status = noErr;
    @synchronized (self) {
        if (self.thread == nil) {
            self.thread = [[NSThread alloc] initWithTarget:self
                                                  selector:@selector(_runThreadLoop)
                                                    object:nil];
            [self.thread setThreadPriority:1.0];
            [self.thread setName:@"fg.AudioUnit.Recorder"];
            [self.thread start];
        }

        NSNumber *rateBox = @(sampleRate);
        [self performSelector:@selector(_prepareWithSampleRate:)
                     onThread:self.thread
                   withObject:rateBox
                waitUntilDone:YES];
        status = self.statusBuffer;
        self.statusBuffer = noErr;
    }
    return status;
}

- (OSStatus)start {
    OSStatus status = noErr;
    @synchronized (self) {
        if (self.thread) {
            [self performSelector:@selector(_start)
                         onThread:self.thread
                       withObject:nil
                    waitUntilDone:YES];
        }
        status = self.statusBuffer;
        self.statusBuffer = noErr;
    }
    return status;
}

- (OSStatus)stop {
    OSStatus status = noErr;
    @synchronized (self) {
        if (self.thread) {
            [self performSelector:@selector(_stop)
                         onThread:self.thread
                       withObject:nil
                    waitUntilDone:YES];
        }
        status = self.statusBuffer;
        self.statusBuffer = noErr;
    }
    return status;
}

- (OSStatus)releaseAudioUnit {
    OSStatus status = noErr;
    @synchronized (self) {
        if (self.thread) {
            [self performSelector:@selector(_releaseAudioUnit)
                         onThread:self.thread
                       withObject:nil
                    waitUntilDone:YES];
            if (_threadCanClose) {
                CFRunLoopStop(self.runloop);
                self.thread = nil;
            }
        }
        status = self.statusBuffer;
        self.statusBuffer = noErr;
    }
    return status;
}

#pragma mark - Internal thread entry

- (void)_runThreadLoop {
    [[NSRunLoop currentRunLoop] addPort:[NSPort port] forMode:NSDefaultRunLoopMode];
    self.runloop = CFRunLoopGetCurrent();
    _threadCanClose = NO;
    CFRunLoopRun();

    if ([self.delegate respondsToSelector:@selector(audioControllerDidFinish)]) {
        [self.delegate audioControllerDidFinish];
    }
}

#pragma mark - Render callback

static OSStatus FGRecordingCallback(void *inRefCon,
                                    AudioUnitRenderActionFlags *ioActionFlags,
                                    const AudioTimeStamp *inTimeStamp,
                                    UInt32 inBusNumber,
                                    UInt32 inNumberFrames,
                                    AudioBufferList *ioData) {
    FGAudioController *controller = (__bridge FGAudioController *)inRefCon;

    AudioBufferList bufferList;
    bufferList.mNumberBuffers = 1;
    bufferList.mBuffers[0].mNumberChannels = 1;
    bufferList.mBuffers[0].mDataByteSize = inNumberFrames * (UInt32)sizeof(int16_t);
    bufferList.mBuffers[0].mData = NULL;

    OSStatus status = AudioUnitRender(controller->_remoteIOUnit,
                                      ioActionFlags,
                                      inTimeStamp,
                                      inBusNumber,
                                      inNumberFrames,
                                      &bufferList);
    if (status != noErr) {
        return status;
    }

    NSData *data = [[NSData alloc] initWithBytes:bufferList.mBuffers[0].mData
                                          length:bufferList.mBuffers[0].mDataByteSize];

    id<FGAudioControllerDelegate> delegate = controller.delegate;
    if ([delegate respondsToSelector:@selector(audioControllerDidProduceData:)]) {
        [delegate audioControllerDidProduceData:data];
    }
    return noErr;
}

#pragma mark - AU lifecycle (run on internal thread)

static OSStatus FGCheckStatus(OSStatus error, const char *operation) {
    if (error == noErr) return error;
    char err4cc[8] = {0};
    *(UInt32 *)(err4cc + 1) = CFSwapInt32HostToBig(error);
    if (isprint(err4cc[1]) && isprint(err4cc[2]) &&
        isprint(err4cc[3]) && isprint(err4cc[4])) {
        err4cc[0] = err4cc[5] = '\'';
        err4cc[6] = '\0';
        NSLog(@"[FGAudioController] %s -> %s (%d)", operation, err4cc, (int)error);
    } else {
        NSLog(@"[FGAudioController] %s -> %d", operation, (int)error);
    }
    return error;
}

- (OSStatus)_prepareWithSampleRate:(NSNumber *)sampleRateBox {
    if (self.status != FGAudioControllerStatusIdle) {
        NSLog(@"[FGAudioController] prepare in non-idle status %d", self.status);
        self.statusBuffer = -1;
        return -1;
    }

    double sampleRate = sampleRateBox.doubleValue;
    OSStatus status = noErr;

    AudioComponentDescription desc = {0};
    desc.componentType = kAudioUnitType_Output;
    desc.componentSubType = kAudioUnitSubType_RemoteIO;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;

    AudioComponent component = AudioComponentFindNext(NULL, &desc);
    status = AudioComponentInstanceNew(component, &_remoteIOUnit);
    if (FGCheckStatus(status, "AudioComponentInstanceNew")) {
        self.statusBuffer = status;
        return status;
    }

    UInt32 oneFlag = 1;
    AudioUnitElement bus1 = 1;  // mic input bus

    status = AudioUnitSetProperty(_remoteIOUnit,
                                  kAudioOutputUnitProperty_EnableIO,
                                  kAudioUnitScope_Input,
                                  bus1,
                                  &oneFlag,
                                  sizeof(oneFlag));
    if (FGCheckStatus(status, "EnableIO input")) {
        self.statusBuffer = status;
        return status;
    }

    AudioStreamBasicDescription asbd = {0};
    asbd.mSampleRate = sampleRate;
    asbd.mFormatID = kAudioFormatLinearPCM;
    asbd.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    asbd.mBytesPerPacket = 2;
    asbd.mFramesPerPacket = 1;
    asbd.mBytesPerFrame = 2;
    asbd.mChannelsPerFrame = 1;
    asbd.mBitsPerChannel = 16;

    status = AudioUnitSetProperty(_remoteIOUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Output,
                                  bus1,
                                  &asbd,
                                  sizeof(asbd));
    if (FGCheckStatus(status, "Set StreamFormat for mic output")) {
        self.statusBuffer = status;
        return status;
    }

    AURenderCallbackStruct callback;
    callback.inputProc = FGRecordingCallback;
    callback.inputProcRefCon = (__bridge void *)self;
    status = AudioUnitSetProperty(_remoteIOUnit,
                                  kAudioOutputUnitProperty_SetInputCallback,
                                  kAudioUnitScope_Global,
                                  bus1,
                                  &callback,
                                  sizeof(callback));
    if (FGCheckStatus(status, "Set input callback")) {
        self.statusBuffer = status;
        return status;
    }

    status = AudioUnitInitialize(_remoteIOUnit);
    if (FGCheckStatus(status, "AudioUnitInitialize")) {
        self.statusBuffer = status;
        return status;
    }

    self.status = FGAudioControllerStatusReady;
    self.statusBuffer = status;
    return status;
}

- (OSStatus)_start {
    if (self.status != FGAudioControllerStatusReady) {
        NSLog(@"[FGAudioController] start in non-ready status %d", self.status);
        self.statusBuffer = -1;
        return -1;
    }
    OSStatus status = AudioOutputUnitStart(_remoteIOUnit);
    if (status == noErr) {
        self.isRunning = YES;
        self.status = FGAudioControllerStatusRecording;
        if ([self.delegate respondsToSelector:@selector(audioControllerDidBegin)]) {
            [self.delegate audioControllerDidBegin];
        }
    } else {
        FGCheckStatus(status, "AudioOutputUnitStart");
    }
    self.statusBuffer = status;
    return status;
}

- (OSStatus)_stop {
    if (self.status != FGAudioControllerStatusRecording) {
        NSLog(@"[FGAudioController] stop in non-recording status %d", self.status);
        self.statusBuffer = -1;
        return -1;
    }
    OSStatus status = AudioOutputUnitStop(_remoteIOUnit);
    if (status == noErr) {
        self.isRunning = NO;
        self.status = FGAudioControllerStatusStopped;
    } else {
        FGCheckStatus(status, "AudioOutputUnitStop");
    }
    self.statusBuffer = status;
    return status;
}

- (OSStatus)_releaseAudioUnit {
    if (self.status != FGAudioControllerStatusReady &&
        self.status != FGAudioControllerStatusStopped) {
        NSLog(@"[FGAudioController] release in invalid status %d", self.status);
        self.statusBuffer = -1;
        return -1;
    }
    OSStatus status = AudioComponentInstanceDispose(_remoteIOUnit);
    _remoteIOUnit = NULL;
    if (status == noErr) {
        self.status = FGAudioControllerStatusIdle;
    } else {
        FGCheckStatus(status, "AudioComponentInstanceDispose");
    }
    _threadCanClose = YES;
    self.statusBuffer = status;
    return status;
}

@end
