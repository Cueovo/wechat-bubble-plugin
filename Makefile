ARCHS = arm64
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WeChatBubble

WeChatBubble_FILES = Sources/TweakEntry.m
WeChatBubble_CFLAGS = -fobjc-arc
WeChatBubble_FRAMEWORKS = Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
