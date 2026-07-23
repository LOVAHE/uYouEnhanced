#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import <YouTubeHeader/YTIElementRenderer.h>
#import <YouTubeHeader/YTIItemSectionRenderer.h>
#import <YouTubeHeader/YTIItemSectionSupportedRenderers.h>
#import <YouTubeHeader/YTISectionListRenderer.h>
#import <YouTubeHeader/YTISectionListSupportedRenderers.h>
#import <YouTubeHeader/YTIShelfRenderer.h>
#import <YouTubeHeader/YTIHorizontalListRenderer.h>
#import <YouTubeHeader/YTIHorizontalListSupportedRenderers.h>
#import <YouTubeHeader/YTInnerTubeCollectionViewController.h>
#import <YouTubeHeader/YTSectionListViewController.h>
#import <YouTubeHeader/_ASDisplayView.h>

// This file deliberately contains no preferences or entitlement checks.
// uYouCompat is an always-on compatibility layer for uYouEnhanced.

@interface YTIElementRenderer (uYouCompat)
- (NSData *)elementData;
@end

@interface YTIPlayerResponse : NSObject
- (BOOL)isMonetized;
- (NSMutableArray *)playerAdsArray;
- (NSMutableArray *)adSlotsArray;
@end

@interface YTPlayerResponse : NSObject
- (NSMutableArray *)playerAdsArray;
- (NSMutableArray *)adSlotsArray;
@end

@interface YTInnerTubeCollectionViewController (uYouCompat)
- (void)displaySectionsWithReloadingSectionControllerByRenderer:(id)renderer;
- (void)addSectionsFromArray:(NSArray *)array;
@end

@interface YTSectionListViewController (uYouCompat)
- (void)loadWithModel:(YTISectionListRenderer *)model;
@end

static id UYCValueForKey(id object, NSString *key) {
    if (!object || !key) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static BOOL UYCDescriptionLooksLikeAd(NSString *description) {
    if (description.length == 0) return NO;

    static NSArray<NSString *> *tokens;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        tokens = @[
            @"brand_promo",
            @"carousel_footered_layout",
            @"carousel_headered_layout",
            @"eml.ad_layout",
            @"eml.expandable_metadata",
            @"feed_ad_metadata",
            @"full_width_portrait_image_layout",
            @"full_width_square_image_layout",
            @"landscape_image_wide_button_layout",
            @"product_carousel",
            @"product_engagement_panel",
            @"product_item",
            @"promoted_video",
            @"shopping_carousel",
            @"shopping_item_card_list",
            @"statement_banner",
            @"square_image_layout",
            @"text_image_button_layout",
            @"text_search_ad",
            @"video_display_full_buttoned_layout",
            @"video_display_full_layout"
        ];
    });

    for (NSString *token in tokens) {
        if ([description containsString:token]) return YES;
    }
    return NO;
}

static BOOL UYCElementIsAd(YTIElementRenderer *elementRenderer) {
    if (!elementRenderer) return NO;

    if ([elementRenderer respondsToSelector:@selector(hasCompatibilityOptions)] &&
        elementRenderer.hasCompatibilityOptions &&
        [elementRenderer.compatibilityOptions respondsToSelector:@selector(hasAdLoggingData)] &&
        elementRenderer.compatibilityOptions.hasAdLoggingData) {
        return YES;
    }

    return UYCDescriptionLooksLikeAd(elementRenderer.description);
}

static BOOL UYCSupportedRendererIsAd(YTIItemSectionSupportedRenderers *renderer) {
    if (!renderer) return NO;

    if (([renderer respondsToSelector:@selector(hasPromotedVideoRenderer)] &&
         renderer.hasPromotedVideoRenderer) ||
        ([renderer respondsToSelector:@selector(hasCompactPromotedVideoRenderer)] &&
         renderer.hasCompactPromotedVideoRenderer) ||
        ([renderer respondsToSelector:@selector(hasPromotedVideoInlineMutedRenderer)] &&
         renderer.hasPromotedVideoInlineMutedRenderer)) {
        return YES;
    }

    return UYCElementIsAd(renderer.elementRenderer);
}

static BOOL UYCFilterItemSection(YTIItemSectionRenderer *section) {
    if (!section || ![section respondsToSelector:@selector(contentsArray)]) return NO;

    NSArray *original = section.contentsArray;
    if (![original isKindOfClass:NSArray.class] || original.count == 0) return NO;

    NSMutableArray *filtered = [NSMutableArray arrayWithCapacity:original.count];
    for (YTIItemSectionSupportedRenderers *renderer in original) {
        if (!UYCSupportedRendererIsAd(renderer)) [filtered addObject:renderer];
    }
    section.contentsArray = filtered;
    return filtered.count == 0;
}

