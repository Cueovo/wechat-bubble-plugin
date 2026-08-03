#import "WBBubbleStyler.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

static UIBezierPath *WBBubblePath(CGRect bounds, WBBubbleTailSide tailSide, WBBubbleSegmentPosition segmentPosition) {
    CGFloat minX = CGRectGetMinX(bounds);
    CGFloat minY = CGRectGetMinY(bounds);
    CGFloat maxX = CGRectGetMaxX(bounds);
    CGFloat maxY = CGRectGetMaxY(bounds);
    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);
    CGFloat tailWidth = MIN(5.0, width * 0.12);
    CGFloat radius = MIN([WBBubbleThemeProvider cornerRadius], MIN((width - tailWidth) * 0.5, height * 0.5));
    CGFloat topRadius = (segmentPosition == WBBubbleSegmentPositionMiddle || segmentPosition == WBBubbleSegmentPositionBottom) ? 0.0 : radius;
    CGFloat bottomRadius = (segmentPosition == WBBubbleSegmentPositionTop || segmentPosition == WBBubbleSegmentPositionMiddle) ? 0.0 : radius;
    CGFloat straightTop = minY + topRadius;
    CGFloat straightBottom = maxY - bottomRadius;
    CGFloat availableHeight = straightBottom - straightTop;
    BOOL includesTail = (segmentPosition == WBBubbleSegmentPositionSingle || segmentPosition == WBBubbleSegmentPositionTop) && availableHeight >= 10.0;
    CGFloat bodyMinX = tailSide == WBBubbleTailSideLeft ? minX + tailWidth : minX;
    CGFloat bodyMaxX = tailSide == WBBubbleTailSideRight ? maxX - tailWidth : maxX;
    CGFloat tailSpan = includesTail ? MIN(10.0, availableHeight - 2.0) : 0.0;
    CGFloat tailCenter = MIN(MAX(minY + MIN(13.0, height * 0.35), straightTop + tailSpan * 0.5), straightBottom - tailSpan * 0.5);
    CGFloat tailTop = tailCenter - tailSpan * 0.5;
    CGFloat tailBottom = tailCenter + tailSpan * 0.5;
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(bodyMinX + topRadius, minY)];
    [path addLineToPoint:CGPointMake(bodyMaxX - topRadius, minY)];
    [path addQuadCurveToPoint:CGPointMake(bodyMaxX, minY + topRadius) controlPoint:CGPointMake(bodyMaxX, minY)];
    if (tailSide == WBBubbleTailSideRight && includesTail) {
        [path addLineToPoint:CGPointMake(bodyMaxX, tailTop)];
        [path addLineToPoint:CGPointMake(maxX, tailCenter)];
        [path addLineToPoint:CGPointMake(bodyMaxX, tailBottom)];
    }
    [path addLineToPoint:CGPointMake(bodyMaxX, maxY - bottomRadius)];
    [path addQuadCurveToPoint:CGPointMake(bodyMaxX - bottomRadius, maxY) controlPoint:CGPointMake(bodyMaxX, maxY)];
    [path addLineToPoint:CGPointMake(bodyMinX + bottomRadius, maxY)];
    [path addQuadCurveToPoint:CGPointMake(bodyMinX, maxY - bottomRadius) controlPoint:CGPointMake(bodyMinX, maxY)];
    if (tailSide == WBBubbleTailSideLeft && includesTail) {
        [path addLineToPoint:CGPointMake(bodyMinX, tailBottom)];
        [path addLineToPoint:CGPointMake(minX, tailCenter)];
        [path addLineToPoint:CGPointMake(bodyMinX, tailTop)];
    }
    [path addLineToPoint:CGPointMake(bodyMinX, minY + topRadius)];
    [path addQuadCurveToPoint:CGPointMake(bodyMinX + topRadius, minY) controlPoint:CGPointMake(bodyMinX, minY)];
    [path closePath];
    return path;
}

