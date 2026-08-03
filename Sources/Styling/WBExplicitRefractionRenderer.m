#import "WBExplicitRefractionRenderer.h"
#import "../Discovery/WBDiagnostics.h"
#import <CoreImage/CoreImage.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>
#import <objc/message.h>

static BOOL WBExplicitCapabilityProbed;
static BOOL WBExplicitCapabilityAvailable;
static NSString *WBExplicitProbeReason = @"not-probed";
static NSString *WBExplicitLastFailure = @"none";
static NSUInteger WBExplicitCaptureCount;
static NSUInteger WBExplicitFailureCount;
static double WBExplicitLastCaptureMilliseconds;
static double WBExplicitLastWarpMilliseconds;
static CGFloat WBExplicitLastScale;
static CGFloat WBExplicitLastSourceWidth;
static CGFloat WBExplicitLastSourceHeight;
static CGFloat WBExplicitLastOutputWidth;
static CGFloat WBExplicitLastOutputHeight;

static CIWarpKernel *WBExplicitWarpKernel(void) {
    static CIWarpKernel *kernel;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *source = @"kernel vec2 wbLens(vec2 center, vec2 halfSize, float radius, float edgeWidth, float amount) { vec2 coordinate = destCoord(); vec2 p = coordinate - center; vec2 q = abs(p) - (halfSize - vec2(radius)); vec2 outside = max(q, vec2(0.0)); float distance = length(outside) + min(max(q.x, q.y), 0.0) - radius; float depth = clamp(1.0 + distance / edgeWidth, 0.0, 1.0); float profile = 1.0 - sqrt(max(0.0, 1.0 - depth * depth)); vec2 normal; if (q.x > q.y) { normal = vec2(sign(p.x), 0.0); } else { normal = vec2(0.0, sign(p.y)); } if (q.x > 0.0 && q.y > 0.0) { normal = normalize(outside * sign(p)); } return coordinate + normal * amount * profile; }";
        SEL selector = NSSelectorFromString(@"kernelWithString:");
        kernel = [CIWarpKernel respondsToSelector:selector] ? ((id (*)(id, SEL, id))objc_msgSend)(CIWarpKernel.class, selector, source) : nil;
    });
    return kernel;
}

static CIContext *WBExplicitContext(void) {
    static CIContext *context;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        context = [CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer: @NO}];
    });
    return context;
}

static void WBExplicitWriteDiagnostics(void) {
    NSDictionary *runtime;
    @synchronized(WBExplicitRefractionRenderer.class) {
        runtime = @{
            @"applicationSucceeded": @(WBExplicitCaptureCount > 0),
            @"captureCount": @(WBExplicitCaptureCount),
            @"failureCount": @(WBExplicitFailureCount),
            @"lastFailure": WBExplicitLastFailure,
            @"captureMilliseconds": @(WBExplicitLastCaptureMilliseconds),
            @"warpMilliseconds": @(WBExplicitLastWarpMilliseconds),
            @"captureScale": @(WBExplicitLastScale),
            @"sourcePixelWidth": @(WBExplicitLastSourceWidth),
            @"sourcePixelHeight": @(WBExplicitLastSourceHeight),
            @"outputPixelWidth": @(WBExplicitLastOutputWidth),
            @"outputPixelHeight": @(WBExplicitLastOutputHeight),
            @"samplingMode": @"window-region-ciwarp-rounded-sdf",
            @"updatedAt": NSDate.date
        };
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [WBDiagnostics updateStyling:@{@"explicitRefractionRuntime": runtime} error:nil];
    });
}

static UIView *WBExplicitMessageCellForView(UIView *view) {
    Class cellClass = NSClassFromString(@"CommonMessageCellView");
    UIView *candidate = view;
    while (candidate && candidate.window) {
        if (cellClass && [candidate isKindOfClass:cellClass]) {
            return candidate;
        }
        candidate = candidate.superview;
    }
    return nil;
}

@interface WBExplicitRefractionRenderer ()
@property (nonatomic, weak) UIView *targetView;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, assign) CGRect requestedBounds;
@property (nonatomic, assign) CGRect lastCapturedFrame;
@property (nonatomic, assign) BOOL captureScheduled;
@property (nonatomic, assign) NSUInteger requestGeneration;
@end

@implementation WBExplicitRefractionRenderer

