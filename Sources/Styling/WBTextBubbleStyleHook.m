#import "WBTextBubbleStyleHook.h"
#import "WBBubbleStyler.h"
#import "WBBubblePreferences.h"
#import "WBBubbleThemeProvider.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>

static void (*WBOriginalLayoutContentView)(id, SEL);
static void (*WBOriginalLayoutSubviews)(id, SEL);
static void (*WBOriginalPrepareForReuse)(id, SEL);
static void (*WBOriginalSetImage)(id, SEL, id);
static void (*WBOriginalSetAnimatedImage)(id, SEL, id);
static BOOL WBHookInstalled;
static BOOL WBArtworkHooksInstalled;
static id WBPreferencesObserver;
static NSHashTable<UIView *> *WBTrackedMessageCells;
static char WBLastStyledBubbleKey;

static BOOL WBValidObjectSetterMethod(Method method) {
    if (!method || method_getNumberOfArguments(method) != 3) {
        return NO;
    }
    char returnType[8] = {0};
    char argumentType[8] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    method_getArgumentType(method, 2, argumentType, sizeof(argumentType));
    return returnType[0] == 'v' && argumentType[0] == '@';
}

static UIView *WBViewFromSelector(id object, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    id value = [object respondsToSelector:selector] ? ((id (*)(id, SEL))objc_msgSend)(object, selector) : nil;
    return [value isKindOfClass:UIView.class] ? value : nil;
}

static UIView *WBDescendantOfClass(UIView *rootView, Class targetClass) {
    if (!rootView || !targetClass) {
        return nil;
    }
    for (UIView *subview in rootView.subviews) {
        if ([subview isKindOfClass:targetClass]) {
            return subview;
        }
        UIView *match = WBDescendantOfClass(subview, targetClass);
        if (match) {
            return match;
        }
    }
    return nil;
}

static id WBValueFromSelector(id object, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    return [object respondsToSelector:selector] ? ((id (*)(id, SEL))objc_msgSend)(object, selector) : nil;
}

static UIView *WBAvatarView(id object, UIView *cellView) {
    UIView *avatarView = WBViewFromSelector(object, @"getHeadImageView");
    if (avatarView) {
        return avatarView;
    }
    Class avatarClass = NSClassFromString(@"MMHeadImageView");
    return WBDescendantOfClass(cellView, avatarClass);
}

static UIView *WBTextViewForCell(id object, UIView *cellView) {
    UIView *textView = WBViewFromSelector(object, @"getRichTextView");
    if (textView) {
        return textView;
    }
    return WBDescendantOfClass(cellView, NSClassFromString(@"RichTextView"));
}

static id WBMessageWrapForCell(id object) {
    id messageWrap = WBValueFromSelector(object, @"getCurrentMessageWrap");
    return messageWrap ?: WBValueFromSelector(object, @"messageWrap");
}

static long long WBMessageIdentifier(id messageWrap) {
    static NSArray<NSString *> *selectorNames;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        selectorNames = @[@"m_n64MesSvrID", @"mesSvrID", @"getMesSvrID", @"m_uiMesLocalID", @"mesLocalID"];
    });
    for (NSString *selectorName in selectorNames) {
        SEL selector = NSSelectorFromString(selectorName);
        if ([messageWrap respondsToSelector:selector]) {
            long long identifier = ((long long (*)(id, SEL))objc_msgSend)(messageWrap, selector);
            if (identifier != 0) {
                return identifier;
            }
        }
    }
    return 0;
}

static BOOL WBSameMessage(id leftCell, id rightCell) {
    id leftWrap = WBMessageWrapForCell(leftCell);
    id rightWrap = WBMessageWrapForCell(rightCell);
    if (!leftWrap || !rightWrap) {
        return NO;
    }
    if (leftWrap == rightWrap) {
        return YES;
    }
    long long leftIdentifier = WBMessageIdentifier(leftWrap);
    return leftIdentifier != 0 && leftIdentifier == WBMessageIdentifier(rightWrap);
}

static void WBCollectMessageCells(UIView *rootView, Class cellClass, NSMutableArray<UIView *> *cells) {
    if ([rootView isKindOfClass:cellClass]) {
        [cells addObject:rootView];
    }
    for (UIView *subview in rootView.subviews) {
        WBCollectMessageCells(subview, cellClass, cells);
    }
}

static UIView *WBMessageCellRoot(UIView *cellView) {
    UIView *rootView = cellView;
    for (NSUInteger depth = 0; depth < 5 && rootView.superview; depth++) {
        rootView = rootView.superview;
        if ([rootView isKindOfClass:UITableView.class]) {
            break;
        }
    }
    return rootView;
}

