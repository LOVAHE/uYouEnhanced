#import <CoreMedia/CoreMedia.h>
#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>
#include <string.h>

#import "Header.h"

typedef struct {
    const unsigned int *data;
    uint64_t length;
} VP9CompatPreferredOutputFormats;

static BOOL (*VP9CompatOriginalSupportsCodec)(CMVideoCodecType codec);
static volatile uint32_t VP9CompatDecoderCapabilityDepth;

@interface YTUHDVPXVideoDecoder : NSObject
@property (nonatomic, weak) id delegate;
- (instancetype)initWithDelegate:(id)delegate
                   delegateQueue:(dispatch_queue_t)delegateQueue
                     decodeQueue:(dispatch_queue_t)decodeQueue
           pixelBufferAttributes:(id)pixelBufferAttributes
                          config:(HAMVPXDecoderConfig)config;
- (void)terminate;
@end

static void *VP9CompatFindSupportsCodec(void) {
    static const uint8_t pattern[] = {
        0x28, 0x66, 0x8c, 0x52,
        0xc8, 0x2e, 0xac, 0x72,
        0x1f, 0x00, 0x08, 0x6b,
        0x61, 0x00, 0x00, 0x54,
        0x28, 0x00, 0x80, 0x52,
    };
    void *match = NULL;

    for (uint32_t imageIndex = 0;
         imageIndex < _dyld_image_count();
         imageIndex++) {
        const char *imagePath = _dyld_get_image_name(imageIndex);
        const char *imageName = imagePath ? strrchr(imagePath, '/') : NULL;
        imageName = imageName ? imageName + 1 : imagePath;
        if (!imageName || strcmp(imageName, "YouTube") != 0)
            continue;

        const struct mach_header *genericHeader =
            _dyld_get_image_header(imageIndex);
        if (!genericHeader || genericHeader->magic != MH_MAGIC_64)
            return NULL;

        const struct mach_header_64 *header =
            (const struct mach_header_64 *)genericHeader;
        intptr_t slide = _dyld_get_image_vmaddr_slide(imageIndex);
        uintptr_t commandAddress = (uintptr_t)(header + 1);
        uintptr_t commandsEnd = commandAddress + header->sizeofcmds;

        for (uint32_t commandIndex = 0;
             commandIndex < header->ncmds;
             commandIndex++) {
            if (commandAddress + sizeof(struct load_command) > commandsEnd)
                return NULL;

            const struct load_command *command =
                (const struct load_command *)commandAddress;
            if (command->cmdsize < sizeof(struct load_command) ||
                commandAddress + command->cmdsize > commandsEnd)
                return NULL;

            if (command->cmd == LC_SEGMENT_64) {
                const struct segment_command_64 *segment =
                    (const struct segment_command_64 *)command;
                const struct section_64 *section =
                    (const struct section_64 *)(segment + 1);
                uintptr_t sectionsEnd =
                    (uintptr_t)section +
                    (uintptr_t)segment->nsects * sizeof(*section);
                if (sectionsEnd > commandAddress + command->cmdsize)
                    return NULL;

                for (uint32_t sectionIndex = 0;
                     sectionIndex < segment->nsects;
                     sectionIndex++) {
                    if (strncmp(section[sectionIndex].segname,
                                "__TEXT",
                                sizeof(section[sectionIndex].segname)) != 0 ||
                        strncmp(section[sectionIndex].sectname,
                                "__text",
                                sizeof(section[sectionIndex].sectname)) != 0)
                        continue;

                    const uint8_t *start =
                        (const uint8_t *)(section[sectionIndex].addr + slide);
                    size_t length = (size_t)section[sectionIndex].size;
                    if (length < sizeof(pattern))
                        return NULL;

                    for (size_t offset = 0;
                         offset <= length - sizeof(pattern);
                         offset++) {
                        if (start[offset] != pattern[0] ||
                            memcmp(start + offset,
                                   pattern,
                                   sizeof(pattern)) != 0)
                            continue;
                        if (match)
                            return NULL;
                        match = (void *)(start + offset);
                    }
                }
            }
            commandAddress += command->cmdsize;
        }
        break;
    }
    return match;
}

static BOOL VP9CompatSupportsCodec(CMVideoCodecType codec) {
    if (codec == kCMVideoCodecType_VP9)
        return __sync_fetch_and_add(
            &VP9CompatDecoderCapabilityDepth,
            0
        ) == 0;
    return VP9CompatOriginalSupportsCodec
        ? VP9CompatOriginalSupportsCodec(codec)
        : NO;
}

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

static void VP9CompatClearPreparedDecoder(id factory) {
    SEL selector = NSSelectorFromString(@"clearPreparedDecoder");
    if (factory && [factory respondsToSelector:selector])
        ((void (*)(id, SEL))objc_msgSend)(factory, selector);
}

static CMFormatDescriptionRef VP9CompatCMFormatDescription(id formatDescription) {
    SEL selector = @selector(formatDescription);
    if (!formatDescription ||
        ![formatDescription respondsToSelector:selector])
        return NULL;
    return ((CMFormatDescriptionRef (*)(id, SEL))objc_msgSend)(
        formatDescription,
        selector
    );
}