+ (BOOL)isAvailable {
    @synchronized(self) {
        if (!WBExplicitCapabilityProbed) {
            WBExplicitCapabilityProbed = YES;
            @try {
                WBExplicitCapabilityAvailable = WBExplicitWarpKernel() != nil && WBExplicitContext() != nil;
                WBExplicitProbeReason = WBExplicitCapabilityAvailable ? @"available" : @"ci-warp-kernel-unavailable";
            } @catch (__unused NSException *exception) {
                WBExplicitCapabilityAvailable = NO;
                WBExplicitProbeReason = @"ci-capability-probe-exception";
            }
        }
        return WBExplicitCapabilityAvailable;
    }
}

+ (NSDictionary<NSString *,id> *)capabilitySnapshot {
    BOOL available = [self isAvailable];
    @synchronized(self) {
        return @{
            @"available": @(available),
            @"capabilityProbed": @(WBExplicitCapabilityProbed),
            @"probeReason": WBExplicitProbeReason,
            @"applicationSucceeded": @(WBExplicitCaptureCount > 0),
            @"captureCount": @(WBExplicitCaptureCount),
            @"failureCount": @(WBExplicitFailureCount),
            @"lastFailure": WBExplicitLastFailure,
            @"samplingMode": @"window-region-ciwarp-rounded-sdf"
        };
    }
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _imageView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _imageView.userInteractionEnabled = NO;
        _imageView.backgroundColor = UIColor.clearColor;
        _imageView.contentMode = UIViewContentModeScaleToFill;
        _lastCapturedFrame = CGRectNull;
    }
    return self;
}

- (void)recordFailure:(NSString *)reason {
    @synchronized(WBExplicitRefractionRenderer.class) {
        WBExplicitFailureCount++;
        WBExplicitLastFailure = reason;
    }
    WBExplicitWriteDiagnostics();
}

- (void)scheduleCapture {
    self.requestGeneration++;
    if (self.captureScheduled) {
        return;
    }
    self.captureScheduled = YES;
    NSUInteger scheduledGeneration = self.requestGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.06 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        typeof(self) self = weakSelf;
        if (!self) {
            return;
        }
        self.captureScheduled = NO;
        if (scheduledGeneration != self.requestGeneration) {
            if (self.targetView) {
                [self scheduleCapture];
            }
            return;
        }
        [self captureAndWarp];
    });
}

