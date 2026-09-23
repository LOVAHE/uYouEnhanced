from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else 'YTUHD')

policy = r'''#pragma once
#include <stdbool.h>
#include <stdint.h>

static inline uint64_t ytuhd_raise_existing_limit(bool enabled, uint64_t old, uint64_t target) {
    return enabled && old > 0 && old < target ? target : old;
}
static inline bool ytuhd_expand_codec(bool enabled, int mode, bool vp9) {
    return enabled && (mode == 0 || (vp9 ? mode == 1 : mode == 2));
}
'''
(root / 'NativePolicy.h').write_text(policy)

native = r'''#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreMedia/CoreMedia.h>
#import <VideoToolbox/VideoToolbox.h>
#import <dlfcn.h>
#include <atomic>
#include "NativePolicy.h"

extern "C" BOOL UseVP9orAV1(void);
extern "C" BOOL DisablesHDR(void);
extern "C" int Codec(void);

@interface YTIHamplayerStreamFilter : NSObject
- (id)vp9;
- (id)av1;
@end
@interface MLABRPolicy : NSObject
@end
@interface MLABRPolicyOld : NSObject
@end
@interface MLABRPolicyNew : NSObject
@end
@interface HAMDefaultABRPolicy : NSObject
@end
@interface YTMainAppVideoPlayerOverlayViewController : UIViewController
@end

static std::atomic<unsigned long long> vp9Visits{0}, av1Visits{0}, raisedFields{0}, rejectedFields{0}, hdrFallbacks{0};
static BOOL hwVP9 = NO, hwAV1 = NO, registrationAvailable = NO;
static NSArray *lastErrors = nil;

// A zero limit remains zero. No codec-support result, preferred codec, player
// factory, server ABR flag, or raw manifest is replaced by this build.
static id raiseLimits(id codec, BOOL vp9) {
    if (vp9) ++vp9Visits; else ++av1Visits;
    if (!codec || !ytuhd_expand_codec(UseVP9orAV1(), Codec(), vp9)) return codec;
    for (NSString *key in @[@"maxArea", @"maxFps"]) {
        SEL getter = NSSelectorFromString(key);
        NSString *setterName = [NSString stringWithFormat:@"set%@%@:", [[key substringToIndex:1] uppercaseString], [key substringFromIndex:1]];
        if (![codec respondsToSelector:getter] || ![codec respondsToSelector:NSSelectorFromString(setterName)]) continue;
        @try {
            id value = [codec valueForKey:key];
            if (![value isKindOfClass:NSNumber.class] || [value longLongValue] <= 0) continue;
            uint64_t old = [value unsignedLongLongValue];
            uint64_t target = [key isEqualToString:@"maxArea"] ? 8294400ULL : 60ULL;
            uint64_t next = ytuhd_raise_existing_limit(true, old, target);
            if (next != old) {
                [codec setValue:@(next) forKey:key];
                ++raisedFields;
            }
        } @catch (__unused NSException *exception) {
            ++rejectedFields;
        }
    }
    return codec;
}

static id filterHDR(id formats) {
    if (!UseVP9orAV1() || !DisablesHDR() || ![formats isKindOfClass:NSArray.class] || [formats count] == 0) return formats;
    NSMutableArray *result = [NSMutableArray array];
    for (id format in (NSArray *)formats) {
        BOOL hdr = NO;
        @try {
            if ([format respondsToSelector:NSSelectorFromString(@"qualityLabel")]) {
                id label = [format valueForKey:@"qualityLabel"];
                hdr = [label isKindOfClass:NSString.class] && [label rangeOfString:@"HDR" options:NSCaseInsensitiveSearch].location != NSNotFound;
            }
        } @catch (__unused NSException *exception) {}
        if (!hdr) [result addObject:format];
    }
    if (result.count == 0) { ++hdrFallbacks; return formats; }
    return result.count == [formats count] ? formats : result;
}

static void recordError(NSError *error) {
    if (![error isKindOfClass:NSError.class]) return;
    NSMutableArray *chain = [NSMutableArray array];
    NSError *current = error;
    for (unsigned i = 0; i < 5 && [current isKindOfClass:NSError.class]; ++i) {
        [chain addObject:@{@"domain": current.domain ?: @"", @"code": @(current.code)}];
        id underlying = current.userInfo[NSUnderlyingErrorKey];
        if (underlying == current) break;
        current = [underlying isKindOfClass:NSError.class] ? underlying : nil;
    }
    @synchronized (NSUserDefaults.standardUserDefaults) { lastErrors = [chain copy]; }
}

extern "C" NSString *YTUHDNativeDiagnosticText(void) {
    NSArray *errors;
    @synchronized (NSUserDefaults.standardUserDefaults) { errors = lastErrors ?: @[]; }
    NSDictionary *data = @{
        @"build": @"1.13.4+nativevp9.2-sabr",
        @"youtube": [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown",
        @"system": NSProcessInfo.processInfo.operatingSystemVersionString,
        @"enabled": @(UseVP9orAV1()),
        @"expand_codec_mode": @(Codec()),
        @"server_ABR": @"YouTube original",
        @"player_and_codec_support": @"YouTube original",
        @"hardware_VP9_hint": @(hwVP9), @"hardware_AV1_hint": @(hwAV1),
        @"supplemental_registration_symbol": @(registrationAvailable),
        @"vp9_filter_visits": @(vp9Visits.load()), @"av1_filter_visits": @(av1Visits.load()),
        @"raised_existing_limit_fields": @(raisedFields.load()),
        @"incompatible_fields_skipped": @(rejectedFields.load()),
        @"empty_HDR_filter_prevented": @(hdrFallbacks.load()),
        @"last_playback_error_chain": errors,
        @"legacy_force_player_setting_ignored": @([NSUserDefaults.standardUserDefaults boolForKey:@"YTUHDFixPlaybackIssues"]),
        @"note": @"Hardware hints do not certify per-stream decoding; native capability checks remain intact. No URLs, cookies or tokens are recorded."
    };
    NSData *json = [NSJSONSerialization dataWithJSONObject:data options:NSJSONWritingPrettyPrinted error:nil];
    return json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : @"Diagnostic serialization failed";
}

%hook YTIHamplayerStreamFilter
- (id)vp9 { return raiseLimits(%orig, YES); }
- (id)av1 { return raiseLimits(%orig, NO); }
%end

// These operate only on formats already produced by YouTube. They never add
// raw playlists, alter private filtering-state ivars, or force client ABR.
%hook MLABRPolicy
- (void)setFormats:(NSArray *)formats { %orig(filterHDR(formats)); }
%end
%hook MLABRPolicyOld
- (void)setFormats:(NSArray *)formats { %orig(filterHDR(formats)); }
%end
%hook MLABRPolicyNew
- (void)setFormats:(NSArray *)formats { %orig(filterHDR(formats)); }
%end
%hook HAMDefaultABRPolicy
- (NSArray *)filterFormats:(NSArray *)formats { return filterHDR(%orig); }
- (id)getSelectableFormatDataAndReturnError:(NSError **)error { return filterHDR(%orig); }
- (void)setFormats:(NSArray *)formats { %orig(filterHDR(formats)); }
%end

%hook YTMainAppVideoPlayerOverlayViewController
- (void)handleError:(NSError *)error {
    recordError(error);
    %orig;
}
%end

%ctor {
    typedef void (*RegisterDecoderFn)(CMVideoCodecType);
    RegisterDecoderFn registerDecoder = (RegisterDecoderFn)dlsym(RTLD_DEFAULT, "VTRegisterSupplementalVideoDecoderIfAvailable");
    registrationAvailable = registerDecoder != NULL;
    if (registerDecoder) registerDecoder(kCMVideoCodecType_VP9);
    hwVP9 = VTIsHardwareDecodeSupported(kCMVideoCodecType_VP9);
    hwAV1 = VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1);
    %init;
}
'''
(root / 'NativeSafe.xm').write_text(native)

