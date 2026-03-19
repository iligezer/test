TARGET = iphone:clang:latest:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = aimbot
aimbot_FILES = Tweak.x
aimbot_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
aimbot_FRAMEWORKS = UIKit Foundation QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