static UIBezierPath *WBBubbleBorderPath(CGRect bounds, WBBubbleTailSide tailSide, WBBubbleSegmentPosition segmentPosition) {
    if (segmentPosition == WBBubbleSegmentPositionSingle) {
        return WBBubblePath(bounds, tailSide, segmentPosition);
    }
    CGFloat minX = CGRectGetMinX(bounds);
    CGFloat minY = CGRectGetMinY(bounds);
    CGFloat maxX = CGRectGetMaxX(bounds);
    CGFloat maxY = CGRectGetMaxY(bounds);
    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);
    CGFloat tailWidth = MIN(5.0, width * 0.12);
    CGFloat radius = MIN([WBBubbleThemeProvider cornerRadius], MIN((width - tailWidth) * 0.5, height * 0.5));
    CGFloat bodyMinX = tailSide == WBBubbleTailSideLeft ? minX + tailWidth : minX;
    CGFloat bodyMaxX = tailSide == WBBubbleTailSideRight ? maxX - tailWidth : maxX;
    UIBezierPath *path = [UIBezierPath bezierPath];
    if (segmentPosition == WBBubbleSegmentPositionMiddle) {
        [path moveToPoint:CGPointMake(bodyMinX, minY)];
        [path addLineToPoint:CGPointMake(bodyMinX, maxY)];
        [path moveToPoint:CGPointMake(bodyMaxX, minY)];
        [path addLineToPoint:CGPointMake(bodyMaxX, maxY)];
        return path;
    }
    if (segmentPosition == WBBubbleSegmentPositionBottom) {
        [path moveToPoint:CGPointMake(bodyMinX, minY)];
        [path addLineToPoint:CGPointMake(bodyMinX, maxY - radius)];
        [path addQuadCurveToPoint:CGPointMake(bodyMinX + radius, maxY) controlPoint:CGPointMake(bodyMinX, maxY)];
        [path addLineToPoint:CGPointMake(bodyMaxX - radius, maxY)];
        [path addQuadCurveToPoint:CGPointMake(bodyMaxX, maxY - radius) controlPoint:CGPointMake(bodyMaxX, maxY)];
        [path addLineToPoint:CGPointMake(bodyMaxX, minY)];
        return path;
    }
    CGFloat tailSpan = MIN(10.0, MAX(0.0, height - radius - 2.0));
    CGFloat tailCenter = MIN(MAX(minY + MIN(13.0, height * 0.35), minY + radius + tailSpan * 0.5), maxY - tailSpan * 0.5);
    CGFloat tailTop = tailCenter - tailSpan * 0.5;
    CGFloat tailBottom = tailCenter + tailSpan * 0.5;
    [path moveToPoint:CGPointMake(bodyMinX, maxY)];
    if (tailSide == WBBubbleTailSideLeft && tailSpan > 0.0) {
        [path addLineToPoint:CGPointMake(bodyMinX, tailBottom)];
        [path addLineToPoint:CGPointMake(minX, tailCenter)];
        [path addLineToPoint:CGPointMake(bodyMinX, tailTop)];
    }
    [path addLineToPoint:CGPointMake(bodyMinX, minY + radius)];
    [path addQuadCurveToPoint:CGPointMake(bodyMinX + radius, minY) controlPoint:CGPointMake(bodyMinX, minY)];
    [path addLineToPoint:CGPointMake(bodyMaxX - radius, minY)];
    [path addQuadCurveToPoint:CGPointMake(bodyMaxX, minY + radius) controlPoint:CGPointMake(bodyMaxX, minY)];
    if (tailSide == WBBubbleTailSideRight && tailSpan > 0.0) {
        [path addLineToPoint:CGPointMake(bodyMaxX, tailTop)];
        [path addLineToPoint:CGPointMake(maxX, tailCenter)];
        [path addLineToPoint:CGPointMake(bodyMaxX, tailBottom)];
    }
    [path addLineToPoint:CGPointMake(bodyMaxX, maxY)];
    return path;
}

@interface WBBubbleOverlayView : UIView
@property (nonatomic, strong) CAShapeLayer *shapeLayer;
@property (nonatomic, strong) CAShapeLayer *borderLayer;
@property (nonatomic, strong) CAShapeLayer *maskLayer;
@property (nonatomic, assign) WBBubbleDirection direction;
@property (nonatomic, assign) WBBubbleTailSide tailSide;
@property (nonatomic, assign) WBBubbleSegmentPosition segmentPosition;
@end

