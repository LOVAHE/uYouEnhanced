TARGET = iphone:clang:latest:14.0
ARCHS = arm64
INSTALL_TARGET_PROCESSES = YouTube

include $(THEOS)/makefiles/common.mk

LIBVPX_SOURCE = $(THEOS_PROJECT_DIR)/vendor/libvpx
LIBVPX_BUILD = $(THEOS_PROJECT_DIR)/vendor/libvpx_ios
LIBVPX_ARCHIVE = $(LIBVPX_BUILD)/libvpx.a
YTUHD_SOURCE = $(THEOS_PROJECT_DIR)/vendor/ytuhd

TWEAK_NAME = VP9Compat
$(TWEAK_NAME)_FILES = \
	Tweak.xm \
	$(YTUHD_SOURCE)/HAMVPXVideoDecoder.m \
	$(YTUHD_SOURCE)/VideoDecoderHelper.x
$(TWEAK_NAME)_CFLAGS = \
	-fobjc-arc \
	-I$(THEOS_PROJECT_DIR) \
	-I$(LIBVPX_SOURCE) \
	-I$(LIBVPX_BUILD)
$(TWEAK_NAME)_LDFLAGS = $(LIBVPX_ARCHIVE)
$(TWEAK_NAME)_FRAMEWORKS = CoreMedia VideoToolbox

include $(THEOS_MAKE_PATH)/tweak.mk

.PHONY: libvpx
libvpx:
	bash "$(THEOS_PROJECT_DIR)/vendor/build_libvpx.sh"