p = root / 'Settings.x'
s = p.read_text()
s = s.replace('#define TweakName @"YTUHD"', 'extern NSString *YTUHDNativeDiagnosticText(void);\n#define TweakName @"YTUHD"')
s = s.replace('static BOOL hasSWVP9VideoDecoder;', '')
s = s.replace('    hasSWVP9VideoDecoder = %c(HAMVPXVideoDecoder) != nil;', '')
s = s.replace('@"YTUHD v1.13.4"', '@"YTUHD Native/SABR Fix2"')
start = s.index('    // App restart bar')
end = s.index('        if ([settingsViewController respondsToSelector:', start)
ui = r'''    YTSettingsSectionItem *mode = [YTSettingsSectionItemClass switchItemWithTitle:@"Native 2K/4K (SABR compatible)"
        titleDescription:@"提高已有 VP9/AV1 路径的画质上限；保留原生协议、能力检测和播放器。更改后重启。"
        accessibilityIdentifier:nil switchOn:UseVP9orAV1()
        switchBlock:^BOOL (YTSettingsCell *cell, BOOL enabled) {
            [NSUserDefaults.standardUserDefaults setBool:enabled forKey:UseVP9orAV1Key];
            return YES;
        } settingItemId:0];
    [sectionItems addObject:mode];

    NSArray *labels = @[@"Automatic (VP9 + AV1)", @"Expand VP9 limits only", @"Expand AV1 limits only"];
    YTSettingsSectionItem *codecOptions = [YTSettingsSectionItemClass itemWithTitle:@"Codec limits"
        titleDescription:@"仅选择放宽哪种格式的上限；不会强制视频切换编码。原生格式回退仍保留。"
        accessibilityIdentifier:nil detailTextBlock:^NSString *{
            NSInteger i = Codec(); return labels[(i >= 0 && i < 3) ? i : 0];
        } selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSMutableArray *rows = [NSMutableArray array];
            for (NSInteger i = 0; i < 3; ++i) {
                [rows addObject:[YTSettingsSectionItemClass checkmarkItemWithTitle:labels[i] titleDescription:nil selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
                    [NSUserDefaults.standardUserDefaults setInteger:i forKey:CodecKey];
                    [settingsViewController reloadData];
                    return YES;
                }]];
            }
            NSInteger i = Codec();
            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:@"Codec limits" pickerSectionTitle:nil rows:rows selectedItemIndex:(i >= 0 && i < 3 ? i : 0) parentResponder:[self parentResponder]];
            [settingsViewController pushViewController:picker];
            return YES;
        }];
    [sectionItems addObject:codecOptions];

    [sectionItems addObject:[YTSettingsSectionItemClass switchItemWithTitle:LOC(@"HDR")
        titleDescription:@"可选过滤 HDR；若筛选后没有可播放格式，保留原列表，避免空画质列表。"
        accessibilityIdentifier:nil switchOn:DisablesHDR()
        switchBlock:^BOOL (YTSettingsCell *cell, BOOL enabled) {
            [NSUserDefaults.standardUserDefaults setBool:enabled forKey:DisablesHDRKey]; return YES;
        } settingItemId:0]];
    [sectionItems addObject:[YTSettingsSectionItemClass switchItemWithTitle:LOC(@"RELOAD_BUTTON")
        titleDescription:LOC(@"RELOAD_BUTTON_DESC") accessibilityIdentifier:nil switchOn:ReloadButton()
        switchBlock:^BOOL (YTSettingsCell *cell, BOOL enabled) {
            [NSUserDefaults.standardUserDefaults setBool:enabled forKey:AddsReloadButtonKey]; return YES;
        } settingItemId:0]];

    [sectionItems addObject:[YTSettingsSectionItemClass itemWithTitle:@"Playback diagnostics / 播放诊断"
        titleDescription:@"显示实际钩子计数及最近的错误 domain/code；不记录视频地址或登录凭据，不联网。"
        accessibilityIdentifier:nil detailTextBlock:nil selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSString *text = YTUHDNativeDiagnosticText();
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"YTUHD Native/SABR Fix2" message:text preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"Copy / 复制" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { UIPasteboard.generalPasteboard.string = text; }]];
            [alert addAction:[UIAlertAction actionWithTitle:@"Close / 关闭" style:UIAlertActionStyleCancel handler:nil]];
            [settingsViewController presentViewController:alert animated:YES completion:nil];
            return YES;
        }]];

'''
s = s[:start] + ui + s[end:]
p.write_text(s)

