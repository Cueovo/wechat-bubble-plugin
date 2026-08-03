#import "WBBubbleStyler.h"
#import "WBSDFDisplacementRenderer.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
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
@property (nonatomic, strong) UIVisualEffectView *effectView;
@property (nonatomic, strong) UIView *tintView;
@property (nonatomic, strong) UIView *borderView;
@property (nonatomic, strong) CAShapeLayer *shapeLayer;
@property (nonatomic, strong) CAGradientLayer *rimLayer;
@property (nonatomic, strong) CAShapeLayer *rimMaskLayer;
@property (nonatomic, strong) CAGradientLayer *shadeLayer;
@property (nonatomic, strong) CAShapeLayer *shadeMaskLayer;
@property (nonatomic, strong) CAShapeLayer *borderLayer;
@property (nonatomic, strong) CAShapeLayer *maskLayer;
@property (nonatomic, strong) WBSDFDisplacementRenderer *sdfRenderer;
@property (nonatomic, copy, nullable) NSString *effectSignature;
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
        _effectView = [[UIVisualEffectView alloc] initWithEffect:nil];
        _effectView.userInteractionEnabled = NO;
        _effectView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:_effectView];
        _tintView = [[UIView alloc] initWithFrame:_effectView.contentView.bounds];
        _tintView.userInteractionEnabled = NO;
        _tintView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [_effectView.contentView addSubview:_tintView];
        _shapeLayer = [CAShapeLayer layer];
        _shapeLayer.name = @"com.bi8bo.wechat.bubble.style";
        _shapeLayer.contentsScale = UIScreen.mainScreen.scale;
        [self.layer addSublayer:_shapeLayer];
        _borderView = [[UIView alloc] initWithFrame:self.bounds];
        _borderView.userInteractionEnabled = NO;
        _borderView.backgroundColor = UIColor.clearColor;
        _borderView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:_borderView];
        _borderLayer = [CAShapeLayer layer];
        [_borderLayer setContentsScale:UIScreen.mainScreen.scale];
        [_borderLayer setFillColor:UIColor.clearColor.CGColor];
        [_borderLayer setLineJoin:kCALineJoinRound];
        [_borderLayer setLineCap:kCALineCapButt];
        [_borderView.layer addSublayer:_borderLayer];
        _rimLayer = [CAGradientLayer layer];
        _rimLayer.startPoint = CGPointMake(0.0, 0.0);
        _rimLayer.endPoint = CGPointMake(1.0, 1.0);
        _rimMaskLayer = [CAShapeLayer layer];
        _rimMaskLayer.fillColor = UIColor.clearColor.CGColor;
        _rimMaskLayer.strokeColor = UIColor.whiteColor.CGColor;
        _rimLayer.mask = _rimMaskLayer;
        [_borderView.layer addSublayer:_rimLayer];
        _shadeLayer = [CAGradientLayer layer];
        _shadeLayer.startPoint = CGPointMake(0.0, 0.0);
        _shadeLayer.endPoint = CGPointMake(1.0, 1.0);
        _shadeMaskLayer = [CAShapeLayer layer];
        _shadeMaskLayer.fillColor = UIColor.clearColor.CGColor;
        _shadeMaskLayer.strokeColor = UIColor.whiteColor.CGColor;
        _shadeLayer.mask = _shadeMaskLayer;
        [_borderView.layer addSublayer:_shadeLayer];
        _maskLayer = [CAShapeLayer layer];
        [_maskLayer setContentsScale:UIScreen.mainScreen.scale];
        _maskLayer.fillColor = UIColor.blackColor.CGColor;
        _sdfRenderer = [WBSDFDisplacementRenderer new];
    }
    return self;
}

