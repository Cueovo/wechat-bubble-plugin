#import "WBBubbleStyler.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

@interface WBBubbleStyleState : NSObject
@property (nonatomic, strong) CAShapeLayer *shapeLayer;
@property (nonatomic, copy) NSString *themeIdentifier;
@property (nonatomic, assign) WBBubbleDirection direction;
@end

@implementation WBBubbleStyleState
@end

static char WBBubbleStyleStateKey;

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
        objc_setAssociatedObject(bubbleView, &WBBubbleStyleStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UITraitCollection *traits = bubbleView.traitCollection;
    CGFloat borderWidth = [WBBubbleThemeProvider borderWidth];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (state.shapeLayer.superlayer != bubbleView.layer || bubbleView.layer.sublayers.firstObject != state.shapeLayer) {
        [state.shapeLayer removeFromSuperlayer];
        [bubbleView.layer insertSublayer:state.shapeLayer atIndex:0];
    }
    state.shapeLayer.frame = bubbleView.bounds;
    CGRect pathRect = CGRectInset(state.shapeLayer.bounds, borderWidth * 0.5, borderWidth * 0.5);
    CGFloat radius = MIN([WBBubbleThemeProvider cornerRadius], MIN(CGRectGetWidth(pathRect), CGRectGetHeight(pathRect)) * 0.5);
    state.shapeLayer.path = [UIBezierPath bezierPathWithRoundedRect:pathRect cornerRadius:radius].CGPath;
    state.shapeLayer.fillColor = [[WBBubbleThemeProvider fillColorForDirection:direction traitCollection:traits] colorWithAlphaComponent:[WBBubbleThemeProvider fillOpacity]].CGColor;
    state.shapeLayer.strokeColor = [WBBubbleThemeProvider borderColorForDirection:direction traitCollection:traits].CGColor;
    state.shapeLayer.lineWidth = borderWidth;
    state.shapeLayer.hidden = NO;
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
    [CATransaction commit];
    objc_setAssociatedObject(bubbleView, &WBBubbleStyleStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end
