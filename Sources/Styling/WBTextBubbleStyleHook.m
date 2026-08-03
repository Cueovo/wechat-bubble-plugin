#import "WBTextBubbleStyleHook.h"
#import "WBBubbleStyler.h"
#import "WBBubbleThemeProvider.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <math.h>

static void (*WBOriginalLayoutContentView)(id, SEL);
static void (*WBOriginalPrepareForReuse)(id, SEL);
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
    if (CGRectIsEmpty(avatarRect) || CGRectGetWidth(avatarRect) < 24.0 || CGRectGetHeight(avatarRect) < 24.0 || CGRectGetMinY(avatarRect) <= 1.0) {
        return WBBubbleDirectionUnknown;
    }
    CGFloat leftInset = CGRectGetMinX(avatarRect);
    CGFloat rightInset = cellWidth - CGRectGetMaxX(avatarRect);
    if (leftInset >= 2.0 && leftInset <= 24.0 && rightInset > cellWidth * 0.5) {
        return WBBubbleDirectionIncoming;
    }
    if (rightInset >= 2.0 && rightInset <= 24.0 && leftInset > cellWidth * 0.5) {
        return WBBubbleDirectionOutgoing;
    }
    return WBBubbleDirectionUnknown;
}

static BOOL WBTailSideForBubbleView(UIView *bubbleView, UIView *avatarView, UIView *cellView, WBBubbleTailSide *tailSide) {
    if (!bubbleView || !avatarView || !tailSide) {
        return NO;
    }
    CGPoint avatarCenter = [avatarView convertPoint:CGPointMake(CGRectGetMidX(avatarView.bounds), CGRectGetMidY(avatarView.bounds)) toView:cellView];
    CGFloat bubbleMidY = CGRectGetMidY(bubbleView.bounds);
    CGPoint localLeft = [bubbleView convertPoint:CGPointMake(CGRectGetMinX(bubbleView.bounds), bubbleMidY) toView:cellView];
    CGPoint localRight = [bubbleView convertPoint:CGPointMake(CGRectGetMaxX(bubbleView.bounds), bubbleMidY) toView:cellView];
    CGFloat leftDistance = fabs(localLeft.x - avatarCenter.x);
    CGFloat rightDistance = fabs(localRight.x - avatarCenter.x);
    if (!isfinite(leftDistance) || !isfinite(rightDistance) || fabs(leftDistance - rightDistance) < 4.0) {
        return NO;
    }
    *tailSide = leftDistance < rightDistance ? WBBubbleTailSideLeft : WBBubbleTailSideRight;
    return YES;
}

static BOOL WBValidTextBubble(UIView *bubbleView, UIView *textView, WBBubbleTailSide tailSide) {
    Class backgroundClass = NSClassFromString(@"YYAsyncImageView");
    Class textClass = NSClassFromString(@"RichTextView");
    if (!backgroundClass || !textClass || !bubbleView || !textView || ![bubbleView isKindOfClass:backgroundClass] || ![textView isKindOfClass:textClass]) {
        return NO;
    }
    CGFloat width = CGRectGetWidth(bubbleView.bounds);
    CGFloat height = CGRectGetHeight(bubbleView.bounds);
    CGFloat widthPadding = width - CGRectGetWidth(textView.bounds);
    CGFloat heightPadding = height - CGRectGetHeight(textView.bounds);
    if (width < 30.0 || height < 30.0 || widthPadding < 12.0 || widthPadding > 60.0 || heightPadding < 10.0 || heightPadding > 50.0) {
        return NO;
    }
    if ([textView isDescendantOfView:bubbleView]) {
        CGRect textRect = [textView convertRect:textView.bounds toView:bubbleView];
        CGRect safeRect = CGRectInset(bubbleView.bounds, 4.0, 3.0);
        if (tailSide == WBBubbleTailSideLeft) {
            safeRect.origin.x += 5.0;
            safeRect.size.width -= 5.0;
        } else {
            safeRect.size.width -= 5.0;
        }
        if (!CGRectContainsRect(safeRect, textRect)) {
            return NO;
        }
    }
    return YES;
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
    WBBubbleTailSide tailSide = WBBubbleTailSideLeft;
    BOOL tailSideKnown = WBTailSideForBubbleView(bubbleView, avatarView, cellView, &tailSide);
    UIView *previousBubble = objc_getAssociatedObject(object, &WBLastStyledBubbleKey);
    if (previousBubble && previousBubble != bubbleView) {
        [WBBubbleStyler removeFromBubbleView:previousBubble];
    }
    if (![WBBubbleThemeProvider isEnabled] || direction == WBBubbleDirectionUnknown || !tailSideKnown || !WBValidTextBubble(bubbleView, textView, tailSide)) {
        WBClearStyle(object, bubbleView);
        return;
    }
    if ([WBBubbleStyler applyToBubbleView:bubbleView direction:direction tailSide:tailSide]) {
        objc_setAssociatedObject(object, &WBLastStyledBubbleKey, bubbleView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else {
        WBClearStyle(object, bubbleView);
    }
}

static void WBLayoutContentViewHook(id object, SEL selector) {
    if (!WBOriginalLayoutContentView) {
        return;
    }
    WBClearStyle(object, nil);
    WBOriginalLayoutContentView(object, selector);
    WBApplyStyle(object);
}

static void WBPrepareForReuseHook(id object, SEL selector) {
    WBClearStyle(object, nil);
    if (WBOriginalPrepareForReuse) {
        WBOriginalPrepareForReuse(object, selector);
    }
}

@implementation WBTextBubbleStyleHook

+ (BOOL)install {
    if (WBHookInstalled) {
        return YES;
    }
    @synchronized (self) {
        if (WBHookInstalled) {
            return YES;
        }
        Class cellClass = NSClassFromString(@"TextMessageCellView");
        Class backgroundClass = NSClassFromString(@"YYAsyncImageView");
        Class textClass = NSClassFromString(@"RichTextView");
        SEL selector = NSSelectorFromString(@"layoutContentView");
        Method method = cellClass ? class_getInstanceMethod(cellClass, selector) : NULL;
        BOOL selectorsAvailable = cellClass && [cellClass instancesRespondToSelector:NSSelectorFromString(@"getBgImageView")] && [cellClass instancesRespondToSelector:NSSelectorFromString(@"getRichTextView")] && [cellClass instancesRespondToSelector:NSSelectorFromString(@"getHeadImageView")];
        if (!method || !backgroundClass || !textClass || !selectorsAvailable) {
            return NO;
        }
        MSHookMessageEx(cellClass, selector, (IMP)WBLayoutContentViewHook, (IMP *)&WBOriginalLayoutContentView);
        WBHookInstalled = WBOriginalLayoutContentView != NULL;
        SEL reuseSelector = NSSelectorFromString(@"prepareForReuse");
        if (WBHookInstalled && class_getInstanceMethod(cellClass, reuseSelector)) {
            MSHookMessageEx(cellClass, reuseSelector, (IMP)WBPrepareForReuseHook, (IMP *)&WBOriginalPrepareForReuse);
        }
    }
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
        @"directionRule": @"stable-avatar-edge-plus-local-bubble-edge",
        @"messageDataRead": @NO,
        @"textRead": @NO,
        @"recursiveViewTreeScanned": @NO
    };
}

@end
