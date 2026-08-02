ARCHS = arm64
TARGET = iphone:clang:latest:15.0
DEB_ARCH = iphoneos-arm64e
THEOS_PACKAGE_SCHEME = roothide

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WeChatBubble

WeChatBubble_FILES = \
	Sources/TweakEntry.m \
	Sources/Bootstrap/WBProcessGuard.m \
	Sources/Bootstrap/WBVersionGate.m \
	Sources/Discovery/WBCapabilityRegistry.m \
	Sources/Discovery/WBBubbleDiscoveryHook.m \
	Sources/Discovery/WBDiagnostics.m
WeChatBubble_CFLAGS = -fobjc-arc
WeChatBubble_FRAMEWORKS = Foundation UIKit
WeChatBubble_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
