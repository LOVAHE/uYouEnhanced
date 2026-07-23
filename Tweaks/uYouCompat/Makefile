TARGET := iphone:clang:latest:14.0
ARCHS = arm64
INSTALL_TARGET_PROCESSES = YouTube

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = uYouCompat
uYouCompat_FILES = Tweak.xm
uYouCompat_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
uYouCompat_FRAMEWORKS = Foundation UIKit

include $(THEOS_MAKE_PATH)/tweak.mk
