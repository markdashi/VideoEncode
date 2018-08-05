//
//  H264Encoder.h
//  01-硬编码
//
//  Created by seemygo on 17/4/29.
//  Copyright © 2017年 seemygo. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>

@interface H264Encoder : NSObject

- (void)prepareEncodeWithWidth:(int)width height:(int)height;
- (void)encodeFrame:(CMSampleBufferRef)sampleBuffer;
- (void)endEncoding;

@end
