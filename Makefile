TARGET = iphone:clang:latest:15.0
PACKAGE_VERSION = 1.0
ARCHS = arm64 arm64e
TARGET_IPHONEOS_DEPLOYMENT_VERSION = 15.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = aimbot
aimbot_FILES = Tweak.x
aimbot_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-error
aimbot_FRAMEWORKS = UIKit Foundation
aimbot_CODESIGN_FLAGS = -Sentitlements.plist
aimbot_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries

include $(THEOS_MAKE_PATH)/tweak.mk

after-package::
	@echo "✅ Сборка завершена!"
	@echo "📦 Пакет: packages/$(TWEAK_NAME)_$(PACKAGE_VERSION)_iphoneos-arm.deb"
	@echo "🔧 Бинарник: .theos/obj/debug/$(TWEAK_NAME).dylib"
	
# Дополнительная подпись ldid (на всякий случай)
	@ldid -Sentitlements.plist .theos/obj/debug/$(TWEAK_NAME).dylib || true
