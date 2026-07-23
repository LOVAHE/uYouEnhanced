export TARGET = iphone:clang:17.5:15.0
export SDK_PATH = $(THEOS)/sdks/iPhoneOS17.5.sdk/
export SYSROOT = $(SDK_PATH)
export ARCHS = arm64

export libcolorpicker_ARCHS = arm64
export libcolorpicker_CFLAGS = -Wno-error=deprecated-declarations
export libFLEX_ARCHS = arm64
export Alderis_XCODEOPTS = LD_DYLIB_INSTALL_NAME=@rpath/Alderis.framework/Alderis
export Alderis_XCODEFLAGS = DYLIB_INSTALL_NAME_BASE=/Library/Frameworks BUILD_LIBRARY_FOR_DISTRIBUTION=YES ARCHS="$(ARCHS)"
export libcolorpicker_LDFLAGS = -F$(TARGET_PRIVATE_FRAMEWORK_PATH) -install_name @rpath/libcolorpicker.dylib
export ADDITIONAL_CFLAGS = -I$(THEOS_PROJECT_DIR)/Tweaks/RemoteLog -I$(THEOS_PROJECT_DIR)/Tweaks

ifneq ($(JAILBROKEN),1)
export DEBUGFLAG = -ggdb -Wno-unused-command-line-argument -L$(THEOS_OBJ_DIR) -F$(_THEOS_LOCAL_DATA_DIR)/$(THEOS_OBJ_DIR_NAME)/install/Library/Frameworks
MODULES = jailed
endif

ifndef YOUTUBE_VERSION
YOUTUBE_VERSION = 20.44.2
endif
ifndef UYOU_VERSION
UYOU_VERSION = 3.0.4
endif
PACKAGE_NAME = $(TWEAK_NAME)
PACKAGE_VERSION = $(YOUTUBE_VERSION)-$(UYOU_VERSION)

INSTALL_TARGET_PROCESSES = YouTube
TWEAK_NAME = uYouEnhanced
DISPLAY_NAME = YouTube
BUNDLE_ID = com.google.ios.youtube
DIAGNOSTIC_PROFILE ?= full

UYOU_INJECT_DYLIB = Tweaks/uYou/Library/MobileSubstrate/DynamicLibraries/uYou.dylib
UYOU_COMPAT_DYLIB = $(THEOS_OBJ_DIR)/uYouCompat.dylib
UYOU_CORE_INJECT_DYLIBS = $(UYOU_INJECT_DYLIB) $(UYOU_COMPAT_DYLIB)
$(TWEAK_NAME)_LDFLAGS += $(UYOU_COMPAT_DYLIB)
OTHER_INJECT_DYLIBS_A = \
    $(THEOS_OBJ_DIR)/libFLEX.dylib \
    $(THEOS_OBJ_DIR)/iSponsorBlock.dylib \
    $(THEOS_OBJ_DIR)/YTABConfig.dylib \
    $(THEOS_OBJ_DIR)/YTIcons.dylib \
    $(THEOS_OBJ_DIR)/YouTubeDislikesReturn.dylib \
    $(THEOS_OBJ_DIR)/DontEatMyContent.dylib \
    $(THEOS_OBJ_DIR)/YTHoldForSpeed.dylib \
    $(THEOS_OBJ_DIR)/YTVideoOverlay.dylib \
    $(THEOS_OBJ_DIR)/YTweaks.dylib
OTHER_INJECT_DYLIBS_B = \
    $(THEOS_OBJ_DIR)/YouGroupSettings.dylib \
    $(THEOS_OBJ_DIR)/YouLoop.dylib \
    $(THEOS_OBJ_DIR)/YouMute.dylib \
    $(THEOS_OBJ_DIR)/YouPiP.dylib \
    $(THEOS_OBJ_DIR)/YouQuality.dylib \
    $(THEOS_OBJ_DIR)/YouSlider.dylib \
    $(THEOS_OBJ_DIR)/YouSpeed.dylib \
    $(THEOS_OBJ_DIR)/YouTimeStamp.dylib \
    $(THEOS_OBJ_DIR)/YTUHD.dylib
