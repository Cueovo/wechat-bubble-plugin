#import "WBBubbleStyler.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

static UIBezierPath *WBBubblePath(CGRect bounds, WBBubbleTailSide tailSide) {
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
    CGFloat bodyMinX = tailSide == WBBubbleTailSideLeft ? minX + tailWidth : minX;
    CGFloat bodyMaxX = tailSide == WBBubbleTailSideRight ? maxX - tailWidth : maxX;
    CGFloat tailSpan = includesTail ? MIN(10.0, availableHeight - 2.0) : 0.0;
    CGFloat tailCenter = MIN(MAX(minY + MIN(13.0, height * 0.35), straightTop + tailSpan * 0.5), straightBottom - tailSpan * 0.5);
    CGFloat tailTop = tailCenter - tailSpan * 0.5;
    CGFloat tailBottom = tailCenter + tailSpan * 0.5;
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(bodyMinX + radius, minY)];
    [path addLineToPoint:CGPointMake(bodyMaxX - radius, minY)];
    [path addQuadCurveToPoint:CGPointMake(bodyMaxX, minY + radius) controlPoint:CGPointMake(bodyMaxX, minY)];
    if (tailSide == WBBubbleTailSideRight && includesTail) {
        [path addLineToPoint:CGPointMake(bodyMaxX, tailTop)];
        [path addLineToPoint:CGPointMake(maxX, tailCenter)];
        [path addLineToPoint:CGPointMake(bodyMaxX, tailBottom)];
    }
    [path addLineToPoint:CGPointMake(bodyMaxX, maxY - radius)];
    [path addQuadCurveToPoint:CGPointMake(bodyMaxX - radius, maxY) controlPoint:CGPointMake(bodyMaxX, maxY)];
    [path addLineToPoint:CGPointMake(bodyMinX + radius, maxY)];
    [path addQuadCurveToPoint:CGPointMake(bodyMinX, maxY - radius) controlPoint:CGPointMake(bodyMinX, maxY)];
    if (tailSide == WBBubbleTailSideLeft && includesTail) {
        [path addLineToPoint:CGPointMake(bodyMinX, tailBottom)];
        [path addLineToPoint:CGPointMake(minX, tailCenter)];
        [path addLineToPoint:CGPointMake(bodyMinX, tailTop)];
    }
    [path addLineToPoint:CGPointMake(bodyMinX, minY + radius)];
    [path addQuadCurveToPoint:CGPointMake(bodyMinX + radius, minY) controlPoint:CGPointMake(bodyMinX, minY)];
    [path closePath];
    return path;
}

@interface WBBubbleOverlayView : UIView
@property (nonatomic, strong) CAShapeLayer *shapeLayer;
@property (nonatomic, strong) CAShapeLayer *maskLayer;
@property (nonatomic, assign) WBBubbleDirection direction;
@property (nonatomic, assign) WBBubbleTailSide tailSide;
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
        _maskLayer = [CAShapeLayer layer];
        _maskLayer.contentsScale = UIScreen.mainScreen.scale;
        _maskLayer.fillColor = UIColor.blackColor.CGColor;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect localBounds = (CGRect){CGPointZero, self.bounds.size};
    UIBezierPath *path = WBBubblePath(localBounds, self.tailSide);
    UITraitCollection *traits = self.traitCollection;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.shapeLayer.frame = localBounds;
    self.shapeLayer.path = path.CGPath;
    self.shapeLayer.fillColor = [WBBubbleThemeProvider fillColorForDirection:self.direction traitCollection:traits].CGColor;
    self.shapeLayer.strokeColor = [WBBubbleThemeProvider borderColorForDirection:self.direction traitCollection:traits].CGColor;
    self.shapeLayer.lineWidth = [WBBubbleThemeProvider borderWidth];
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

+ (BOOL)applyToBubbleView:(UIView *)bubbleView direction:(WBBubbleDirection)direction tailSide:(WBBubbleTailSide)tailSide {
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