static BOOL UYCFilterShelf(YTIShelfRenderer *shelf) {
    if (!shelf || ![shelf respondsToSelector:@selector(content)]) return NO;

    YTIHorizontalListRenderer *list = shelf.content.horizontalListRenderer;
    if (!list || ![list respondsToSelector:@selector(itemsArray)]) return NO;

    NSArray *original = list.itemsArray;
    if (![original isKindOfClass:NSArray.class] || original.count == 0) return NO;

    NSMutableArray *filtered = [NSMutableArray arrayWithCapacity:original.count];
    for (YTIHorizontalListSupportedRenderers *renderer in original) {
        if (!UYCElementIsAd(renderer.elementRenderer)) [filtered addObject:renderer];
    }
    list.itemsArray = filtered;
    return filtered.count == 0;
}

static NSMutableArray *UYCFilteredSections(NSArray *sections) {
    if (![sections isKindOfClass:NSArray.class]) return [NSMutableArray array];

    Class itemSectionClass = NSClassFromString(@"YTIItemSectionRenderer");
    Class shelfClass = NSClassFromString(@"YTIShelfRenderer");
    NSMutableArray *filtered = [NSMutableArray arrayWithCapacity:sections.count];

    for (id section in sections) {
        BOOL remove = NO;
        if (itemSectionClass && [section isKindOfClass:itemSectionClass]) {
            remove = UYCFilterItemSection(section);
        } else if (shelfClass && [section isKindOfClass:shelfClass]) {
            remove = UYCFilterShelf(section);
        } else {
            YTIElementRenderer *element = UYCValueForKey(section, @"elementRenderer");
            remove = UYCElementIsAd(element);
        }
        if (!remove) [filtered addObject:section];
    }
    return filtered;
}

%hook YTIPlayerResponse
- (BOOL)isMonetized {
    return NO;
}

- (NSMutableArray *)playerAdsArray {
    return [NSMutableArray array];
}

- (NSMutableArray *)adSlotsArray {
    return [NSMutableArray array];
}
%end

%hook YTPlayerResponse
- (NSMutableArray *)playerAdsArray {
    return [NSMutableArray array];
}

- (NSMutableArray *)adSlotsArray {
    return [NSMutableArray array];
}
%end

%hook YTAdShieldUtils
+ (id)spamSignalsDictionary {
    return @{};
}

+ (id)spamSignalsDictionaryWithoutIDFA {
    return @{};
}
%end

%hook YTDataUtils
+ (id)spamSignalsDictionary {
    return @{@"ms": @""};
}

+ (id)spamSignalsDictionaryWithoutIDFA {
    return @{};
}
%end

%hook YTAdsInnerTubeContextDecorator
- (void)decorateContext:(id)context {
}
%end

%hook YTAccountScopedAdsInnerTubeContextDecorator
- (void)decorateContext:(id)context {
}
%end

%hook YTLocalPlaybackController
- (id)createAdsPlaybackCoordinator {
    return nil;
}
%end

%hook MDXSession
- (void)adPlaying:(id)ad {
}
%end

%hook MDXSessionImpl
- (void)adPlaying:(id)ad {
}
%end

%hook YTIElementRenderer
- (NSData *)elementData {
    return UYCElementIsAd(self) ? nil : %orig;
}
%end

%hook YTSectionListViewController
- (void)loadWithModel:(YTISectionListRenderer *)model {
    if ([model respondsToSelector:@selector(contentsArray)]) {
        NSMutableArray *contents = model.contentsArray;
        NSMutableArray *filtered = [NSMutableArray arrayWithCapacity:contents.count];
        for (YTISectionListSupportedRenderers *renderer in contents) {
            YTIItemSectionRenderer *section = renderer.itemSectionRenderer;
            if (!section || !UYCFilterItemSection(section)) [filtered addObject:renderer];
        }
        model.contentsArray = filtered;
    }
    %orig(model);
}
%end

%hook YTInnerTubeCollectionViewController
- (void)addSectionsFromArray:(NSArray *)array {
    %orig(UYCFilteredSections(array));
}

- (void)displaySectionsWithReloadingSectionControllerByRenderer:(id)renderer {
    @try {
        NSArray *sections = [self valueForKey:@"_sectionRenderers"];
        if ([sections isKindOfClass:NSArray.class]) {
            [self setValue:UYCFilteredSections(sections) forKey:@"_sectionRenderers"];
        }
    } @catch (__unused NSException *exception) {
        // YouTube frequently renames private ivars. Feed filtering still runs
        // through addSectionsFromArray: and YTIElementRenderer in that case.
    }
    %orig(renderer);
}
%end

%hook _ASDisplayView
- (void)didMoveToWindow {
    %orig;
    NSString *identifier = self.accessibilityIdentifier;
    if ([identifier isEqualToString:@"eml.expandable_metadata.vpp"] ||
        [identifier isEqualToString:@"eml.ad_layout.full_width_square_image_layout"] ||
        [identifier containsString:@"feed_ad_metadata"]) {
        self.hidden = YES;
    }
}
%end