- (void)updateGlassEffectForDarkAppearance:(BOOL)dark {
    NSString *backend = [WBBubbleThemeProvider resolvedMaterialBackend];
    NSString *signature = [NSString stringWithFormat:@"%@-%d", backend, dark];
    if ([self.effectSignature isEqualToString:signature]) {
        return;
    }
    if ([backend isEqualToString:@"native-uiglass-effect"]) {
        @try {
            [self.sdfRenderer reset];
            id effect = [[NSClassFromString(@"UIGlassEffect") alloc] init];
            SEL tintSelector = NSSelectorFromString(@"setTintColor:");
            SEL interactiveSelector = NSSelectorFromString(@"setInteractive:");
            ((void (*)(id, SEL, id))objc_msgSend)(effect, tintSelector, nil);
            ((void (*)(id, SEL, BOOL))objc_msgSend)(effect, interactiveSelector, NO);
            if ([effect isKindOfClass:UIVisualEffect.class]) {
                self.effectView.transform = CGAffineTransformIdentity;
                self.effectView.effect = (UIVisualEffect *)effect;
                self.tintView.hidden = YES;
                self.effectSignature = signature;
                return;
            }
        } @catch (__unused NSException *exception) {
        }
        [WBBubbleThemeProvider disableNativeLiquidGlassForProcess];
        self.effectSignature = nil;
        [self updateGlassEffectForDarkAppearance:dark];
        return;
    }
    if ([backend isEqualToString:@"compatibility-sdf-displacement"]) {
        self.effectView.transform = CGAffineTransformIdentity;
        self.effectView.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial];
        self.tintView.hidden = YES;
        self.tintView.backgroundColor = UIColor.clearColor;
        self.effectSignature = signature;
        return;
    }
    [self.sdfRenderer reset];
    self.effectView.transform = CGAffineTransformMakeScale(1.045, 1.08);
    self.effectView.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial];
    self.tintView.hidden = YES;
    self.tintView.backgroundColor = UIColor.clearColor;
    self.effectSignature = signature;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect localBounds = (CGRect){CGPointZero, self.bounds.size};
    UIBezierPath *path = WBBubblePath(localBounds, self.tailSide, self.segmentPosition);
    UIBezierPath *borderPath = WBBubbleBorderPath(localBounds, self.tailSide, self.segmentPosition);
    UITraitCollection *traits = self.traitCollection;
    BOOL dark = traits.userInterfaceStyle == UIUserInterfaceStyleDark;
    UIColor *fillColor = [WBBubbleThemeProvider fillColorForDirection:self.direction traitCollection:traits];
    BOOL usesGlass = [WBBubbleThemeProvider usesGlassMaterial];
    NSString *backend = [WBBubbleThemeProvider resolvedMaterialBackend];
    BOOL sdfGlass = NO;
    self.effectView.frame = localBounds;
    self.effectView.hidden = !usesGlass;
    if (usesGlass) {
        [self updateGlassEffectForDarkAppearance:dark];
        backend = [WBBubbleThemeProvider resolvedMaterialBackend];
        sdfGlass = [backend isEqualToString:@"compatibility-sdf-displacement"];
        if (sdfGlass) {
            NSString *cacheKey = [NSString stringWithFormat:@"%ld-%ld-%.2f", (long)self.tailSide, (long)self.segmentPosition, [WBBubbleThemeProvider cornerRadius]];
            WBSDFApplicationResult result = [self.sdfRenderer applyToEffectView:self.effectView path:path bounds:localBounds cacheKey:cacheKey];
            if (result == WBSDFApplicationResultFailed) {
                self.effectSignature = nil;
                backend = [WBBubbleThemeProvider resolvedMaterialBackend];
                sdfGlass = NO;
                [self updateGlassEffectForDarkAppearance:dark];
            }
        }
    } else {
        [self.sdfRenderer reset];
        self.effectView.transform = CGAffineTransformIdentity;
        self.effectView.effect = nil;
        self.effectSignature = nil;
    }
    BOOL compatibilityGlass = usesGlass && ([backend isEqualToString:@"compatibility-colorless-lens"] || sdfGlass);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.shapeLayer.frame = localBounds;
    self.shapeLayer.path = path.CGPath;
    self.shapeLayer.fillColor = compatibilityGlass ? [UIColor colorWithWhite:1.0 alpha:dark ? 0.035 : 0.075].CGColor : (usesGlass ? UIColor.clearColor.CGColor : fillColor.CGColor);
    self.shapeLayer.strokeColor = UIColor.clearColor.CGColor;
    self.borderView.frame = localBounds;
    self.borderLayer.frame = localBounds;
    self.borderLayer.path = borderPath.CGPath;
    self.borderLayer.strokeColor = usesGlass ? UIColor.clearColor.CGColor : [WBBubbleThemeProvider borderColorForDirection:self.direction traitCollection:traits].CGColor;
    self.borderLayer.lineWidth = usesGlass ? 0.0 : [WBBubbleThemeProvider borderWidth];
    self.rimLayer.hidden = !compatibilityGlass;
    self.rimLayer.frame = localBounds;
    self.rimLayer.colors = @[(id)[UIColor colorWithWhite:1.0 alpha:dark ? 0.58 : 0.82].CGColor, (id)[UIColor colorWithWhite:1.0 alpha:0.06].CGColor, (id)[UIColor colorWithWhite:1.0 alpha:dark ? 0.20 : 0.34].CGColor];
    self.rimLayer.locations = @[@0.0, @0.52, @1.0];
    self.rimMaskLayer.frame = localBounds;
    self.rimMaskLayer.path = borderPath.CGPath;
    self.rimMaskLayer.lineWidth = 1.25;
    self.shadeLayer.hidden = !compatibilityGlass;
    self.shadeLayer.frame = localBounds;
    self.shadeLayer.colors = @[(id)UIColor.clearColor.CGColor, (id)[UIColor colorWithWhite:0.0 alpha:dark ? 0.24 : 0.13].CGColor];
    self.shadeMaskLayer.frame = localBounds;
    self.shadeMaskLayer.path = borderPath.CGPath;
    self.shadeMaskLayer.lineWidth = 2.5;
    self.maskLayer.frame = localBounds;
    self.maskLayer.path = path.CGPath;
    [CATransaction commit];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (!previousTraitCollection || previousTraitCollection.userInterfaceStyle != self.traitCollection.userInterfaceStyle) {
        [self setNeedsLayout];
        [self layoutIfNeeded];
    }
}

