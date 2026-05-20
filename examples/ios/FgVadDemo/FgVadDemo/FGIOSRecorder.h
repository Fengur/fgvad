//
//  FGIOSRecorder.h
//  FgVadDemo
//
//  iOS 录音器对外薄封装：处理 AVAudioSession 配置 + 麦克风权限 + 拼成
//  Swift 友好的 chunk 回调接口。底层走 FGAudioController（RemoteIO AU）。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class FGIOSRecorder;

@protocol FGIOSRecorderDelegate <NSObject>

/// 每个 chunk 回调（已经在主线程，consumer 直接消费）。frames 指针寿命仅限
/// 此回调内，consumer 要复制就在回调内复制。
- (void)recorder:(FGIOSRecorder *)recorder
   didProduceFrames:(const int16_t *)frames
              count:(NSUInteger)count;

@optional
- (void)recorderDidStart:(FGIOSRecorder *)recorder;
- (void)recorderDidStop:(FGIOSRecorder *)recorder;
- (void)recorder:(FGIOSRecorder *)recorder didFailWithError:(NSError *)error;

@end

@interface FGIOSRecorder : NSObject

@property (nonatomic, weak, nullable) id<FGIOSRecorderDelegate> delegate;
@property (nonatomic, readonly) BOOL isRecording;

/// 请求麦克风权限。callback 在主线程执行。
- (void)requestPermission:(void (^)(BOOL granted))completion;

/// 配置 AVAudioSession + AU + 开始录音。返回 NO 时 error 通过 delegate 抛出。
- (BOOL)start;

/// 停止 + 释放 AU + deactivate AVAudioSession。
- (void)stop;

@end

NS_ASSUME_NONNULL_END
