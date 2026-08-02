#import "WBTextBubbleStyleHook.h"
#import "WBBubbleStyler.h"
#import "WBBubbleThemeProvider.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>

static void (*WBOriginalLayoutContentView)(id, SEL);
static BOOL WBHookInstalled;
static char WBLastStyledBubbleKey;

static UIView *WBViewFromSelector(id object, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    id value = [object respondsToSelector:selector] ? ((id (*)(id, SEL))objc_msgSend)(object, selector) : nil;
    return [value isKindOfClass:UIView.class] ? value : nil;
}

static UIView *WBAvatarView(id object, UIView *cellView) {
    UIView *avatarView = WBViewFromSelector(object, @"getHeadImageView");
    if (avatarView) {
        return avatarView;
    }
    for (UIView *subview in cellView.subviews) {
        if ([NSStringFromClass(subview.class) isEqualToString:@"MMHeadImageView"]) {
            return subview;
        }
    }
    return nil;
}

static WBBubbleDirection WBDirectionForAvatarView(UIView *avatarView, UIView *cellView) {
    if (!avatarView || avatarView.hidden || avatarView.alpha <= 0.01 || CGRectGetWidth(cellView.bounds) < 200.0) {
        return WBBubbleDirectionUnknown;
    }
    CGRect avatarRect = [avatarView convertRect:avatarView.bounds toView:cellView];
    CGFloat cellWidth = CGRectGetWidth(cellView.bounds);
    if (CGRectIsEmpty(avatarRect) || CGRectGetWidth(avatarRect) < 24.0 || CGRectGetHeight(avatarRect) < 24.0) {
        return WBBubbleDirectionUnknown;
    }
    if (CGRectGetMinX(avatarRect) <= 1.0 && CGRectGetMinY(avatarRect) <= 1.0) {
        return WBBubbleDirectionUnknown;
    }
    CGFloat midpoint = CGRectGetMidX(avatarRect) / cellWidth;
    if (midpoint <= 0.25) {
        return WBBubbleDirectionIncoming;
    }
    if (midpoint >= 0.75) {
        return WBBubbleDirectionOutgoing;
    }
    return WBBubbleDirectionUnknown;
}

static BOOL WBValidTextBubble(UIView *bubbleView, UIView *textView) {
    Class backgroundClass = NSClassFromString(@"YYAsyncImageView");
    Class textClass = NSClassFromString(@"RichTextView");
    if (!backgroundClass || !textClass || !bubbleView || !textView || ![bubbleView isKindOfClass:backgroundClass] || ![textView isKindOfClass:textClass]) {
        return NO;
    }
    CGFloat widthPadding = CGRectGetWidth(bubbleView.bounds) - CGRectGetWidth(textView.bounds);
    CGFloat heightPadding = CGRectGetHeight(bubbleView.bounds) - CGRectGetHeight(textView.bounds);
    return CGRectGetWidth(bubbleView.bounds) > 0.0 && CGRectGetHeight(bubbleView.bounds) > 0.0 && widthPadding >= 12.0 && widthPadding <= 60.0 && heightPadding >= 10.0 && heightPadding <= 50.0;
}

static void WBClearStyle(id object, UIView *bubbleView) {
    UIView *previousBubble = objc_getAssociatedObject(object, &WBLastStyledBubbleKey);
    if (previousBubble) {
        [WBBubbleStyler removeFromBubbleView:previousBubble];
    }
    if (bubbleView && bubbleView != previousBubble) {
        [WBBubbleStyler removeFromBubbleView:bubbleView];
    }
    objc_setAssociatedObject(object, &WBLastStyledBubbleKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void WBApplyStyle(id object) {
    if (!NSThread.isMainThread || ![object isKindOfClass:UIView.class]) {
        return;
    }
    UIView *cellView = object;
    UIView *bubbleView = WBViewFromSelector(object, @"getBgImageView");
    UIView *textView = WBViewFromSelector(object, @"getRichTextView");
    UIView *avatarView = WBAvatarView(object, cellView);
    WBBubbleDirection direction = WBDirectionForAvatarView(avatarView, cellView);
    UIView *previousBubble = objc_getAssociatedObject(object, &WBLastStyledBubbleKey);
    if (previousBubble && previousBubble != bubbleView) {
        [WBBubbleStyler removeFromBubbleView:previousBubble];
    }
    if (![WBBubbleThemeProvider isEnabled] || direction == WBBubbleDirectionUnknown || !WBValidTextBubble(bubbleView, textView)) {
        WBClearStyle(object, bubbleView);
        return;
    }
    if ([WBBubbleStyler applyToBubbleView:bubbleView direction:direction]) {
        objc_setAssociatedObject(object, &WBLastStyledBubbleKey, bubbleView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else {
        WBClearStyle(object, bubbleView);
    }
}

static void WBLayoutContentViewHook(id object, SEL selector) {
    WBOriginalLayoutContentView(object, selector);
    WBApplyStyle(object);
}

@implementation WBTextBubbleStyleHook

+ (BOOL)install {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cellClass = NSClassFromString(@"TextMessageCellView");
        Class backgroundClass = NSClassFromString(@"YYAsyncImageView");
        Class textClass = NSClassFromString(@"RichTextView");
        SEL selector = NSSelectorFromString(@"layoutContentView");
        Method method = cellClass ? class_getInstanceMethod(cellClass, selector) : NULL;
        BOOL selectorsAvailable = cellClass && [cellClass instancesRespondToSelector:NSSelectorFromString(@"getBgImageView")] && [cellClass instancesRespondToSelector:NSSelectorFromString(@"getRichTextView")] && [cellClass instancesRespondToSelector:NSSelectorFromString(@"getHeadImageView")];
        if (!method || !backgroundClass || !textClass || !selectorsAvailable) {
            return;
        }
        MSHookMessageEx(cellClass, selector, (IMP)WBLayoutContentViewHook, (IMP *)&WBOriginalLayoutContentView);
        WBHookInstalled = WBOriginalLayoutContentView != NULL;
    });
    return WBHookInstalled;
}

+ (NSDictionary<NSString *, id> *)configurationSnapshot {
    Class cellClass = NSClassFromString(@"TextMessageCellView");
    return @{
        @"mode": @"fixed-solid-colors",
        @"themeIdentifier": [WBBubbleThemeProvider themeIdentifier],
        @"enabled": @([WBBubbleThemeProvider isEnabled]),
        @"hookInstalled": @(WBHookInstalled),
        @"targetClassAvailable": @(cellClass != Nil),
        @"backgroundClassAvailable": @(NSClassFromString(@"YYAsyncImageView") != Nil),
        @"textClassAvailable": @(NSClassFromString(@"RichTextView") != Nil),
        @"layoutSelectorAvailable": @(cellClass && class_getInstanceMethod(cellClass, NSSelectorFromString(@"layoutContentView")) != NULL),
        @"backgroundSelectorAvailable": @(cellClass && [cellClass instancesRespondToSelector:NSSelectorFromString(@"getBgImageView")]),
        @"textSelectorAvailable": @(cellClass && [cellClass instancesRespondToSelector:NSSelectorFromString(@"getRichTextView")]),
        @"avatarSelectorAvailable": @(cellClass && [cellClass instancesRespondToSelector:NSSelectorFromString(@"getHeadImageView")]),
        @"directionRule": @"stable-MMHeadImageView-outer-quartile",
        @"messageDataRead": @NO,
        @"textRead": @NO,
        @"recursiveViewTreeScanned": @NO
    };
}

@end