- (void)captureAndWarp {
    UIView *view = self.targetView;
    UIWindow *window = view.window;
    CGRect bounds = self.requestedBounds;
    if (!view || !window || CGRectIsEmpty(bounds)) {
        return;
    }
    CGRect frameInWindow = [view convertRect:bounds toView:window];
    if (CGRectIsEmpty(frameInWindow) || !isfinite(CGRectGetMinX(frameInWindow)) || !isfinite(CGRectGetMinY(frameInWindow))) {
        [self recordFailure:@"invalid-window-frame"];
        return;
    }
    CGFloat scale = MIN(MAX(UIScreen.mainScreen.scale * 0.75, 1.0), 2.0);
    CGFloat padding = 24.0;
    CGRect captureRect = CGRectInset(frameInWindow, -padding, -padding);
    CGSize captureSize = captureRect.size;
    if (!isfinite(captureSize.width) || !isfinite(captureSize.height) || captureSize.width < 1.0 || captureSize.height < 1.0 || captureSize.width > 560.0 || captureSize.height > 1080.0 || captureSize.width * captureSize.height * scale * scale > 1600000.0) {
        [self recordFailure:@"capture-size-out-of-range"];
        return;
    }
    UIView *messageCell = WBExplicitMessageCellForView(view);
    if (!messageCell) {
        [self recordFailure:@"message-cell-unavailable"];
        return;
    }
    CFTimeInterval captureStarted = CACurrentMediaTime();
    UIGraphicsBeginImageContextWithOptions(captureSize, NO, scale);
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context) {
        UIGraphicsEndImageContext();
        [self recordFailure:@"capture-context-unavailable"];
        return;
    }
    CGContextTranslateCTM(context, -CGRectGetMinX(captureRect), -CGRectGetMinY(captureRect));
    float originalOpacity = messageCell.layer.opacity;
    BOOL captureFailed = NO;
    messageCell.layer.opacity = 0.0f;
    @try {
        [window.layer renderInContext:context];
    } @catch (__unused NSException *exception) {
        captureFailed = YES;
    } @finally {
        messageCell.layer.opacity = originalOpacity;
    }
    if (captureFailed) {
        UIGraphicsEndImageContext();
        [self recordFailure:@"window-region-capture-exception"];
        return;
    }
    UIImage *sourceImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    double captureMilliseconds = (CACurrentMediaTime() - captureStarted) * 1000.0;
    if (!sourceImage.CGImage) {
        [self recordFailure:@"window-region-capture-failed"];
        return;
    }
    CIImage *source = [CIImage imageWithCGImage:sourceImage.CGImage];
    CGFloat width = CGRectGetWidth(bounds) * scale;
    CGFloat height = CGRectGetHeight(bounds) * scale;
    CGFloat paddingPixels = padding * scale;
    CIVector *center = [CIVector vectorWithX:paddingPixels + width * 0.5 Y:paddingPixels + height * 0.5];
    CIVector *halfSize = [CIVector vectorWithX:width * 0.5 Y:height * 0.5];
    CGFloat radius = MIN(24.0 * scale, MIN(width, height) * 0.5);
    CFTimeInterval warpStarted = CACurrentMediaTime();
    CIImage *warped = nil;
    CGImageRef output = NULL;
    @try {
        warped = [WBExplicitWarpKernel() applyWithExtent:source.extent roiCallback:^CGRect(__unused int index, CGRect rect) {
            return CGRectInset(rect, -24.0 * scale, -24.0 * scale);
        } inputImage:source arguments:@[center, halfSize, @(radius), @(14.0 * scale), @(18.0 * scale)]];
        CGRect outputRect = CGRectMake(paddingPixels, paddingPixels, width, height);
        output = warped ? [WBExplicitContext() createCGImage:warped fromRect:outputRect] : NULL;
    } @catch (__unused NSException *exception) {
        [self recordFailure:@"ci-warp-exception"];
        return;
    }
    double warpMilliseconds = (CACurrentMediaTime() - warpStarted) * 1000.0;
    if (!output) {
        [self recordFailure:@"ci-warp-output-failed"];
        return;
    }
    UIImage *image = [UIImage imageWithCGImage:output scale:scale orientation:UIImageOrientationUp];
    size_t outputWidth = CGImageGetWidth(output);
    size_t outputHeight = CGImageGetHeight(output);
    CGImageRelease(output);
    self.imageView.image = image;
    self.imageView.frame = bounds;
    self.lastCapturedFrame = frameInWindow;
    @synchronized(WBExplicitRefractionRenderer.class) {
        WBExplicitCaptureCount++;
        WBExplicitLastFailure = @"none";
        WBExplicitLastCaptureMilliseconds = captureMilliseconds;
        WBExplicitLastWarpMilliseconds = warpMilliseconds;
        WBExplicitLastScale = scale;
        WBExplicitLastSourceWidth = CGImageGetWidth(sourceImage.CGImage);
        WBExplicitLastSourceHeight = CGImageGetHeight(sourceImage.CGImage);
        WBExplicitLastOutputWidth = outputWidth;
        WBExplicitLastOutputHeight = outputHeight;
    }
    WBExplicitWriteDiagnostics();
}

- (WBExplicitRefractionResult)applyToView:(UIView *)view path:(UIBezierPath *)path bounds:(CGRect)bounds {
    if (!NSThread.isMainThread || ![WBExplicitRefractionRenderer isAvailable] || !view || !path || CGRectIsEmpty(bounds)) {
        return WBExplicitRefractionResultFailed;
    }
    self.targetView = view;
    self.requestedBounds = bounds;
    if (self.imageView.superview != view) {
        [self.imageView removeFromSuperview];
        [view insertSubview:self.imageView atIndex:0];
    }
    self.imageView.frame = bounds;
    CGRect currentFrame = view.window ? [view convertRect:bounds toView:view.window] : CGRectNull;
    if (!CGRectEqualToRect(currentFrame, self.lastCapturedFrame)) {
        [self scheduleCapture];
    }
    return self.imageView.image ? WBExplicitRefractionResultApplied : WBExplicitRefractionResultPending;
}

- (void)reset {
    self.requestGeneration++;
    self.targetView = nil;
    self.imageView.image = nil;
    [self.imageView removeFromSuperview];
    self.lastCapturedFrame = CGRectNull;
}

@end