OTHER_INJECT_DYLIBS = $(OTHER_INJECT_DYLIBS_A) $(OTHER_INJECT_DYLIBS_B)

ifeq ($(DIAGNOSTIC_PROFILE),uyou-only)
$(TWEAK_NAME)_FILES := Diagnostics/Noop.xm
$(TWEAK_NAME)_INJECT_DYLIBS = $(UYOU_CORE_INJECT_DYLIBS)
$(TWEAK_NAME)_EMBED_BUNDLES = Bundles/uYouBundle.bundle
else
$(TWEAK_NAME)_FILES := $(wildcard Sources/*.xm) $(wildcard Sources/*.x) $(wildcard Sources/*.m)
ifeq ($(DIAGNOSTIC_PROFILE),no-uyou)
$(TWEAK_NAME)_INJECT_DYLIBS = $(UYOU_COMPAT_DYLIB) $(OTHER_INJECT_DYLIBS)
else ifeq ($(DIAGNOSTIC_PROFILE),enhanced-core)
$(TWEAK_NAME)_INJECT_DYLIBS = $(UYOU_CORE_INJECT_DYLIBS)
else ifeq ($(DIAGNOSTIC_PROFILE),extras-a)
$(TWEAK_NAME)_INJECT_DYLIBS = $(UYOU_CORE_INJECT_DYLIBS) $(OTHER_INJECT_DYLIBS_A)
else ifeq ($(DIAGNOSTIC_PROFILE),extras-b)
$(TWEAK_NAME)_INJECT_DYLIBS = $(UYOU_CORE_INJECT_DYLIBS) $(OTHER_INJECT_DYLIBS_B)
else
$(TWEAK_NAME)_INJECT_DYLIBS = $(UYOU_CORE_INJECT_DYLIBS) $(OTHER_INJECT_DYLIBS)
endif
$(TWEAK_NAME)_EMBED_LIBRARIES = $(THEOS_OBJ_DIR)/libcolorpicker.dylib
$(TWEAK_NAME)_EMBED_FRAMEWORKS = $(_THEOS_LOCAL_DATA_DIR)/$(THEOS_OBJ_DIR_NAME)/install_Alderis.xcarchive/Products/var/jb/Library/Frameworks/Alderis.framework
$(TWEAK_NAME)_EMBED_BUNDLES = $(wildcard Bundles/*.bundle)
$(TWEAK_NAME)_EMBED_EXTENSIONS = $(wildcard Extensions/*.appex)
endif

$(TWEAK_NAME)_FRAMEWORKS = UIKit Foundation AVFoundation AVKit Photos Accelerate CoreMotion GameController VideoToolbox Security QuartzCore
$(TWEAK_NAME)_LIBRARIES = bz2 c++ iconv z
$(TWEAK_NAME)_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-but-set-variable -DTWEAK_VERSION=\"$(PACKAGE_VERSION)\"

include $(THEOS)/makefiles/common.mk
ifneq ($(JAILBROKEN),1)
SUBPROJECTS += Tweaks/uYouCompat
ifneq ($(DIAGNOSTIC_PROFILE),uyou-only)
YTUHD_PROJECT_DIR := $(THEOS_PROJECT_DIR)/Tweaks/YTUHD
YTUHD_LIBVPX_A := $(YTUHD_PROJECT_DIR)/vendor/libvpx_ios/libvpx.a
YTUHD_DAV1D_A := $(YTUHD_PROJECT_DIR)/vendor/dav1d_ios/libdav1d.a
YTWEEKS_PROJECT_DIR := $(THEOS_PROJECT_DIR)/Tweaks/YTweaks

.PHONY: ytuhd-all
ytuhd-all:
	@if [[ ! -f $(YTUHD_LIBVPX_A) ]]; then $(YTUHD_PROJECT_DIR)/vendor/build_libvpx.sh; fi
	@if [[ ! -f $(YTUHD_DAV1D_A) ]]; then $(YTUHD_PROJECT_DIR)/vendor/build_dav1d.sh; fi
	+$(MAKE) -C $(YTUHD_PROJECT_DIR) all \
		THEOS_PROJECT_DIR=$(YTUHD_PROJECT_DIR) \
		_THEOS_LOCAL_DATA_DIR=$(_THEOS_LOCAL_DATA_DIR) \
		SIDELOAD=1

before-all:: ytuhd-all

.PHONY: ytweaks-all
ytweaks-all:
	+$(MAKE) -C $(YTWEEKS_PROJECT_DIR) all \
		THEOS_PROJECT_DIR=$(YTWEEKS_PROJECT_DIR) \
		_THEOS_LOCAL_DATA_DIR=$(_THEOS_LOCAL_DATA_DIR) \
		YTweaks_CFLAGS="-fobjc-arc -Wno-error=deprecated-declarations" \
		SIDELOAD=1

before-all:: ytweaks-all

SUBPROJECTS += Tweaks/Alderis Tweaks/DontEatMyContent Tweaks/FLEXing/libflex Tweaks/iSponsorBlock Tweaks/Return-YouTube-Dislikes Tweaks/YTABConfig Tweaks/YouGroupSettings Tweaks/YTIcons Tweaks/YouLoop Tweaks/YouMute Tweaks/YouPiP Tweaks/YouQuality Tweaks/YouSlider Tweaks/YouSpeed Tweaks/YouTimeStamp Tweaks/YTHoldForSpeed Tweaks/YTVideoOverlay
endif
include $(THEOS_MAKE_PATH)/aggregate.mk
endif
include $(THEOS_MAKE_PATH)/tweak.mk

REMOVE_EXTENSIONS = 1
CODESIGN_IPA = 0

UYOU_PATH = Tweaks/uYou
UYOU_DEB = $(UYOU_PATH)/com.miro.uyou_$(UYOU_VERSION)_iphoneos-arm.deb
UYOU_DYLIB = $(UYOU_PATH)/Library/MobileSubstrate/DynamicLibraries/uYou.dylib
UYOU_BUNDLE = $(UYOU_PATH)/Library/Application\ Support/uYouBundle.bundle

internal-clean::
	@rm -rf $(UYOU_PATH)/*

ifneq ($(JAILBROKEN),1)
ifneq ($(filter full uyou-only enhanced-core extras-a extras-b,$(DIAGNOSTIC_PROFILE)),)
before-all::
	@if [[ ! -f $(UYOU_DEB) ]]; then \
		rm -rf $(UYOU_PATH)/*; \
		$(PRINT_FORMAT_BLUE) "Downloading uYou"; \
	fi
before-all::
	@if [[ ! -f $(UYOU_DEB) ]]; then \
		curl -s -L "https://www.dropbox.com/scl/fi/01vvu5lm8nkkicrznku9v/com.miro.uyou_$(UYOU_VERSION)_iphoneos-arm.deb?rlkey=efgz7po8kqqvha8doplk1s3ky&dl=1" -o $(UYOU_DEB); \
	fi; \
	if [[ ! -f $(UYOU_DYLIB) || ! -d $(UYOU_BUNDLE) ]]; then \
		tar -xf Tweaks/uYou/com.miro.uyou_$(UYOU_VERSION)_iphoneos-arm.deb -C Tweaks/uYou; tar -xf Tweaks/uYou/data.tar* -C Tweaks/uYou; \
		if [[ ! -f $(UYOU_DYLIB) || ! -d $(UYOU_BUNDLE) ]]; then \
			$(PRINT_FORMAT_ERROR) "Failed to extract uYou"; exit 1; \
		fi; \
	fi;
endif
else
before-package::
	@mkdir -p $(THEOS_STAGING_DIR)/Library/Application\ Support; cp -r Localizations/uYouPlus.bundle $(THEOS_STAGING_DIR)/Library/Application\ Support/
endif


