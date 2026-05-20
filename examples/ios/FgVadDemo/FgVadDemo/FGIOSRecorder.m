//
//  FGIOSRecorder.m
//  FgVadDemo
//

#import "FGIOSRecorder.h"
#import "FGAudioController.h"
#import <AVFoundation/AVFoundation.h>

@interface FGIOSRecorder () <FGAudioControllerDelegate>
@end

@implementation FGIOSRecorder

#pragma mark - Permission

- (void)requestPermission:(void (^)(BOOL granted))completion {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    if ([session respondsToSelector:@selector(requestRecordPermission:)]) {
        [session requestRecordPermission:^(BOOL granted) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(granted);
            });
        }];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(YES);
        });
    }
}

#pragma mark - Start / Stop

- (BOOL)start {
    NSError *sessionError = nil;
    if (![self _setupAudioSessionError:&sessionError]) {
        if ([self.delegate respondsToSelector:@selector(recorder:didFailWithError:)]) {
            [self.delegate recorder:self didFailWithError:sessionError];
        }
        return NO;
    }

    FGAudioController *ctrl = [FGAudioController sharedInstance];
    ctrl.delegate = self;

    OSStatus status = [ctrl prepareWithSampleRate:16000];
    if (status != noErr) {
        NSError *err = [NSError errorWithDomain:@"FGIOSRecorder"
                                           code:status
                                       userInfo:@{NSLocalizedDescriptionKey: @"prepare failed"}];
        if ([self.delegate respondsToSelector:@selector(recorder:didFailWithError:)]) {
            [self.delegate recorder:self didFailWithError:err];
        }
        return NO;
    }

    status = [ctrl start];
    if (status != noErr) {
        NSError *err = [NSError errorWithDomain:@"FGIOSRecorder"
                                           code:status
                                       userInfo:@{NSLocalizedDescriptionKey: @"start failed"}];
        if ([self.delegate respondsToSelector:@selector(recorder:didFailWithError:)]) {
            [self.delegate recorder:self didFailWithError:err];
        }
        return NO;
    }

    _isRecording = YES;
    if ([self.delegate respondsToSelector:@selector(recorderDidStart:)]) {
        [self.delegate recorderDidStart:self];
    }
    return YES;
}

- (void)stop {
    if (!_isRecording) return;
    FGAudioController *ctrl = [FGAudioController sharedInstance];
    [ctrl stop];
    [ctrl releaseAudioUnit];
    ctrl.delegate = nil;

    [self _deactivateAudioSession];

    _isRecording = NO;
    if ([self.delegate respondsToSelector:@selector(recorderDidStop:)]) {
        [self.delegate recorderDidStop:self];
    }
}

#pragma mark - AVAudioSession

- (BOOL)_setupAudioSessionError:(NSError **)outError {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *err = nil;

    BOOL ok = [session setCategory:AVAudioSessionCategoryPlayAndRecord
                       withOptions:AVAudioSessionCategoryOptionMixWithOthers |
                                   AVAudioSessionCategoryOptionAllowBluetooth |
                                   AVAudioSessionCategoryOptionDefaultToSpeaker
                             error:&err];
    if (!ok) {
        if (outError) *outError = err;
        return NO;
    }

    ok = [session setActive:YES
                withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                      error:&err];
    if (!ok) {
        if (outError) *outError = err;
        return NO;
    }
    return YES;
}

- (void)_deactivateAudioSession {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *err = nil;
    [session setActive:NO
           withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                 error:&err];
}

#pragma mark - FGAudioControllerDelegate

- (void)audioControllerDidProduceData:(NSData *)data {
    // RemoteIO callback 线程；切回主线程后给 delegate 回调。
    NSUInteger frameCount = data.length / sizeof(int16_t);
    const int16_t *frames = (const int16_t *)data.bytes;

    // 注意：data 由 NSData ref 持有，frames 指针在 dispatch_async block 里仍然有效，
    // 因为我们 capture 的是 NSData* 实例，框架按引用计数延期释放。
    NSData *dataCopy = data;  // capture
    dispatch_async(dispatch_get_main_queue(), ^{
        const int16_t *p = (const int16_t *)dataCopy.bytes;
        if ([self.delegate respondsToSelector:@selector(recorder:didProduceFrames:count:)]) {
            [self.delegate recorder:self didProduceFrames:p count:frameCount];
        }
    });
    (void)frames;
}

@end