@implementation WBBubbleOverlayView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = UIColor.clearColor;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _shapeLayer = [CAShapeLayer layer];
        _shapeLayer.name = @"com.bi8bo.wechat.bubble.style";
        _shapeLayer.contentsScale = UIScreen.mainScreen.scale;
        [self.layer addSublayer:_shapeLayer];
        _borderLayer = [CAShapeLayer layer];
        _borderLayer.contentsScale = UIScreen.mainScreen.scale;
        _borderLayer.fillColor = UIColor.clearColor.CGColor;
        _borderLayer.lineJoin = kCALineJoinRound;
        _borderLayer.lineCap = kCALineCapButt;
        [self.layer addSublayer:_borderLayer];
        _maskLayer = [CAShapeLayer layer];
        _maskLayer.contentsScale = UIScreen.mainScreen.scale;
        _maskLayer.fillColor = UIColor.blackColor.CGColor;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect localBounds = (CGRect){CGPointZero, self.bounds.size};
    UIBezierPath *path = WBBubblePath(localBounds, self.tailSide, self.segmentPosition);
    UIBezierPath *borderPath = WBBubbleBorderPath(localBounds, self.tailSide, self.segmentPosition);
    UITraitCollection *traits = self.traitCollection;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.shapeLayer.frame = localBounds;
    self.shapeLayer.path = path.CGPath;
    self.shapeLayer.fillColor = [WBBubbleThemeProvider fillColorForDirection:self.direction traitCollection:traits].CGColor;
    self.shapeLayer.strokeColor = UIColor.clearColor.CGColor;
    self.borderLayer.frame = localBounds;
    self.borderLayer.path = borderPath.CGPath;
    self.borderLayer.strokeColor = [WBBubbleThemeProvider borderColorForDirection:self.direction traitCollection:traits].CGColor;
    self.borderLayer.lineWidth = [WBBubbleThemeProvider borderWidth];
    self.maskLayer.frame = localBounds;
    self.maskLayer.path = path.CGPath;
    [CATransaction commit];
}

@end

@interface WBBubbleStyleState : NSObject
@property (nonatomic, strong) WBBubbleOverlayView *overlayView;
@property (nonatomic, strong, nullable) CALayer *originalMask;
@property (nonatomic, copy) NSString *themeIdentifier;
@end

@implementation WBBubbleStyleState
@end

static char WBBubbleStyleStateKey;

@implementation WBBubbleStyler

+ (BOOL)applyToBubbleView:(UIView *)bubbleView direction:(WBBubbleDirection)direction tailSide:(WBBubbleTailSide)tailSide segmentPosition:(WBBubbleSegmentPosition)segmentPosition {
    if (!NSThread.isMainThread || ![WBBubbleThemeProvider isEnabled] || direction == WBBubbleDirectionUnknown || CGRectIsEmpty(bubbleView.bounds)) {
        [self removeFromBubbleView:bubbleView];
        return NO;
    }
    WBBubbleStyleState *state = objc_getAssociatedObject(bubbleView, &WBBubbleStyleStateKey);
    if (!state) {
        state = [WBBubbleStyleState new];
        state.overlayView = [[WBBubbleOverlayView alloc] initWithFrame:bubbleView.bounds];
        state.originalMask = bubbleView.layer.mask;
        objc_setAssociatedObject(bubbleView, &WBBubbleStyleStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    WBBubbleOverlayView *overlayView = state.overlayView;
    if (overlayView.superview != bubbleView) {
        [overlayView removeFromSuperview];
        [bubbleView insertSubview:overlayView atIndex:0];
    }
    overlayView.frame = bubbleView.bounds;
    overlayView.direction = direction;
    overlayView.tailSide = tailSide;
    overlayView.segmentPosition = segmentPosition;
    if (bubbleView.layer.mask != overlayView.maskLayer) {
        state.originalMask = bubbleView.layer.mask;
        bubbleView.layer.mask = overlayView.maskLayer;
    }
    [overlayView setNeedsLayout];
    [overlayView layoutIfNeeded];
    state.themeIdentifier = [WBBubbleThemeProvider themeIdentifier];
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
    if (bubbleView.layer.mask == state.overlayView.maskLayer) {
        bubbleView.layer.mask = state.originalMask;
    }
    [CATransaction commit];
    [state.overlayView removeFromSuperview];
    objc_setAssociatedObject(bubbleView, &WBBubbleStyleStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end