# Keep the manual reload button. The old automatic timer repeatedly reloaded
# during buffering and is not a repair of the underlying playback failure.
p = root / 'ReloadVideo.x'
s = p.read_text()
a = s.index('%group Auto\n')
b = s.index('%group Top\n', a)
s = s[:a] + s[b:]
s = s.replace('    if (AutoReload()) {\n        %init(Auto);\n    }', '')
p.write_text(s)

p = root / 'Makefile'
s = p.read_text().replace('Tweak.xm Settings.x FixPlayback.x Filter.x ReloadVideo.x', 'NativeSafe.xm Settings.x ReloadVideo.x')
s = s.replace('$(TWEAK_NAME)_CFLAGS =', '$(TWEAK_NAME)_FRAMEWORKS = Foundation UIKit CoreMedia VideoToolbox\n$(TWEAK_NAME)_CFLAGS =')
p.write_text(s)
p = root / 'control'
p.write_text(p.read_text().replace('Version: 1.13.4', 'Version: 1.13.4+nativevp9.2'))

# Compile and execute the same pure limit policy used by NativeSafe.xm.
test = r'''#include <assert.h>
#include <stdio.h>
#include "NativePolicy.h"
int main(void) {
    unsigned tests = 0;
    uint64_t values[] = {0, 1, 2073600, 3686400, 8294400, 33177600, UINT64_MAX};
    for (unsigned e=0;e<2;e++) for (unsigned i=0;i<7;i++) {
        uint64_t old=values[i], next=ytuhd_raise_existing_limit(e,old,8294400);
        assert(next >= old);
        if (!e || old==0 || old>=8294400) assert(next==old);
        else assert(next==8294400);
        tests++;
    }
    uint64_t fps[] = {0,24,30,60,120,240};
    for (unsigned e=0;e<2;e++) for (unsigned i=0;i<6;i++) {
        uint64_t old=fps[i], next=ytuhd_raise_existing_limit(e,old,60);
        assert(next>=old);
        if (!e || old==0 || old>=60) assert(next==old); else assert(next==60);
        tests++;
    }
    for (int e=0;e<2;e++) for (int m=-1;m<=3;m++) for (int v=0;v<2;v++) {
        assert(ytuhd_expand_codec(e,m,v)==(e && (m==0 || (v ? m==1 : m==2)))); tests++;
    }
    printf("%u native policy cases passed\n", tests);
    return 0;
}
'''
(root / 'native_policy_test.c').write_text(test)
subprocess.run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', str(root/'native_policy_test.c'), '-o', str(root/'native_policy_test')], check=True)
subprocess.run([str((root/'native_policy_test').resolve())], check=True)

# Fail the build if unsafe paths accidentally return to the compiled sources.
compiled = '\n'.join((root/n).read_text() for n in ['NativeSafe.xm', 'Settings.x', 'ReloadVideo.x'])
for forbidden in ['%hookf', 'MSHookFunction', 'libundirect_find', 'SupportsCodec', 'iosPlayerClientSharedConfigDisableServerDrivenAbr', '_postponePreferredFormatFiltering', 'acquirePlayerForVideo:', 'streamSelectorHasSelectableVideoFormats:', '%init(Auto)']:
    if forbidden in compiled:
        raise SystemExit(f'Unsafe compiled path returned: {forbidden}')
print('Native/SABR source invariants passed')