static WBBubbleSegmentPosition WBSegmentPositionForCell(id object, UIView *cellView) {
    Class cellClass = NSClassFromString(@"CommonMessageCellView");
    if (!cellClass || !WBMessageWrapForCell(object)) {
        return WBBubbleSegmentPositionSingle;
    }
    UIView *rootView = cellView;
    for (NSUInteger depth = 0; depth < 5 && rootView.superview; depth++) {
        rootView = rootView.superview;
        if ([rootView isKindOfClass:UITableView.class]) {
            break;
        }
    }
    NSMutableArray<UIView *> *cells = [NSMutableArray array];
    WBCollectMessageCells(rootView, cellClass, cells);
    CGRect currentRect = [cellView convertRect:cellView.bounds toView:rootView];
    BOOL hasPreviousSegment = NO;
    BOOL hasNextSegment = NO;
    for (UIView *candidate in cells) {
        if (candidate == cellView || !WBSameMessage(object, candidate)) {
            continue;
        }
        CGRect candidateRect = [candidate convertRect:candidate.bounds toView:rootView];
        CGFloat verticalGap;
        if (CGRectGetMidY(candidateRect) < CGRectGetMidY(currentRect)) {
            verticalGap = CGRectGetMinY(currentRect) - CGRectGetMaxY(candidateRect);
            hasPreviousSegment |= verticalGap >= -4.0 && verticalGap <= 8.0;
        } else {
            verticalGap = CGRectGetMinY(candidateRect) - CGRectGetMaxY(currentRect);
            hasNextSegment |= verticalGap >= -4.0 && verticalGap <= 8.0;
        }
    }
    if (hasPreviousSegment && hasNextSegment) {
        return WBBubbleSegmentPositionMiddle;
    }
    if (hasNextSegment) {
        return WBBubbleSegmentPositionTop;
    }
    if (hasPreviousSegment) {
        return WBBubbleSegmentPositionBottom;
    }
    return WBBubbleSegmentPositionSingle;
}