@end

@interface WBBubbleStyleState : NSObject
@property (nonatomic, strong) WBBubbleOverlayView *overlayView;
@property (nonatomic, strong, nullable) CALayer *originalMask;
@property (nonatomic, strong, nullable) UIImage *originalImage;
@property (nonatomic, strong, nullable) id originalAnimatedImage;
@property (nonatomic, strong, nullable) id originalLayerContents;
@property (nonatomic, strong, nullable) UIColor *originalBackgroundColor;
@property (nonatomic, assign) BOOL capturedImageState;
@property (nonatomic, copy) NSString *themeIdentifier;
@end

@implementation WBBubbleStyleState
@end

static char WBBubbleStyleStateKey;
static char WBInternalArtworkUpdateKey;

@implementation WBBubbleStyler

+ (id)animatedImageForImageView:(UIImageView *)imageView {
    SEL selector = NSSelectorFromString(@"animatedImage");
    return [imageView respondsToSelector:selector] ? ((id (*)(id, SEL))objc_msgSend)(imageView, selector) : nil;
}

+ (void)setImage:(UIImage *)image forImageView:(UIImageView *)imageView {
    objc_setAssociatedObject(imageView, &WBInternalArtworkUpdateKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    imageView.image = image;
    objc_setAssociatedObject(imageView, &WBInternalArtworkUpdateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

+ (void)setAnimatedImage:(id)animatedImage forImageView:(UIImageView *)imageView {
    SEL selector = NSSelectorFromString(@"setAnimatedImage:");
    if ([imageView respondsToSelector:selector]) {
        objc_setAssociatedObject(imageView, &WBInternalArtworkUpdateKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        ((void (*)(id, SEL, id))objc_msgSend)(imageView, selector, animatedImage);
        objc_setAssociatedObject(imageView, &WBInternalArtworkUpdateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

+ (void)hideOriginalArtworkFromImageView:(UIImageView *)imageView state:(WBBubbleStyleState *)state {
    id animatedImage = [self animatedImageForImageView:imageView];
    if (!state.capturedImageState) {
        state.originalBackgroundColor = imageView.backgroundColor;
        state.capturedImageState = YES;
    }
    if (imageView.image) {
        state.originalImage = imageView.image;
    }
    if (animatedImage) {
        state.originalAnimatedImage = animatedImage;
    }
    if (imageView.layer.contents) {
        state.originalLayerContents = imageView.layer.contents;
    }
    [self setAnimatedImage:nil forImageView:imageView];
    [self setImage:nil forImageView:imageView];
    imageView.layer.contents = nil;
    imageView.backgroundColor = UIColor.clearColor;
}

+ (void)restoreOriginalArtworkToImageView:(UIImageView *)imageView state:(WBBubbleStyleState *)state {
    if (!state.capturedImageState) {
        return;
    }
    [self setImage:state.originalImage forImageView:imageView];
    [self setAnimatedImage:state.originalAnimatedImage forImageView:imageView];
    if (!state.originalImage && !state.originalAnimatedImage) {
        imageView.layer.contents = state.originalLayerContents;
    }
    imageView.backgroundColor = state.originalBackgroundColor;
    state.originalImage = nil;
    state.originalAnimatedImage = nil;
    state.originalLayerContents = nil;
    state.originalBackgroundColor = nil;
    state.capturedImageState = NO;
}

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
    if ([bubbleView isKindOfClass:UIImageView.class]) {
        if ([WBBubbleThemeProvider usesGlassMaterial]) {
            [self hideOriginalArtworkFromImageView:(UIImageView *)bubbleView state:state];
        } else {
            [self restoreOriginalArtworkToImageView:(UIImageView *)bubbleView state:state];
        }
    }
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
        [bubbleView.layer setMask:overlayView.maskLayer];
    }
    [overlayView setNeedsLayout];
    [overlayView layoutIfNeeded];
    state.themeIdentifier = [WBBubbleThemeProvider themeIdentifier];
    return YES;
}

+ (BOOL)captureArtworkUpdate:(id)artwork forBubbleView:(UIView *)bubbleView animated:(BOOL)animated {
    if (objc_getAssociatedObject(bubbleView, &WBInternalArtworkUpdateKey) || ![WBBubbleThemeProvider usesGlassMaterial]) {
        return NO;
    }
    WBBubbleStyleState *state = objc_getAssociatedObject(bubbleView, &WBBubbleStyleStateKey);
    if (!state || state.overlayView.superview != bubbleView || ![bubbleView isKindOfClass:UIImageView.class]) {
        return NO;
    }
    if (!artwork) {
        if (animated) {
            state.originalAnimatedImage = nil;
        } else {
            state.originalImage = nil;
        }
        return NO;
    }
    if (!animated && ![artwork isKindOfClass:UIImage.class]) {
        return NO;
    }
    if (animated) {
        state.originalAnimatedImage = artwork;
        state.originalImage = nil;
    } else {
        state.originalImage = artwork;
        state.originalAnimatedImage = nil;
    }
    UIImageView *imageView = (UIImageView *)bubbleView;
    [self setAnimatedImage:nil forImageView:imageView];
    [self setImage:nil forImageView:imageView];
    imageView.layer.contents = nil;
    imageView.backgroundColor = UIColor.clearColor;
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
    if ([bubbleView isKindOfClass:UIImageView.class]) {
        [self restoreOriginalArtworkToImageView:(UIImageView *)bubbleView state:state];
    }
}

@end
