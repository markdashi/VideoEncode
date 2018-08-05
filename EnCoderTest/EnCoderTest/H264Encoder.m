//
//  H264Encoder.m
//  01-硬编码
//
//  Created by seemygo on 17/4/29.
//  Copyright © 2017年 seemygo. All rights reserved.
//

#import "H264Encoder.h"
#import <VideoToolbox/VideoToolbox.h>

@interface H264Encoder(){
    int frameIndex;
}
@property (nonatomic, assign) VTCompressionSessionRef session;
@property (nonatomic, strong) NSFileHandle *fileHandle;
@end

@implementation H264Encoder

- (void)prepareEncodeWithWidth:(int)width height:(int)height{
    
    NSString *filePath =  [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"abc.h264"];
    [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
    [[NSFileManager defaultManager] createFileAtPath:filePath contents:nil attributes:nil];
    self.fileHandle = [NSFileHandle fileHandleForWritingAtPath:filePath];
    
    //0 定义帧的下标值
    frameIndex = 0;
    
    //1.创建VTCompressionSessionRef 对象
    // 参数一: CoreFoundation 创建对象的方式 ，NULL -> Default
    // 参数二：编码的视频宽度
    // 参数三: 编码的视频高度
    // 参数四: 编码的标准 H.264/ H.265
    // 参数五 ~ 参数七 NULL
    // 参数八: 编码成功一帧数据后的函数回调
    // 参数九: 回调函数的第一个参数
    //  VTCompressionSessionRef session;
    VTCompressionSessionCreate(kCFAllocatorDefault, width, height, kCMVideoCodecType_H264, NULL, NULL, NULL, compressionCallback, (__bridge void * _Nullable)(self), &_session);
    //2.设置VTCompressionSessionRef 属性
    // 2.1 如果是直播，需要设置视频编码是实时输出
    VTSessionSetProperty(self.session, kVTCompressionPropertyKey_RealTime, (__bridge CFTypeRef _Nullable)(@YES));
    // 2.2 设置帧率 (16/24/30)
    // 帧/s
    VTSessionSetProperty(self.session, kVTCompressionPropertyKey_ExpectedFrameRate, (__bridge CFTypeRef _Nullable)(@30));
    //2.3 设置比特率 (码率) bit/s  单位时间的数据量
    VTSessionSetProperty(self.session, kVTCompressionPropertyKey_AverageBitRate, (__bridge CFTypeRef _Nullable)(@(1500000))); // bit
    CFArrayRef dataLimits = (__bridge CFArrayRef)(@[@(1500000/8),@1]); //byte
    VTSessionSetProperty(self.session, kVTCompressionPropertyKey_DataRateLimits, dataLimits);
    // 2.4 设置GOP的大小
    VTSessionSetProperty(self.session, kVTCompressionPropertyKey_MaxKeyFrameInterval, (__bridge CFTypeRef _Nullable)(@(20)));
    //3.准备开始编码
    VTCompressionSessionPrepareToEncodeFrames(self.session);
}
- (void)encodeFrame:(CMSampleBufferRef)sampleBuffer{
    
    //1.从CMSampleBufferRef 中获取 CVImageBufferRef
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    
    //利用 VTCompressionSessionRef 编码 CMSampleBufferRef
    //pts(presentationTimeStamp):展示时间戳，用来解码时，计算每一帧时间的
    //dts(DecodeTimeStamp): 解码时间戳,决定该帧在什么时间展示
    frameIndex ++;
    // 第几帧 帧率
    CMTime pts = CMTimeMake(frameIndex, 30);
    
    VTCompressionSessionEncodeFrame(self.session, imageBuffer, pts, kCMTimeInvalid, NULL, NULL, NULL);
}

/**
  编码成功一帧数据后的函数回调

 @param outputCallbackRefCon <#outputCallbackRefCon description#>
 @param sourceFrameRefCon <#sourceFrameRefCon description#>
 @param status <#status description#>
 @param infoFlags <#infoFlags description#>
 @param sampleBuffer 编码后的 CMSampleBufferRef
 */
void compressionCallback(void * CM_NULLABLE outputCallbackRefCon,
              void * CM_NULLABLE sourceFrameRefCon,
              OSStatus status,
              VTEncodeInfoFlags infoFlags,
              CM_NULLABLE CMSampleBufferRef sampleBuffer){
    // 0 获取到当前对象
    H264Encoder *encoder = (__bridge H264Encoder *)(outputCallbackRefCon);
    
    // 1.CMSampleBufferRef
    // 2.判断该帧是否是关键帧
    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, YES);
    CFDictionaryRef dict = CFArrayGetValueAtIndex(attachments, 0);
    BOOL iskeyFrame = !CFDictionaryContainsKey(dict, kCMSampleAttachmentKey_NotSync);
    // 3. 如果是关键帧，那么将关键帧写入文件之前，先写入 PPS / SPS数据
    if (iskeyFrame) {
        
      //3.1 获取参数信息
      CMFormatDescriptionRef format =   CMSampleBufferGetFormatDescription(sampleBuffer);
      //3.2 从format 中获取sps信息
        //
        //参数二 : sps 0 pps 1
        //参数三
        const uint8_t *spsPointer;
        size_t spsSize,spsCount;
        
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 0, &spsPointer, &spsSize, &spsCount, NULL);
      //3.3 从format 中获取pps信息
        const uint8_t *ppsPointer;
        size_t ppsSize,ppsCount; //ppsCount 不用
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 1, &ppsPointer, &ppsSize, &ppsCount, NULL);
       // 3.4 将sps/pps 写入 NAL单元
        NSData *spsData = [NSData dataWithBytes:spsPointer length:spsSize];
        NSData *ppsData = [NSData dataWithBytes:ppsPointer length:ppsSize];
        [encoder writeData:spsData];
        [encoder writeData:ppsData];
    }
    // 4.将编码后的数据写入文件
    // 4.1 获取CMSampleBufferRef
    CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    // 4.2 CMSampleBufferRef获取内存地址/长度
    size_t totalLength;
    char *dataPointer;
    CMBlockBufferGetDataPointer(blockBuffer, 0, NULL, &totalLength, &dataPointer);
    // 4.3 从dataPointer开始读取数据，并且写入NALU -> slice
    // h264 存在切片的概念
    // h264 NALU 前4位来记录切片的长度的
    static const int h264HeaderLength = 4;
    size_t offsetLength = 0;
    // 4.4 通过循环，不断的读取slice的切片数据，并且封装成NALU 写入文件
    // while totolLength - offsetLength > h264HeaderLength
    while (offsetLength < totalLength - h264HeaderLength) {
        // 4.5 读取slice的长度
        uint32_t naluLength;
        // 从内存中读取数据
        memcpy(&naluLength, dataPointer+offsetLength, h264HeaderLength);
        // 4.6 H264 大端字节序/ 小端字节序
        naluLength = CFSwapInt32BigToHost(naluLength);
        // 4.7 根据长度读取字节,并转成NSData
        NSData *data = [NSData dataWithBytes:dataPointer+offsetLength+h264HeaderLength length:naluLength];
        //4.8 写入文件
        [encoder writeData:data];
        //4.9 设置offsetLength
        offsetLength += naluLength + h264HeaderLength;
    }
}
- (void)writeData:(NSData *)data{
   // NALU 的形式写入
   // NALU 头  0x 表示 16进制的某个数字 x 表示16进制的某个字节
    const char bytes[] = "\x00\x00\x00\x01";
    int headerLength = sizeof(bytes) - 1;
    NSData *headerData = [NSData dataWithBytes:bytes length:headerLength];
    // NALU 体
    [self.fileHandle writeData:headerData];
    [self.fileHandle writeData:data];
}

- (void)endEncoding{
    VTCompressionSessionInvalidate(self.session);
    CFRelease(self.session);
}


@end