static id VP9CompatTakePreparedDecoder(
    id factory,
    id delegate,
    dispatch_queue_t delegateQueue,
    id formatDescription,
    id pixelBufferAttributes
) {
    if (!factory) return nil;

    id preparedDecoder =
        VP9CompatValueForKey(factory, @"_preparedDecoder");
    if (!preparedDecoder) return nil;

    BOOL matches = NO;
    id preparedDelegateQueue =
        VP9CompatValueForKey(factory, @"_delegateQueue");
    id preparedFormat =
        VP9CompatValueForKey(factory, @"_preparedFormatDescription");
    id preparedPixelBufferAttributes =
        VP9CompatValueForKey(factory, @"_preparedPixelBufferAttributes");
    CMFormatDescriptionRef requestedCMFormat =
        VP9CompatCMFormatDescription(formatDescription);
    CMFormatDescriptionRef preparedCMFormat =
        VP9CompatCMFormatDescription(preparedFormat);
    BOOL pixelBufferAttributesMatch =
        pixelBufferAttributes == preparedPixelBufferAttributes ||
        [pixelBufferAttributes
            isEqualToDictionary:preparedPixelBufferAttributes];

    if (preparedDelegateQueue == delegateQueue &&
        requestedCMFormat &&
        preparedCMFormat &&
        CMFormatDescriptionEqual(requestedCMFormat, preparedCMFormat) &&
        pixelBufferAttributesMatch) {
        matches = YES;
    }

    // YouTube prepares the VOD decoder before requesting it from the factory.
    // Reuse that exact decoder so its prepare callback and state are retained.
    if (matches) {
        VP9CompatClearPreparedDecoder(factory);
        SEL selector = @selector(setDelegate:);
        if ([preparedDecoder respondsToSelector:selector]) {
            ((void (*)(id, SEL, id))objc_msgSend)(
                preparedDecoder,
                selector,
                delegate
            );
        }
        return preparedDecoder;
    }

    if ([preparedDecoder respondsToSelector:@selector(terminate)])
        ((void (*)(id, SEL))objc_msgSend)(
            preparedDecoder,
            @selector(terminate)
        );
    VP9CompatClearPreparedDecoder(factory);
    return nil;
}

static id VP9CompatCreateSoftwareDecoder(
    id factory,
    id delegate,
    dispatch_queue_t delegateQueue,
    id formatDescription,
    id pixelBufferAttributes
) {
    id preparedDecoder = VP9CompatTakePreparedDecoder(
        factory,
        delegate,
        delegateQueue,
        formatDescription,
        pixelBufferAttributes
    );
    if (preparedDecoder) return preparedDecoder;

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

- (void)prepareDecoderForFormatDescription:(id)formatDescription
                             delegateQueue:(dispatch_queue_t)delegateQueue {
    __sync_add_and_fetch(&VP9CompatDecoderCapabilityDepth, 1);
    @try {
        %orig;
    } @finally {
        __sync_sub_and_fetch(&VP9CompatDecoderCapabilityDepth, 1);
    }
}

- (id)videoDecoderWithDelegate:(id)delegate
                 delegateQueue:(dispatch_queue_t)delegateQueue
             formatDescription:(id)formatDescription
         pixelBufferAttributes:(NSDictionary *)pixelBufferAttributes
        preferredOutputFormats:(VP9CompatPreferredOutputFormats)preferredOutputFormats
                         error:(NSError **)error {
    if (VP9CompatIsVP9(formatDescription)) {
        if (error) *error = nil;
        return VP9CompatCreateSoftwareDecoder(
            self,
            delegate,
            delegateQueue,
            formatDescription,
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
            nil,
            delegate,
            delegateQueue,
            formatDescription,
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
        SEL factorySelector = @selector(
            videoDecoderWithDelegate:
            delegateQueue:
            formatDescription:
            pixelBufferAttributes:
            preferredOutputFormats:
            error:
        );
        SEL prepareSelector = @selector(
            prepareDecoderForFormatDescription:
            delegateQueue:
        );
        if (!VP9CompatHasInstanceMethod(
                "MLVideoDecoderFactory",
                factorySelector
            ) ||
            !VP9CompatHasInstanceMethod(
                "MLVideoDecoderFactory",
                prepareSelector
            )) {
            NSLog(
                @"VP9Compat: required YouTube 21.21.3 decoder methods "
                 "were not found; leaving codec behavior unchanged"
            );
            return;
        }

        void *supportsCodec = VP9CompatFindSupportsCodec();
        if (!supportsCodec) {
            NSLog(
                @"VP9Compat: SupportsCodec hook target was not uniquely "
                 "identified; leaving codec behavior unchanged"
            );
            return;
        }
        MSHookFunction(
            supportsCodec,
            (void *)VP9CompatSupportsCodec,
            (void **)&VP9CompatOriginalSupportsCodec
        );

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