static WBBubbleDirection WBDirectionForMessage(id object, UIView *avatarView, UIView *cellView) {
    id messageWrap = WBMessageWrapForCell(object);
    Class messageClass = NSClassFromString(@"CMessageWrap");
    SEL senderSelector = NSSelectorFromString(@"isSenderFromMsgWrap:");
    if (messageWrap && messageClass && [messageClass respondsToSelector:senderSelector]) {
        BOOL isSender = ((BOOL (*)(id, SEL, id))objc_msgSend)(messageClass, senderSelector, messageWrap);
        return isSender ? WBBubbleDirectionOutgoing : WBBubbleDirectionIncoming;
    }
    if (!avatarView || avatarView.hidden || avatarView.alpha <= 0.01 || CGRectGetWidth(cellView.bounds) < 200.0) {
        return WBBubbleDirectionUnknown;
    }
    CGRect avatarRect = [avatarView convertRect:avatarView.bounds toView:cellView];
    CGFloat cellWidth = CGRectGetWidth(cellView.bounds);
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

static WBBubbleTailSide WBTailSideForDirection(WBBubbleDirection direction) {
    return direction == WBBubbleDirectionIncoming ? WBBubbleTailSideLeft : WBBubbleTailSideRight;
}

static BOOL WBValidTextBubble(UIView *bubbleView, UIView *textView) {
    Class backgroundClass = NSClassFromString(@"YYAsyncImageView");
    Class textClass = NSClassFromString(@"RichTextView");
    if (!backgroundClass || !textClass || !bubbleView || !textView || ![bubbleView isKindOfClass:backgroundClass] || ![textView isKindOfClass:textClass]) {
        return NO;
    }
    CGRect bubbleBounds = bubbleView.bounds;
    if (CGRectGetWidth(bubbleBounds) < 30.0 || CGRectGetHeight(bubbleBounds) < 20.0 || bubbleView.hidden || bubbleView.alpha <= 0.01 || textView.hidden || textView.alpha <= 0.01) {
        return NO;
    }
    if ([textView isDescendantOfView:bubbleView]) {
        CGRect textRect = [textView convertRect:textView.bounds toView:bubbleView];
        if (CGRectIsEmpty(textRect) || !CGRectIntersectsRect(CGRectInset(bubbleBounds, -8.0, -8.0), textRect)) {
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

static void WBApplyStyle(id object, BOOL clearIfInvalid) {
    if (!NSThread.isMainThread || ![object isKindOfClass:UIView.class]) {
        return;
    }
    UIView *cellView = object;
    if (!WBTrackedMessageCells) {
        WBTrackedMessageCells = [NSHashTable weakObjectsHashTable];
    }
    [WBTrackedMessageCells addObject:cellView];
    UIView *bubbleView = WBViewFromSelector(object, @"getBgImageView");
    if (![WBBubbleThemeProvider isEnabled]) {
        if (clearIfInvalid) {
            WBClearStyle(object, bubbleView);
        }
        return;
    }
    UIView *textView = WBTextViewForCell(object, cellView);
    UIView *avatarView = WBAvatarView(object, cellView);
    WBBubbleDirection direction = WBDirectionForMessage(object, avatarView, cellView);
    WBBubbleTailSide tailSide = WBTailSideForDirection(direction);
    WBBubbleSegmentPosition segmentPosition = WBSegmentPositionForCell(object, cellView);
    BOOL tailSideKnown = direction != WBBubbleDirectionUnknown;
    UIView *previousBubble = objc_getAssociatedObject(object, &WBLastStyledBubbleKey);
    if (previousBubble && previousBubble != bubbleView) {
        [WBBubbleStyler removeFromBubbleView:previousBubble];
    }
    if (direction == WBBubbleDirectionUnknown || !tailSideKnown || !WBValidTextBubble(bubbleView, textView)) {
        if (clearIfInvalid) {
            WBClearStyle(object, bubbleView);
        }
        return;
    }
    if ([WBBubbleStyler applyToBubbleView:bubbleView direction:direction tailSide:tailSide segmentPosition:segmentPosition]) {
        objc_setAssociatedObject(object, &WBLastStyledBubbleKey, bubbleView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else {
        WBClearStyle(object, bubbleView);
    }
}

static BOOL WBRefreshingMessageSegments;

static void WBRefreshMessageSegments(id object, UIView *cellView) {
    if (WBRefreshingMessageSegments || !cellView.window || !WBMessageWrapForCell(object)) {
        return;
    }
    Class cellClass = NSClassFromString(@"CommonMessageCellView");
    UIView *rootView = WBMessageCellRoot(cellView);
    NSMutableArray<UIView *> *cells = [NSMutableArray array];
    WBCollectMessageCells(rootView, cellClass, cells);
    WBRefreshingMessageSegments = YES;
    for (UIView *candidate in cells) {
        if (candidate.window && WBSameMessage(object, candidate)) {
            WBApplyStyle(candidate, NO);
        }
    }
    WBRefreshingMessageSegments = NO;
}

static void WBRefreshAllVisibleMessageCells(void) {
    for (UIView *cell in WBTrackedMessageCells.allObjects) {
        if (cell.window) {
            WBApplyStyle(cell, YES);
        }
    }
}

static void WBObservePreferences(void) {
    if (WBPreferencesObserver) {
        return;
    }
    WBPreferencesObserver = [NSNotificationCenter.defaultCenter addObserverForName:WBBubblePreferencesDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *notification) {
        WBRefreshAllVisibleMessageCells();
    }];
}

static void WBLayoutContentViewHook(id object, SEL selector) {
    if (!WBOriginalLayoutContentView) {
        return;
    }
    WBClearStyle(object, nil);
    WBOriginalLayoutContentView(object, selector);
    WBApplyStyle(object, YES);
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *cellView = [object isKindOfClass:UIView.class] ? object : nil;
        if (cellView.window) {
            WBRefreshMessageSegments(object, cellView);
        }
    });
}

static void WBLayoutSubviewsHook(id object, SEL selector) {
    if (!WBOriginalLayoutSubviews) {
        return;
    }
    WBOriginalLayoutSubviews(object, selector);
    WBApplyStyle(object, NO);
    UIView *cellView = [object isKindOfClass:UIView.class] ? object : nil;
    if (cellView.window) {
        WBRefreshMessageSegments(object, cellView);
    }
}

static void WBPrepareForReuseHook(id object, SEL selector) {
    WBClearStyle(object, nil);
    if (WBOriginalPrepareForReuse) {
        WBOriginalPrepareForReuse(object, selector);
    }
}

static void WBSetImageHook(id object, SEL selector, id image) {
    if (![WBBubbleStyler captureArtworkUpdate:image forBubbleView:object animated:NO] && WBOriginalSetImage) {
        WBOriginalSetImage(object, selector, image);
    }
}

static void WBSetAnimatedImageHook(id object, SEL selector, id image) {
    if (![WBBubbleStyler captureArtworkUpdate:image forBubbleView:object animated:YES] && WBOriginalSetAnimatedImage) {
        WBOriginalSetAnimatedImage(object, selector, image);
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
        Class cellClass = NSClassFromString(@"CommonMessageCellView");
        Class backgroundClass = NSClassFromString(@"YYAsyncImageView");
        Class textClass = NSClassFromString(@"RichTextView");
        SEL selector = NSSelectorFromString(@"layoutContentView");
        Method method = cellClass ? class_getInstanceMethod(cellClass, selector) : NULL;
        BOOL selectorsAvailable = cellClass && [cellClass instancesRespondToSelector:NSSelectorFromString(@"getBgImageView")] && [cellClass instancesRespondToSelector:NSSelectorFromString(@"getHeadImageView")];
        if (!method || !backgroundClass || !textClass || !selectorsAvailable) {
            return NO;
        }
        MSHookMessageEx(cellClass, selector, (IMP)WBLayoutContentViewHook, (IMP *)&WBOriginalLayoutContentView);
        WBHookInstalled = WBOriginalLayoutContentView != NULL;
        SEL layoutSubviewsSelector = NSSelectorFromString(@"layoutSubviews");
        if (WBHookInstalled && class_getInstanceMethod(cellClass, layoutSubviewsSelector)) {
            MSHookMessageEx(cellClass, layoutSubviewsSelector, (IMP)WBLayoutSubviewsHook, (IMP *)&WBOriginalLayoutSubviews);
        }
        SEL reuseSelector = NSSelectorFromString(@"prepareForReuse");
        if (WBHookInstalled && class_getInstanceMethod(cellClass, reuseSelector)) {
            MSHookMessageEx(cellClass, reuseSelector, (IMP)WBPrepareForReuseHook, (IMP *)&WBOriginalPrepareForReuse);
        }
        if (WBHookInstalled) {
            SEL setImageSelector = NSSelectorFromString(@"setImage:");
            Method setImageMethod = class_getInstanceMethod(backgroundClass, setImageSelector);
            if (WBValidObjectSetterMethod(setImageMethod)) {
                MSHookMessageEx(backgroundClass, setImageSelector, (IMP)WBSetImageHook, (IMP *)&WBOriginalSetImage);
            }
            SEL setAnimatedImageSelector = NSSelectorFromString(@"setAnimatedImage:");
            Method setAnimatedImageMethod = class_getInstanceMethod(backgroundClass, setAnimatedImageSelector);
            if (WBValidObjectSetterMethod(setAnimatedImageMethod)) {
                MSHookMessageEx(backgroundClass, setAnimatedImageSelector, (IMP)WBSetAnimatedImageHook, (IMP *)&WBOriginalSetAnimatedImage);
            }
            WBArtworkHooksInstalled = WBOriginalSetImage != NULL && (!setAnimatedImageMethod || WBOriginalSetAnimatedImage != NULL);
            WBObservePreferences();
        }
    }
    return WBHookInstalled;
}

+ (NSDictionary<NSString *, id> *)configurationSnapshot {
    Class cellClass = NSClassFromString(@"CommonMessageCellView");
    return @{
        @"mode": @"user-configurable-explicit-refraction-glass",
        @"themeIdentifier": [WBBubbleThemeProvider themeIdentifier],
        @"artworkHooksInstalled": @(WBArtworkHooksInstalled),
        @"requestedMaterial": [WBBubbleThemeProvider materialIdentifier],
        @"resolvedMaterialBackend": [WBBubbleThemeProvider resolvedMaterialBackend],
        @"glassCapabilities": [WBBubbleThemeProvider glassCapabilitySnapshot],
        @"nativeLiquidGlassAvailable": @([WBBubbleThemeProvider nativeLiquidGlassAvailable]),
        @"enabled": @([WBBubbleThemeProvider isEnabled]),
        @"hookInstalled": @(WBHookInstalled),
        @"targetClassAvailable": @(cellClass != Nil),
        @"backgroundClassAvailable": @(NSClassFromString(@"YYAsyncImageView") != Nil),
        @"textClassAvailable": @(NSClassFromString(@"RichTextView") != Nil),
        @"layoutSelectorAvailable": @(cellClass && class_getInstanceMethod(cellClass, NSSelectorFromString(@"layoutContentView")) != NULL),
        @"backgroundSelectorAvailable": @(cellClass && [cellClass instancesRespondToSelector:NSSelectorFromString(@"getBgImageView")]),
        @"textSelectorAvailable": @(cellClass != Nil),
        @"avatarSelectorAvailable": @(cellClass && [cellClass instancesRespondToSelector:NSSelectorFromString(@"getHeadImageView")]),
        @"directionRule": @"CMessageWrap-isSenderFromMsgWrap-plus-avatar-edge-fallback",
        @"messageDataRead": @YES,
        @"messageModelMetadataRead": @YES,
        @"messageContentRead": @NO,
        @"textRead": @NO,
        @"recursiveViewTreeScanned": @YES
    };
}

@end
