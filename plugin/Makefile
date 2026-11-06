ARCHS ?= arm64
TARGET = iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = WeChat
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WeChatLiquidGlass
WeChatLiquidGlass_FILES = Sources/WXGConfig.m Sources/WXGNative.m Sources/WXGBackdrop.m Sources/WXGGlassView.m Sources/WXGNativeIcons.m Sources/WXGDemoBar.m Sources/WXGDockInteraction.m Sources/WXGSurface.m Sources/WXGInput.m Sources/WXGNativeInput.m Sources/WXGDecorations.m Sources/WXGMeHeader.m Sources/WXGHost.m Sources/WXGSettings.m Sources/WXGOpticalSettings.m Sources/WXGLicense.m Sources/WXGDockSearch.m Sources/WXGEdgeFade.m Sources/WXGBubbles.m Sources/WXGLocalGlass.m Sources/WXGPerfMonitor.m Sources/WXGSettingsShare.m Sources/WXGKeyboardTrace.m Sources/WXGUnlock.m Sources/WXGTelegramIcons.m Sources/WXGChatSegments.m Sources/WXGChatGroups.m
WeChatLiquidGlass_CFLAGS = -fobjc-arc -fblocks -O2 -Wall -Wextra -Wno-deprecated-declarations
WeChatLiquidGlass_FRAMEWORKS = UIKit Foundation QuartzCore CoreGraphics Metal MetalKit PhotosUI Security AVFoundation CoreMedia CoreVideo

include $(THEOS_MAKE_PATH)/tweak.mk
