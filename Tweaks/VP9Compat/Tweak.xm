#import <CoreMedia/CoreMedia.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "Header.h"

typedef struct {
    const unsigned int *data;
    uint64_t length;
} VP9CompatPreferredOutputFormats;

@interface YTUHDVPXVideoDecoder : NSObject
- (instancetype)initWithDelegate:(id)delegate
                   delegateQueue:(dispatch_queue_t)delegateQueue
                     decodeQueue:(dispatch_queue_t)decodeQueue
           pixelBufferAttributes:(id)pixelBufferAttributes
                          config:(HAMVPXDecoderConfig)config;
@end

static id VP9CompatObjectForSelector(id object, SEL selector) {
    if (!object || ![object respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static id VP9CompatValueForKey(id object, NSString *key) {
    if (!object) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static void VP9CompatSetInt(id object, SEL selector, NSString *key, int value) {
    if (!object) return;
    if ([object respondsToSelector:selector]) {
        ((void (*)(id, SEL, int))objc_msgSend)(object, selector, value);
        return;
    }
    @try {
        [object setValue:@(value) forKey:key];
    } @catch (__unused NSException *exception) {
    }
}

static void VP9CompatConfigurePlayer(id playerItem) {
    id config = VP9CompatValueForKey(playerItem, @"_hamplayerConfig");
    if (!config) return;

    id streamFilter = VP9CompatObjectForSelector(config, NSSelectorFromString(@"streamFilter"));
    if (!streamFilter)
        streamFilter = VP9CompatValueForKey(config, @"streamFilter");
    if (!streamFilter) return;

    id vp9Filter = VP9CompatObjectForSelector(streamFilter, NSSelectorFromString(@"vp9"));
    if (!vp9Filter)
        vp9Filter = VP9CompatValueForKey(streamFilter, @"vp9");
    if (!vp9Filter) return;

    VP9CompatSetInt(
        vp9Filter,
        NSSelectorFromString(@"setMaxArea:"),
        @"maxArea",
        3840 * 2160
    );
    VP9CompatSetInt(
        vp9Filter,
        NSSelectorFromString(@"setMaxFps:"),
        @"maxFps",
        60
    );
}

static id VP9CompatCreateSoftwareDecoder(
    id delegate,
    dispatch_queue_t delegateQueue,
    id pixelBufferAttributes
) {
    dispatch_queue_t decodeQueue =
        dispatch_queue_create("com.lovahe.vp9compat.decode", DISPATCH_QUEUE_SERIAL);
    HAMVPXDecoderConfig config = {
        .threads = 2,
        .skipLoopFilter = NO,
        .loopFilterOptimization = NO,
        .rowThreading = NO,
        ._reserved = NO,
    };
    return [[YTUHDVPXVideoDecoder alloc]
        initWithDelegate:delegate
           delegateQueue:delegateQueue
             decodeQueue:decodeQueue
   pixelBufferAttributes:pixelBufferAttributes
                  config:config];
}

static BOOL VP9CompatIsVP9(id formatDescription) {
    if (!formatDescription ||
        ![formatDescription respondsToSelector:@selector(mediaSubType)])
        return NO;
    CMVideoCodecType codec =
        ((CMVideoCodecType (*)(id, SEL))objc_msgSend)(
            formatDescription,
            @selector(mediaSubType)
        );
    return codec == kCMVideoCodecType_VP9;
}

%group VP9CompatPlayerItem

%hook MLHAMPlayerItem

- (void)load {
    VP9CompatConfigurePlayer(self);
    %orig;
}

- (void)loadWithInitialSeekRequired:(BOOL)initialSeekRequired
                    initialSeekTime:(double)initialSeekTime {
    VP9CompatConfigurePlayer(self);
    %orig;
}

%end

%end

%group VP9CompatABRPolicy

%hook MLABRPolicy

- (void)setFormats:(NSArray *)formats {
    VP9CompatConfigurePlayer(self);
    %orig;
}

%end

%end

%group VP9CompatHotConfig

%hook YTHotConfig

- (BOOL)iosPlayerClientSharedConfigHamplayerPrepareVideoDecoderForAvsbdl {
    return YES;
}

- (BOOL)iosPlayerClientSharedConfigHamplayerAlwaysEnqueueDecodedSampleBuffersToAvsbdl {
    return YES;
}

%end

%end

%group VP9CompatOnesieConfig

%hook YTIIosOnesieHotConfig

- (BOOL)prepareVideoDecoder {
    return YES;
}

%end

%end

%group VP9CompatRenderingView

%hook MLHAMSBDLSampleBufferRenderingView

- (NSArray *)supportedCodecs {
    NSArray *codecs = %orig;
    if (![codecs isKindOfClass:[NSArray class]])
        return codecs;

    // A resigned IPA cannot keep Google's private alternate-decoder
    // entitlement. Keep VP9 away from AVSampleBufferDisplayLayer and route it
    // through the software decoder installed below.
    NSNumber *vp9 = @(kCMVideoCodecType_VP9);
    NSMutableArray *filtered = [NSMutableArray arrayWithCapacity:codecs.count];
    for (NSNumber *codec in codecs) {
        if (![codec isEqualToNumber:vp9])
            [filtered addObject:codec];
    }
    return filtered.copy;
}

%end

%end

%group VP9CompatMLDecoderFactory

%hook MLVideoDecoderFactory

- (id)videoDecoderWithDelegate:(id)delegate
                 delegateQueue:(dispatch_queue_t)delegateQueue
             formatDescription:(id)formatDescription
         pixelBufferAttributes:(NSDictionary *)pixelBufferAttributes
        preferredOutputFormats:(VP9CompatPreferredOutputFormats)preferredOutputFormats
                         error:(NSError **)error {
    if (VP9CompatIsVP9(formatDescription)) {
        if (error) *error = nil;
        return VP9CompatCreateSoftwareDecoder(
            delegate,
            delegateQueue,
            pixelBufferAttributes
        );
    }
    return %orig;
}

%end

%end

%group VP9CompatHAMDecoderFactory

%hook HAMDefaultVideoDecoderFactory

- (id)videoDecoderWithDelegate:(id)delegate
                 delegateQueue:(dispatch_queue_t)delegateQueue
             formatDescription:(id)formatDescription
         pixelBufferAttributes:(NSDictionary *)pixelBufferAttributes
        preferredOutputFormats:(VP9CompatPreferredOutputFormats)preferredOutputFormats
                         error:(NSError **)error {
    if (VP9CompatIsVP9(formatDescription)) {
        if (error) *error = nil;
        return VP9CompatCreateSoftwareDecoder(
            delegate,
            delegateQueue,
            pixelBufferAttributes
        );
    }
    return %orig;
}

%end

%end

static BOOL VP9CompatHasInstanceMethod(const char *className, SEL selector) {
    Class cls = objc_getClass(className);
    return cls && class_getInstanceMethod(cls, selector);
}

%ctor {
    @autoreleasepool {
        if (VP9CompatHasInstanceMethod("MLHAMPlayerItem", @selector(load)) &&
            VP9CompatHasInstanceMethod(
                "MLHAMPlayerItem",
                @selector(loadWithInitialSeekRequired:initialSeekTime:)
            ))
            %init(VP9CompatPlayerItem);

        if (VP9CompatHasInstanceMethod(
                "MLABRPolicy",
                @selector(setFormats:)
            ))
            %init(VP9CompatABRPolicy);

        if (VP9CompatHasInstanceMethod(
                "YTHotConfig",
                @selector(iosPlayerClientSharedConfigHamplayerPrepareVideoDecoderForAvsbdl)
            ) &&
            VP9CompatHasInstanceMethod(
                "YTHotConfig",
                @selector(iosPlayerClientSharedConfigHamplayerAlwaysEnqueueDecodedSampleBuffersToAvsbdl)
            ))
            %init(VP9CompatHotConfig);

        if (VP9CompatHasInstanceMethod(
                "YTIIosOnesieHotConfig",
                @selector(prepareVideoDecoder)
            ))
            %init(VP9CompatOnesieConfig);

        if (VP9CompatHasInstanceMethod(
                "MLHAMSBDLSampleBufferRenderingView",
                @selector(supportedCodecs)
            ))
            %init(VP9CompatRenderingView);

        SEL factorySelector = @selector(
            videoDecoderWithDelegate:
            delegateQueue:
            formatDescription:
            pixelBufferAttributes:
            preferredOutputFormats:
            error:
        );
        if (VP9CompatHasInstanceMethod("MLVideoDecoderFactory", factorySelector)) {
            %init(VP9CompatMLDecoderFactory);
        }
        if (VP9CompatHasInstanceMethod(
                "HAMDefaultVideoDecoderFactory",
                factorySelector
            ))
            %init(VP9CompatHAMDecoderFactory);
    }
}
