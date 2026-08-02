#import "WBBubbleStyler.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

@interface WBBubbleStyleState : NSObject
@property (nonatomic, strong) CAShapeLayer *shapeLayer;
@property (nonatomic, strong) CAShapeLayer *maskLayer;
@property (nonatomic, strong, nullable) CALayer *originalMask;
@property (nonatomic, copy) NSString *themeIdentifier;
@property (nonatomic, assign) WBBubbleDirection direction;
@end

@implementation WBBubbleStyleState
@end

static char WBBubbleStyleStateKey;

static UIBezierPath *WBBubblePath(CGRect bounds, WBBubbleDirection direction) {
    CGFloat minX = CGRectGetMinX(bounds);
    CGFloat minY = CGRectGetMinY(bounds);
    CGFloat maxX = CGRectGetMaxX(bounds);
    CGFloat maxY = CGRectGetMaxY(bounds);
    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);
    CGFloat tailWidth = MIN(5.0, width * 0.12);
    CGFloat radius = MIN([WBBubbleThemeProvider cornerRadius], MIN((width - tailWidth) * 0.5, height * 0.5));
    CGFloat straightTop = minY + radius;
    CGFloat straightBottom = maxY - radius;
    CGFloat availableHeight = straightBottom - straightTop;
    BOOL includesTail = availableHeight >= 10.0;
    if (!includesTail) {
        tailWidth = 0.0;
    }
    CGFloat bodyMinX = direction == WBBubbleDirectionIncoming ? minX + tailWidth : minX;
    CGFloat bodyMaxX = direction == WBBubbleDirectionOutgoing ? maxX - tailWidth : maxX;
    CGFloat tailSpan = includesTail ? MIN(10.0, availableHeight - 2.0) : 0.0;
    CGFloat tailCenter = MIN(MAX(minY + MIN(13.0, height * 0.35), straightTop + tailSpan * 0.5), straightBottom - tailSpan * 0.5);
    CGFloat tailTop = tailCenter - tailSpan * 0.5;
    CGFloat tailBottom = tailCenter + tailSpan * 0.5;
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(bodyMinX + radius, minY)];
    [path addLineToPoint:CGPointMake(bodyMaxX - radius, minY)];
    [path addQuadCurveToPoint:CGPointMake(bodyMaxX, minY + radius) controlPoint:CGPointMake(bodyMaxX, minY)];
    if (direction == WBBubbleDirectionOutgoing && includesTail) {
        [path addLineToPoint:CGPointMake(bodyMaxX, tailTop)];
        [path addLineToPoint:CGPointMake(maxX, tailCenter)];
        [path addLineToPoint:CGPointMake(bodyMaxX, tailBottom)];
    }
    [path addLineToPoint:CGPointMake(bodyMaxX, maxY - radius)];
    [path addQuadCurveToPoint:CGPointMake(bodyMaxX - radius, maxY) controlPoint:CGPointMake(bodyMaxX, maxY)];
    [path addLineToPoint:CGPointMake(bodyMinX + radius, maxY)];
    [path addQuadCurveToPoint:CGPointMake(bodyMinX, maxY - radius) controlPoint:CGPointMake(bodyMinX, maxY)];
    if (direction == WBBubbleDirectionIncoming && includesTail) {
        [path addLineToPoint:CGPointMake(bodyMinX, tailBottom)];
        [path addLineToPoint:CGPointMake(minX, tailCenter)];
        [path addLineToPoint:CGPointMake(bodyMinX, tailTop)];
    }
    [path addLineToPoint:CGPointMake(bodyMinX, minY + radius)];
    [path addQuadCurveToPoint:CGPointMake(bodyMinX + radius, minY) controlPoint:CGPointMake(bodyMinX, minY)];
    [path closePath];
    return path;
}

@implementation WBBubbleStyler

+ (BOOL)applyToBubbleView:(UIView *)bubbleView direction:(WBBubbleDirection)direction {
    if (!NSThread.isMainThread || ![WBBubbleThemeProvider isEnabled] || direction == WBBubbleDirectionUnknown || CGRectIsEmpty(bubbleView.bounds)) {
        [self removeFromBubbleView:bubbleView];
        return NO;
    }
    WBBubbleStyleState *state = objc_getAssociatedObject(bubbleView, &WBBubbleStyleStateKey);
    if (!state) {
        state = [WBBubbleStyleState new];
        state.shapeLayer = [CAShapeLayer layer];
        state.shapeLayer.name = @"com.bi8bo.wechat.bubble.style";
        state.shapeLayer.contentsScale = UIScreen.mainScreen.scale;
        state.maskLayer = [CAShapeLayer layer];
        state.maskLayer.contentsScale = UIScreen.mainScreen.scale;
        state.maskLayer.fillColor = UIColor.blackColor.CGColor;
        state.originalMask = bubbleView.layer.mask;
        objc_setAssociatedObject(bubbleView, &WBBubbleStyleStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGRect layerFrame = bubbleView.layer.bounds;
    CGRect localBounds = (CGRect){CGPointZero, layerFrame.size};
    UIBezierPath *path = WBBubblePath(localBounds, direction);
    UITraitCollection *traits = bubbleView.traitCollection;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (state.shapeLayer.superlayer != bubbleView.layer || bubbleView.layer.sublayers.firstObject != state.shapeLayer) {
        [state.shapeLayer removeFromSuperlayer];
        [bubbleView.layer insertSublayer:state.shapeLayer atIndex:0];
    }
    state.shapeLayer.frame = layerFrame;
    state.shapeLayer.path = path.CGPath;
    state.shapeLayer.fillColor = [[WBBubbleThemeProvider fillColorForDirection:direction traitCollection:traits] colorWithAlphaComponent:[WBBubbleThemeProvider fillOpacity]].CGColor;
    state.shapeLayer.strokeColor = [WBBubbleThemeProvider borderColorForDirection:direction traitCollection:traits].CGColor;
    state.shapeLayer.lineWidth = [WBBubbleThemeProvider borderWidth];
    state.shapeLayer.hidden = NO;
    state.maskLayer.frame = layerFrame;
    state.maskLayer.path = path.CGPath;
    if (bubbleView.layer.mask != state.maskLayer) {
        state.originalMask = bubbleView.layer.mask;
        bubbleView.layer.mask = state.maskLayer;
    }
    [CATransaction commit];
    state.themeIdentifier = [WBBubbleThemeProvider themeIdentifier];
    state.direction = direction;
    return YES;
}

+ (void)removeFromBubbleView:(UIView *)bubbleView {
    if (!bubbleView) {
        return;
    }
    WBBubbleStyleState *state = objc_getAssociatedObject(bubbleView, &WBBubbleStyleStateKey);
    if (!state) {
        return;
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [state.shapeLayer removeFromSuperlayer];
    if (bubbleView.layer.mask == state.maskLayer) {
        bubbleView.layer.mask = state.originalMask;
    }
    [CATransaction commit];
    objc_setAssociatedObject(bubbleView, &WBBubbleStyleStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end
