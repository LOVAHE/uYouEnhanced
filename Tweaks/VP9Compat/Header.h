#ifndef VP9COMPAT_HEADER_H_
#define VP9COMPAT_HEADER_H_

#import <Foundation/Foundation.h>
#import <YouTubeHeader/HAMFormatDescription.h>
#import <YouTubeHeader/HAMInputSampleBuffer.h>
#import <YouTubeHeader/HAMVideoDecoderDelegate.h>
#import <objc/runtime.h>

typedef struct {
    int threads;
    BOOL skipLoopFilter;
    BOOL loopFilterOptimization;
    BOOL rowThreading;
    BOOL _reserved;
} HAMVPXDecoderConfig;

#endif
