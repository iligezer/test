TARGET = iphone:clang:latest:15.0
PACKAGE_VERSION = 1.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = aimbot
aimbot_FILES = Tweak.x
aimbot_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

after-package::
	@echo "✅ Готово!"
