#import "WBBubbleDiscoveryHook.h"
#import "WBDiagnostics.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <string.h>

static void (*WBOriginalLayoutContentView)(id, SEL);
static NSMutableArray<NSDictionary<NSString *, id> *> *WBSamples;
static NSMutableSet<NSString *> *WBSignatures;
static NSUInteger WBLayoutCallCount;
static BOOL WBWriteScheduled;

static NSDictionary<NSString *, NSNumber *> *WBRectSnapshot(CGRect rect) {
    return @{
        @"x": @(CGRectGetMinX(rect)),
        @"y": @(CGRectGetMinY(rect)),
        @"width": @(CGRectGetWidth(rect)),
        @"height": @(CGRectGetHeight(rect))
    };
}

static NSString *WBClassName(id object) {
    return object ? NSStringFromClass([object class]) : @"";
}

static NSArray<NSDictionary<NSString *, id> *> *WBDirectSubviewSnapshot(UIView *view) {
    NSMutableArray<NSDictionary<NSString *, id> *> *subviews = [NSMutableArray array];
    for (UIView *subview in view.subviews) {
        if (subviews.count >= 24) {
            break;
        }
        [subviews addObject:@{
            @"class": WBClassName(subview),
            @"frame": WBRectSnapshot(subview.frame),
            @"hidden": @(subview.hidden),
            @"alpha": @(subview.alpha)
        }];
    }
    return subviews;
}

static UIView *WBAvatarView(UIView *view) {
    for (UIView *subview in view.subviews) {
        if ([WBClassName(subview) isEqualToString:@"MMHeadImageView"]) {
            return subview;
        }
    }
    return nil;
}

static NSDictionary<NSString *, id> *WBImageMetadata(id candidate) {
    if (![candidate isKindOfClass:UIImageView.class]) {
        return @{};
    }
    UIImageView *imageView = candidate;
    UIImage *image = imageView.image;
    SEL animatedImageSelector = NSSelectorFromString(@"animatedImage");
    id animatedImage = [candidate respondsToSelector:animatedImageSelector] ? ((id (*)(id, SEL))objc_msgSend)(candidate, animatedImageSelector) : nil;
    return @{
        @"imagePresent": @(image != nil),
        @"highlightedImagePresent": @(imageView.highlightedImage != nil),
        @"animationImageCount": @(imageView.animationImages.count),
        @"highlightedAnimationImageCount": @(imageView.highlightedAnimationImages.count),
        @"animatedImageGetterAvailable": @([candidate respondsToSelector:animatedImageSelector]),
        @"animatedImagePresent": @(animatedImage != nil),
        @"layerContentsPresent": @(imageView.layer.contents != nil),
        @"backgroundColorPresent": @(imageView.backgroundColor != nil),
        @"opaque": @(imageView.opaque),
        @"imageSize": image ? @{@"width": @(image.size.width), @"height": @(image.size.height)} : @{},
        @"capInsets": image ? @{
            @"top": @(image.capInsets.top),
            @"left": @(image.capInsets.left),
            @"bottom": @(image.capInsets.bottom),
            @"right": @(image.capInsets.right)
        } : @{},
        @"resizingMode": image ? @(image.resizingMode) : @(-1),
        @"contentMode": @(imageView.contentMode),
        @"cornerRadius": @(imageView.layer.cornerRadius),
        @"borderWidth": @(imageView.layer.borderWidth),
        @"masksToBounds": @(imageView.layer.masksToBounds)
    };
}

static NSString *WBDirectionForAvatarRect(CGRect avatarRect, CGFloat cellWidth) {
    if (cellWidth <= 0 || CGRectIsEmpty(avatarRect)) {
        return @"unknown";
    }
    return CGRectGetMidX(avatarRect) < cellWidth * 0.5 ? @"left" : @"right";
}

static void WBWriteSamplesLater(void) {
    if (WBWriteScheduled) {
        return;
    }
    WBWriteScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSArray<NSDictionary<NSString *, id> *> *samples = [WBSamples copy];
        NSUInteger layoutCallCount = WBLayoutCallCount;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            NSDictionary<NSString *, id> *observation = @{
                @"mode": @"TextMessageCellView.layoutContentView-post-original",
                @"directionRule": @"MMHeadImageView-horizontal-midpoint",
                @"layoutCallCount": @(layoutCallCount),
                @"uniqueSampleCount": @(samples.count),
                @"samples": samples,
                @"messageDataRead": @NO,
                @"textRead": @NO,
                @"directSubviewsScanned": @YES,
                @"recursiveViewTreeScanned": @NO
            };
            NSError *error = nil;
            [WBDiagnostics updateDiscovery:@{@"observation": observation} error:&error];
        });
    });
}

