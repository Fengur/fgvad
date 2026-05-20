//
//  FGAudioController.h
//  FgVadDemo
//
//  RemoteIO AudioUnit 录音器，输出 16 kHz mono int16 PCM。
//
//  搬自作者过去工作经验里的 SogouSpeechNote_SDK/AudioController，剥掉 Sogou
//  特有依赖（日志、Config、AudioUtilities/MeterTable）。所有 AU 操作通过
//  专用 NSThread + run loop 串行化，避免多线程竞争 AU 状态机。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(int, FGAudioControllerStatus) {
    FGAudioControllerStatusIdle = 0,
    FGAudioControllerStatusReady = 1,
    FGAudioControllerStatusRecording = 2,
    FGAudioControllerStatusStopped = 3,
};

@protocol FGAudioControllerDelegate <NSObject>

/// 每次 RemoteIO 渲染回调产生的 i16 PCM data（runs on AU IO 线程，consumer 自己
/// 注意切换队列）。
- (void)audioControllerDidProduceData:(NSData *)data;

@optional
- (void)audioControllerDidBegin;
- (void)audioControllerDidFinish;

@end

@interface FGAudioController : NSObject

@property (nonatomic, weak, nullable) id<FGAudioControllerDelegate> delegate;
@property (nonatomic, readonly) BOOL isRunning;
@property (nonatomic, readonly) FGAudioControllerStatus status;

+ (instancetype)sharedInstance;

/// 配置 AU + 启动专用线程 + run loop。同步等待。
- (OSStatus)prepareWithSampleRate:(double)sampleRate;

/// 开始录音。同步。
- (OSStatus)start;

/// 停止录音。同步。
- (OSStatus)stop;

/// 释放 AU。同步。run loop 在此后退出，下次 prepare 会再启线程。
- (OSStatus)releaseAudioUnit;

@end

NS_ASSUME_NONNULL_END
