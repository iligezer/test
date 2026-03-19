export PATH := $(shell brew --prefix make)/libexec/gnubin:$(PATH)
THEOS_IGNORE_PARALLEL_BUILDING_NOTICE = yes

TARGET = iphone:clang:latest:15.0
PACKAGE_VERSION = 1.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = aimbot
aimbot_FILES = Tweak.x
aimbot_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-error -Wno-unused-variable
aimbot_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk

after-package::
	@echo "✅ Готово!"