static void WBCollectLayoutSample(id object) {
    if (!NSThread.isMainThread || ![object isKindOfClass:UIView.class] || WBLayoutCallCount >= 120) {
        return;
    }
    WBLayoutCallCount++;
    UIView *cellView = object;
    SEL backgroundSelector = NSSelectorFromString(@"getBgImageView");
    SEL richTextSelector = NSSelectorFromString(@"getRichTextView");
    id backgroundView = [object respondsToSelector:backgroundSelector] ? ((id (*)(id, SEL))objc_msgSend)(object, backgroundSelector) : nil;
    id richTextView = [object respondsToSelector:richTextSelector] ? ((id (*)(id, SEL))objc_msgSend)(object, richTextSelector) : nil;
    if (![backgroundView isKindOfClass:UIView.class]) {
        return;
    }
    UIView *bubbleView = backgroundView;
    UIView *avatarView = WBAvatarView(cellView);
    CGRect bubbleRect = [bubbleView convertRect:bubbleView.bounds toView:cellView];
    CGRect avatarRect = avatarView ? [avatarView convertRect:avatarView.bounds toView:cellView] : CGRectZero;
    CGRect richTextRect = [richTextView isKindOfClass:UIView.class] ? [(UIView *)richTextView convertRect:((UIView *)richTextView).bounds toView:cellView] : CGRectZero;
    NSString *direction = WBDirectionForAvatarRect(avatarRect, CGRectGetWidth(cellView.bounds));
    NSString *signature = [NSString stringWithFormat:@"%@|%@|%@|%.0f|%.0f|%.0f|%.0f", direction, WBClassName(backgroundView), WBClassName(richTextView), CGRectGetWidth(bubbleRect), CGRectGetHeight(bubbleRect), CGRectGetWidth(richTextRect), CGRectGetHeight(richTextRect)];
    if ([WBSignatures containsObject:signature] || WBSamples.count >= 24) {
        return;
    }
    [WBSignatures addObject:signature];
    [WBSamples addObject:@{
        @"direction": direction,
        @"directionSourceClass": WBClassName(avatarView),
        @"avatarFrameInCell": WBRectSnapshot(avatarRect),
        @"cellClass": WBClassName(cellView),
        @"cellBounds": WBRectSnapshot(cellView.bounds),
        @"backgroundViewClass": WBClassName(backgroundView),
        @"backgroundFrameInCell": WBRectSnapshot(bubbleRect),
        @"backgroundHidden": @(((UIView *)backgroundView).hidden),
        @"backgroundAlpha": @(((UIView *)backgroundView).alpha),
        @"backgroundImage": WBImageMetadata(backgroundView),
        @"richTextViewClass": WBClassName(richTextView),
        @"richTextFrameInCell": WBRectSnapshot(richTextRect),
        @"directSubviews": WBDirectSubviewSnapshot(cellView)
    }];
    WBWriteSamplesLater();
}

static void WBLayoutContentViewHook(id object, SEL selector) {
    if (!WBOriginalLayoutContentView) {
        return;
    }
    WBOriginalLayoutContentView(object, selector);
    @autoreleasepool {
        WBCollectLayoutSample(object);
    }
}

@implementation WBBubbleDiscoveryHook

+ (BOOL)install {
    Class candidateClass = NSClassFromString(@"TextMessageCellView");
    SEL selector = NSSelectorFromString(@"layoutContentView");
    Method method = candidateClass ? class_getInstanceMethod(candidateClass, selector) : NULL;
    if (!method || method_getNumberOfArguments(method) != 2) {
        return NO;
    }
    char returnType[8] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    if (strcmp(returnType, @encode(void)) != 0) {
        return NO;
    }
    WBSamples = [NSMutableArray array];
    WBSignatures = [NSMutableSet set];
    MSHookMessageEx(candidateClass, selector, (IMP)WBLayoutContentViewHook, (IMP *)&WBOriginalLayoutContentView);
    return WBOriginalLayoutContentView != NULL;
}

@end
