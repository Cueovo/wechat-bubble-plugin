#import "WBRealtimeGlassRenderer.h"
#import "WBBubbleThemeProvider.h"
#import "../Discovery/WBDiagnostics.h"
#import <CoreVideo/CoreVideo.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import <simd/simd.h>
#import <math.h>

static BOOL WBRealtimeCapabilityProbed;
static BOOL WBRealtimeCapabilityAvailable;
static NSString *WBRealtimeProbeReason = @"not-probed";
static NSString *WBRealtimeLastFailure = @"none";
static NSUInteger WBRealtimeCaptureCount;
static NSUInteger WBRealtimeFrameCount;
static NSUInteger WBRealtimeDroppedFrameCount;
static NSUInteger WBRealtimeFailureCount;
static double WBRealtimeLastCaptureMilliseconds;
static double WBRealtimeLastEncodeMilliseconds;
static CGFloat WBRealtimeLastCaptureScale;
static NSUInteger WBRealtimeLastPixelWidth;
static NSUInteger WBRealtimeLastPixelHeight;
static NSUInteger WBRealtimeBackdropReuseCount;
static BOOL WBRealtimeTextureYFlipped;
static BOOL WBRealtimeOrientationCalibrated;
static BOOL WBRealtimeOrientationFallbackUsed;
static NSUInteger WBRealtimeRedMarkerPixels;
static NSUInteger WBRealtimeGreenMarkerPixels;
static double WBRealtimeRedMarkerRow;
static double WBRealtimeGreenMarkerRow;
static NSArray<NSDictionary *> *WBRealtimeLastSurfaceFrames = @[];
static NSString *WBRealtimeCaptureSourceClass = @"window";
static NSString *WBRealtimeCaptureSourceFrame = @"unknown";
static NSString *WBRealtimeCapturePolicy = @"isolated-wallpaper-capture-once-live-window-uv";

static id<MTLDevice> WBRealtimeDevice;
static id<MTLRenderPipelineState> WBRealtimePipeline;

static NSString *WBRealtimeShaderSource(void) {
    return @"#include <metal_stdlib>\n"
    @"using namespace metal;\n"
    @"struct VertexOut { float4 position [[position]]; float2 uv; };\n"
    @"struct GlassUniforms { float2 windowSize; float2 glassOrigin; float2 glassSize; float cornerRadius; float edgeWidth; float refraction; float dispersion; float zoom; float tint; float dark; float time; float textureYFlip; };\n"
    @"vertex VertexOut wbGlassVertex(uint id [[vertex_id]]) {\n"
    @"float2 positions[4] = {float2(-1,-1),float2(1,-1),float2(-1,1),float2(1,1)};\n"
    @"float2 uvs[4] = {float2(0,1),float2(1,1),float2(0,0),float2(1,0)};\n"
    @"VertexOut out; out.position=float4(positions[id],0,1); out.uv=uvs[id]; return out; }\n"
    @"float wbRoundedBox(float2 p,float2 halfSize,float radius) { float2 q=abs(p)-halfSize+radius; return min(max(q.x,q.y),0.0)+length(max(q,0.0))-radius; }\n"
    @"fragment float4 wbGlassFragment(VertexOut in [[stage_in]], texture2d<float> backdrop [[texture(0)]], constant GlassUniforms &u [[buffer(0)]]) {\n"
    @"constexpr sampler s(coord::normalized,address::clamp_to_edge,filter::linear);\n"
    @"float2 local=in.uv*u.glassSize; float2 halfSize=u.glassSize*0.5; float2 p=local-halfSize;\n"
    @"float radius=min(u.cornerRadius,min(halfSize.x,halfSize.y)); float d=wbRoundedBox(p,halfSize,radius);\n"
    @"float dx=wbRoundedBox(p+float2(0.75,0),halfSize,radius)-wbRoundedBox(p-float2(0.75,0),halfSize,radius);\n"
    @"float dy=wbRoundedBox(p+float2(0,0.75),halfSize,radius)-wbRoundedBox(p-float2(0,0.75),halfSize,radius);\n"
    @"float2 gradient=float2(dx,dy); float gradientLength=length(gradient); float2 normal=gradientLength>0.0001?gradient/gradientLength:float2(0.0); float depth=max(-d,0.0);\n"
    @"float edge=1.0-smoothstep(0.0,max(u.edgeWidth,1.0),depth); edge=edge*edge*(3.0-2.0*edge);\n"
    @"float2 normalized=p/max(halfSize,float2(1.0)); float center=clamp(1.0-dot(normalized,normalized),0.0,1.0);\n"
    @"float pulse=0.96+0.04*sin(u.time*1.35+normalized.y*2.4);\n"
    @"float2 lensOffset=normal*u.refraction*edge*pulse-normalized*center*u.zoom;\n"
    @"float2 base=(u.glassOrigin+local+lensOffset)/u.windowSize; float2 chroma=normal*u.dispersion*edge/u.windowSize; if(u.textureYFlip>0.5){base.y=1.0-base.y;chroma.y=-chroma.y;}\n"
    @"float3 color; color.r=backdrop.sample(s,clamp(base+chroma,float2(0.001),float2(0.999))).r; color.g=backdrop.sample(s,clamp(base,float2(0.001),float2(0.999))).g; color.b=backdrop.sample(s,clamp(base-chroma,float2(0.001),float2(0.999))).b;\n"
    @"float2 texel=1.0/(u.windowSize*1.15); float3 soft=backdrop.sample(s,clamp(base+float2(texel.x,0),float2(0.001),float2(0.999))).rgb+backdrop.sample(s,clamp(base-float2(texel.x,0),float2(0.001),float2(0.999))).rgb+backdrop.sample(s,clamp(base+float2(0,texel.y),float2(0.001),float2(0.999))).rgb+backdrop.sample(s,clamp(base-float2(0,texel.y),float2(0.001),float2(0.999))).rgb;\n"
    @"color=mix(color,soft*0.25,0.16); float lum=dot(color,float3(0.2126,0.7152,0.0722));\n"
    @"float3 tintTarget=u.dark>0.5?float3(0.10,0.13,0.17):float3(0.96,0.98,1.0); color=mix(color,tintTarget,u.tint*(u.dark>0.5?0.20:0.12));\n"
    @"float2 light=normalize(float2(-0.72,-0.69)); float facing=clamp(dot(normal,light)*0.5+0.5,0.0,1.0); float rim=edge*pow(facing,2.2); float opposite=edge*pow(1.0-facing,3.0);\n"
    @"color+=rim*(u.dark>0.5?0.34:0.46); color-=opposite*(0.08+0.08*(1.0-lum)); float inner=1.0-smoothstep(0.0,4.0,depth); color+=inner*0.06;\n"
    @"return float4(saturate(color),0.985); }\n";
}

static void WBRealtimeProbe(void) {
    @synchronized(WBRealtimeGlassRenderer.class) {
        if (WBRealtimeCapabilityProbed) {
            return;
        }
        WBRealtimeCapabilityProbed = YES;
        WBRealtimeDevice = MTLCreateSystemDefaultDevice();
        if (!WBRealtimeDevice) {
            WBRealtimeProbeReason = @"metal-device-unavailable";
            return;
        }
        NSError *libraryError = nil;
        id<MTLLibrary> library = [WBRealtimeDevice newLibraryWithSource:WBRealtimeShaderSource() options:nil error:&libraryError];
        if (!library) {
            WBRealtimeProbeReason = [NSString stringWithFormat:@"shader-library-failed:%@", libraryError.localizedDescription ?: @"unknown"];
            return;
        }
        id<MTLFunction> vertex = [library newFunctionWithName:@"wbGlassVertex"];
        id<MTLFunction> fragment = [library newFunctionWithName:@"wbGlassFragment"];
        if (!vertex || !fragment) {
            WBRealtimeProbeReason = @"shader-functions-unavailable";
            return;
        }
        MTLRenderPipelineDescriptor *descriptor = [MTLRenderPipelineDescriptor new];
        descriptor.vertexFunction = vertex;
        descriptor.fragmentFunction = fragment;
        descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
        descriptor.colorAttachments[0].blendingEnabled = YES;
        descriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
        descriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        NSError *pipelineError = nil;
        WBRealtimePipeline = [WBRealtimeDevice newRenderPipelineStateWithDescriptor:descriptor error:&pipelineError];
        if (!WBRealtimePipeline) {
            WBRealtimeProbeReason = [NSString stringWithFormat:@"pipeline-failed:%@", pipelineError.localizedDescription ?: @"unknown"];
            return;
        }
        WBRealtimeCapabilityAvailable = YES;
        WBRealtimeProbeReason = @"available";
    }
}

static UIView *WBRealtimeMessageCellForView(UIView *view) {
    Class cellClass = NSClassFromString(@"CommonMessageCellView");
    UIView *candidate = view;
    while (candidate) {
        if (cellClass && [candidate isKindOfClass:cellClass]) {
            return candidate;
        }
        candidate = candidate.superview;
    }
    return nil;
}

static UIScrollView *WBRealtimeScrollContainerForView(UIView *view) {
    UIView *candidate = view;
    while (candidate) {
        if ([candidate isKindOfClass:UIScrollView.class]) {
            return (UIScrollView *)candidate;
        }
        candidate = candidate.superview;
    }
    return nil;
}

static BOOL WBRealtimeViewIsInsideMessageCell(UIView *view) {
    UIView *candidate = view;
    while (candidate) {
        if ([NSStringFromClass(candidate.class) containsString:@"CommonMessageCellView"]) {
            return YES;
        }
        candidate = candidate.superview;
    }
    return NO;
}

static void WBRealtimeFindBackdropImageView(UIView *root, UIWindow *window, UIView **bestView, CGFloat *bestScore) {
    if (!root || root.hidden || root.alpha < 0.01) {
        return;
    }
    if ([root isKindOfClass:UIImageView.class] && !WBRealtimeViewIsInsideMessageCell(root)) {
        UIImageView *imageView = (UIImageView *)root;
        CGRect frame = [root convertRect:root.bounds toView:window];
        CGRect intersection = CGRectIntersection(frame, window.bounds);
        CGFloat windowArea = CGRectGetWidth(window.bounds) * CGRectGetHeight(window.bounds);
        CGFloat coverage = !CGRectIsNull(intersection) && windowArea > 0.0 ? CGRectGetWidth(intersection) * CGRectGetHeight(intersection) / windowArea : 0.0;
        BOOL hasImageContent = imageView.image != nil || imageView.layer.contents != nil;
        if (hasImageContent && coverage >= 0.45 && CGRectGetWidth(intersection) >= CGRectGetWidth(window.bounds) * 0.9 && CGRectGetHeight(intersection) >= CGRectGetHeight(window.bounds) * 0.45) {
            NSString *className = NSStringFromClass(root.class).lowercaseString;
            CGFloat score = coverage + (([className containsString:@"background"] || [className containsString:@"wallpaper"]) ? 0.15 : 0.0);
            if (score > *bestScore) {
                *bestView = root;
                *bestScore = score;
            }
        }
    }
    for (UIView *subview in root.subviews) {
        WBRealtimeFindBackdropImageView(subview, window, bestView, bestScore);
    }
}

static UIView *WBRealtimeBackdropImageView(UIWindow *window) {
    UIView *bestView = nil;
    CGFloat bestScore = 0.0;
    WBRealtimeFindBackdropImageView(window, window, &bestView, &bestScore);
    return bestView;
}

typedef struct {
    vector_float2 windowSize;
    vector_float2 glassOrigin;
    vector_float2 glassSize;
    float cornerRadius;
    float edgeWidth;
    float refraction;
    float dispersion;
    float zoom;
    float tint;
    float dark;
    float time;
    float textureYFlip;
} WBRealtimeUniforms;

@class WBRealtimeGlassManager;

@interface WBRealtimeMetalView : UIView
@end

@implementation WBRealtimeMetalView
+ (Class)layerClass {
    return CAMetalLayer.class;
}
@end

@interface WBRealtimeGlassRenderer ()
@property (nonatomic, weak) UIView *targetView;
@property (nonatomic, strong) WBRealtimeMetalView *metalView;
@property (nonatomic, strong) CAShapeLayer *shapeMask;
@property (nonatomic, weak) WBRealtimeGlassManager *manager;
@property (nonatomic, assign) CGRect requestedBounds;
@property (nonatomic, assign) BOOL hasRenderedFrame;
@end

@interface WBRealtimeGlassManager : NSObject {
    CVMetalTextureCacheRef _textureCache;
    CVPixelBufferRef _pixelBuffer;
    CVMetalTextureRef _cvTexture;
    size_t _pixelWidth;
    size_t _pixelHeight;
    CGFloat _captureScale;
    BOOL _backdropReady;
    BOOL _captureDirty;
    BOOL _orientationCalibrated;
    BOOL _textureYFlipped;
    BOOL _orientationFallbackUsed;
    CGRect _capturedWindowBounds;
    CGFloat _capturedScreenScale;
    CGAffineTransform _capturedWindowTransform;
    __weak UIScreen *_capturedScreen;
    CFTimeInterval _lastRegistrationTime;
}
@property (nonatomic, weak) UIWindow *window;
@property (nonatomic, weak) UIScrollView *contentScrollView;
@property (nonatomic, strong) NSHashTable<WBRealtimeGlassRenderer *> *renderers;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, strong) dispatch_semaphore_t frameSemaphore;
+ (instancetype)managerForWindow:(UIWindow *)window;
- (void)addRenderer:(WBRealtimeGlassRenderer *)renderer;
- (void)removeRenderer:(WBRealtimeGlassRenderer *)renderer;
@end

static void WBRealtimeWriteDiagnostics(NSUInteger activeCount) {
    NSDictionary *runtime;
    @synchronized(WBRealtimeGlassRenderer.class) {
        runtime = @{
            @"applicationSucceeded": @(WBRealtimeFrameCount > 0),
            @"activeSurfaceCount": @(activeCount),
            @"captureCount": @(WBRealtimeCaptureCount),
            @"renderedFrameCount": @(WBRealtimeFrameCount),
            @"droppedFrameCount": @(WBRealtimeDroppedFrameCount),
            @"failureCount": @(WBRealtimeFailureCount),
            @"lastFailure": WBRealtimeLastFailure,
            @"captureMilliseconds": @(WBRealtimeLastCaptureMilliseconds),
            @"encodeMilliseconds": @(WBRealtimeLastEncodeMilliseconds),
            @"captureScale": @(WBRealtimeLastCaptureScale),
            @"capturePixelWidth": @(WBRealtimeLastPixelWidth),
            @"capturePixelHeight": @(WBRealtimeLastPixelHeight),
            @"backdropReuseCount": @(WBRealtimeBackdropReuseCount),
            @"textureYFlipped": @(WBRealtimeTextureYFlipped),
            @"orientationCalibrated": @(WBRealtimeOrientationCalibrated),
            @"orientationFallbackUsed": @(WBRealtimeOrientationFallbackUsed),
            @"redMarkerPixels": @(WBRealtimeRedMarkerPixels),
            @"greenMarkerPixels": @(WBRealtimeGreenMarkerPixels),
            @"redMarkerRow": @(WBRealtimeRedMarkerRow),
            @"greenMarkerRow": @(WBRealtimeGreenMarkerRow),
            @"lastSurfaceFrames": WBRealtimeLastSurfaceFrames,
            @"captureSourceClass": WBRealtimeCaptureSourceClass,
            @"captureSourceFrame": WBRealtimeCaptureSourceFrame,
            @"capturePolicy": WBRealtimeCapturePolicy,
            @"samplingMode": @"isolated-wallpaper-or-window-backdrop-live-metal-uv-sdf",
            @"updatedAt": NSDate.date
        };
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [WBDiagnostics updateStyling:@{@"realtimeMetalRuntime": runtime} error:nil];
    });
}

@implementation WBRealtimeGlassManager

+ (instancetype)managerForWindow:(UIWindow *)window {
    static NSMapTable<UIWindow *, WBRealtimeGlassManager *> *managers;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        managers = [NSMapTable weakToStrongObjectsMapTable];
    });
    @synchronized(managers) {
        WBRealtimeGlassManager *manager = [managers objectForKey:window];
        if (!manager) {
            manager = [WBRealtimeGlassManager new];
            manager.window = window;
            [managers setObject:manager forKey:window];
        }
        return manager;
    }
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _renderers = [NSHashTable weakObjectsHashTable];
        _commandQueue = [WBRealtimeDevice newCommandQueue];
        _frameSemaphore = dispatch_semaphore_create(1);
        _captureDirty = YES;
        _lastRegistrationTime = CACurrentMediaTime();
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, WBRealtimeDevice, nil, &_textureCache);
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.displayLink invalidate];
    if (_cvTexture) {
        CFRelease(_cvTexture);
    }
    if (_pixelBuffer) {
        CFRelease(_pixelBuffer);
    }
    if (_textureCache) {
        CFRelease(_textureCache);
    }
}

- (void)applicationDidBecomeActive:(__unused NSNotification *)notification {
    _backdropReady = NO;
    _captureDirty = YES;
    _orientationCalibrated = NO;
    _orientationFallbackUsed = NO;
    _lastRegistrationTime = CACurrentMediaTime();
}

- (void)addRenderer:(WBRealtimeGlassRenderer *)renderer {
    BOOL firstRenderer = self.renderers.allObjects.count == 0;
    UIScrollView *scrollView = WBRealtimeScrollContainerForView(renderer.targetView);
    if (self.contentScrollView && scrollView && self.contentScrollView != scrollView) {
        _backdropReady = NO;
        _captureDirty = YES;
        _orientationCalibrated = NO;
        _orientationFallbackUsed = NO;
    }
    if (scrollView) {
        self.contentScrollView = scrollView;
    }
    [self.renderers addObject:renderer];
    _lastRegistrationTime = CACurrentMediaTime();
    if (firstRenderer || !_backdropReady) {
        _captureDirty = YES;
    }
    if (!self.displayLink) {
        self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(displayLinkDidFire:)];
        self.displayLink.preferredFramesPerSecond = MIN(UIScreen.mainScreen.maximumFramesPerSecond, 60);
        [self.displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
}

- (void)removeRenderer:(WBRealtimeGlassRenderer *)renderer {
    [self.renderers removeObject:renderer];
    if (self.renderers.allObjects.count == 0) {
        [self.displayLink invalidate];
        self.displayLink = nil;
        _backdropReady = NO;
        _captureDirty = YES;
        _capturedWindowBounds = CGRectZero;
        _capturedScreenScale = 0.0;
        _capturedWindowTransform = CGAffineTransformIdentity;
        _capturedScreen = nil;
        self.contentScrollView = nil;
    }
}

- (BOOL)prepareCaptureBuffer {
    UIWindow *window = self.window;
    CGSize size = window.bounds.size;
    if (!window || size.width < 1.0 || size.height < 1.0 || !isfinite(size.width) || !isfinite(size.height)) {
        return NO;
    }
    CGFloat screenScale = window.screen.scale ?: UIScreen.mainScreen.scale;
    CGFloat scale = MIN(MAX(screenScale * 0.42, 1.0), 1.25);
    CGFloat maximumScale = sqrt(2500000.0 / MAX(size.width * size.height, 1.0));
    scale = MIN(scale, maximumScale);
    size_t width = (size_t)MAX(1.0, ceil(size.width * scale));
    size_t height = (size_t)MAX(1.0, ceil(size.height * scale));
    if (_pixelBuffer && _cvTexture && width == _pixelWidth && height == _pixelHeight) {
        _captureScale = scale;
        return YES;
    }
    if (_cvTexture) {
        CFRelease(_cvTexture);
        _cvTexture = NULL;
    }
    if (_pixelBuffer) {
        CFRelease(_pixelBuffer);
        _pixelBuffer = NULL;
    }
    NSDictionary *attributes = @{
        (__bridge NSString *)kCVPixelBufferMetalCompatibilityKey: @YES,
        (__bridge NSString *)kCVPixelBufferCGImageCompatibilityKey: @YES,
        (__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{}
    };
    CVReturn bufferStatus = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)attributes, &_pixelBuffer);
    if (bufferStatus != kCVReturnSuccess || !_pixelBuffer) {
        return NO;
    }
    CVReturn textureStatus = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, _textureCache, _pixelBuffer, nil, MTLPixelFormatBGRA8Unorm, width, height, 0, &_cvTexture);
    if (textureStatus != kCVReturnSuccess || !_cvTexture) {
        CFRelease(_pixelBuffer);
        _pixelBuffer = NULL;
        _pixelWidth = 0;
        _pixelHeight = 0;
        return NO;
    }
    _pixelWidth = width;
    _pixelHeight = height;
    _captureScale = scale;
    return YES;
}

- (BOOL)captureBackdrop {
    if (![self prepareCaptureBuffer]) {
        return NO;
    }
    UIWindow *window = self.window;
    NSMutableArray<CALayer *> *hiddenLayers = [NSMutableArray array];
    NSMutableArray<NSNumber *> *savedOpacities = [NSMutableArray array];
    NSHashTable<UIView *> *cells = [NSHashTable weakObjectsHashTable];
    for (WBRealtimeGlassRenderer *renderer in self.renderers.allObjects) {
        UIView *cell = WBRealtimeMessageCellForView(renderer.targetView);
        if (cell) {
            [cells addObject:cell];
        }
    }
    CVReturn lockStatus = CVPixelBufferLockBaseAddress(_pixelBuffer, 0);
    if (lockStatus != kCVReturnSuccess) {
        return NO;
    }
    void *baseAddress = CVPixelBufferGetBaseAddress(_pixelBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(_pixelBuffer);
    if (!baseAddress || bytesPerRow < _pixelWidth * 4) {
        CVPixelBufferUnlockBaseAddress(_pixelBuffer, 0);
        return NO;
    }
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(baseAddress, _pixelWidth, _pixelHeight, 8, bytesPerRow, colorSpace, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(colorSpace);
    if (!context) {
        CVPixelBufferUnlockBaseAddress(_pixelBuffer, 0);
        return NO;
    }
    CGContextClearRect(context, CGRectMake(0, 0, _pixelWidth, _pixelHeight));
    CGContextScaleCTM(context, _captureScale, _captureScale);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    void (^hideLayer)(CALayer *) = ^(CALayer *layer) {
        if (!layer || [hiddenLayers containsObject:layer]) {
            return;
        }
        [hiddenLayers addObject:layer];
        [savedOpacities addObject:@(layer.opacity)];
        layer.opacity = 0.0f;
    };
    for (WBRealtimeGlassRenderer *renderer in renderers) {
        hideLayer(renderer.targetView.layer);
    }
    for (UIView *cell in cells.allObjects) {
        hideLayer(cell.layer);
    }
    UIView *backdropSource = WBRealtimeBackdropImageView(window);
    if (backdropSource) {
        UIView *branch = backdropSource;
        while (branch.superview) {
            UIView *parent = branch.superview;
            for (UIView *sibling in parent.subviews) {
                if (sibling != branch) {
                    hideLayer(sibling.layer);
                }
            }
            branch = parent;
        }
    }
    @synchronized(WBRealtimeGlassRenderer.class) {
        WBRealtimeCaptureSourceClass = backdropSource ? NSStringFromClass(backdropSource.class) : @"window";
        WBRealtimeCaptureSourceFrame = backdropSource ? NSStringFromCGRect([backdropSource convertRect:backdropSource.bounds toView:window]) : NSStringFromCGRect(window.bounds);
    }
    CALayer *topMarker = nil;
    CALayer *bottomMarker = nil;
    if (!_orientationCalibrated) {
        CGRect windowBounds = window.bounds;
        topMarker = [CALayer layer];
        topMarker.frame = CGRectMake(CGRectGetMinX(windowBounds) + 2.0, CGRectGetMinY(windowBounds) + 2.0, 12.0, 12.0);
        topMarker.backgroundColor = UIColor.redColor.CGColor;
        bottomMarker = [CALayer layer];
        bottomMarker.frame = CGRectMake(CGRectGetMinX(windowBounds) + 2.0, CGRectGetMaxY(windowBounds) - 14.0, 12.0, 12.0);
        bottomMarker.backgroundColor = UIColor.greenColor.CGColor;
        [window.layer addSublayer:topMarker];
        [window.layer addSublayer:bottomMarker];
        [window.layer layoutIfNeeded];
    }
    BOOL succeeded = YES;
    @try {
        [window.layer renderInContext:context];
        CGContextFlush(context);
        if (topMarker && _pixelWidth > 16 && _pixelHeight > 16) {
            uint8_t *bytes = baseAddress;
            size_t scanWidth = MIN(_pixelWidth, (size_t)ceil(20.0 * _captureScale));
            size_t scanBandHeight = MIN(_pixelHeight / 2, (size_t)ceil(24.0 * _captureScale));
            NSUInteger redCount = 0;
            NSUInteger greenCount = 0;
            uint64_t redRowTotal = 0;
            uint64_t greenRowTotal = 0;
            for (size_t row = 0; row < _pixelHeight; row++) {
                if (row >= scanBandHeight && row < _pixelHeight - scanBandHeight) {
                    continue;
                }
                uint8_t *pixel = bytes + row * bytesPerRow;
                for (size_t column = 0; column < scanWidth; column++, pixel += 4) {
                    BOOL isRed = pixel[2] > 180 && pixel[2] > pixel[1] * 2 && pixel[2] > pixel[0] * 2;
                    BOOL isGreen = pixel[1] > 100 && pixel[1] > pixel[2] * 2 && pixel[1] > pixel[0] * 2;
                    if (isRed) {
                        redCount++;
                        redRowTotal += row;
                    } else if (isGreen) {
                        greenCount++;
                        greenRowTotal += row;
                    }
                }
            }
            NSUInteger minimumMarkerPixels = MAX(16, (NSUInteger)floor(30.0 * _captureScale * _captureScale));
            double redRow = redCount > 0 ? (double)redRowTotal / redCount : -1.0;
            double greenRow = greenCount > 0 ? (double)greenRowTotal / greenCount : -1.0;
            if (redCount >= minimumMarkerPixels && greenCount >= minimumMarkerPixels) {
                _textureYFlipped = redRow > greenRow;
                _orientationCalibrated = YES;
                _orientationFallbackUsed = NO;
            } else {
                _textureYFlipped = NO;
                _orientationFallbackUsed = YES;
            }
            @synchronized(WBRealtimeGlassRenderer.class) {
                WBRealtimeTextureYFlipped = _textureYFlipped;
                WBRealtimeOrientationCalibrated = _orientationCalibrated;
                WBRealtimeOrientationFallbackUsed = _orientationFallbackUsed;
                WBRealtimeRedMarkerPixels = redCount;
                WBRealtimeGreenMarkerPixels = greenCount;
                WBRealtimeRedMarkerRow = redRow;
                WBRealtimeGreenMarkerRow = greenRow;
            }
        }
    } @catch (__unused NSException *exception) {
        succeeded = NO;
    } @finally {
        [topMarker removeFromSuperlayer];
        [bottomMarker removeFromSuperlayer];
        [hiddenLayers enumerateObjectsUsingBlock:^(CALayer *layer, NSUInteger index, __unused BOOL *stop) {
            layer.opacity = savedOpacities[index].floatValue;
        }];
        [CATransaction commit];
        CGContextRelease(context);
        CVPixelBufferUnlockBaseAddress(_pixelBuffer, 0);
    }
    if (succeeded) {
        _capturedWindowBounds = window.bounds;
        _capturedScreenScale = window.screen.scale;
        _capturedWindowTransform = window.transform;
        _capturedScreen = window.screen;
    }
    return succeeded;
}

- (void)displayLinkDidFire:(__unused CADisplayLink *)displayLink {
    NSArray<WBRealtimeGlassRenderer *> *registeredRenderers = self.renderers.allObjects;
    if (registeredRenderers.count == 0 || !self.window || self.window.hidden) {
        return;
    }
    NSMutableArray<WBRealtimeGlassRenderer *> *visibleRenderers = [NSMutableArray arrayWithCapacity:registeredRenderers.count];
    for (WBRealtimeGlassRenderer *renderer in registeredRenderers) {
        UIView *target = renderer.targetView;
        if (target && target.window == self.window && !target.hidden && target.alpha >= 0.01 && !CGRectIsEmpty(renderer.requestedBounds)) {
            CGRect frame = [target convertRect:renderer.requestedBounds toView:self.window];
            if (CGRectIntersectsRect(frame, self.window.bounds)) {
                [visibleRenderers addObject:renderer];
            }
        }
    }
    NSArray<WBRealtimeGlassRenderer *> *renderers = visibleRenderers;
    if (renderers.count == 0) {
        return;
    }
    CGFloat currentScreenScale = self.window.screen.scale;
    BOOL captureCoordinatesChanged = !CGRectEqualToRect(_capturedWindowBounds, self.window.bounds) || fabs(_capturedScreenScale - currentScreenScale) > 0.001 || !CGAffineTransformEqualToTransform(_capturedWindowTransform, self.window.transform) || _capturedScreen != self.window.screen;
    if (captureCoordinatesChanged) {
        if (_backdropReady) {
            _lastRegistrationTime = CACurrentMediaTime();
        }
        _captureDirty = YES;
        _backdropReady = NO;
        _orientationCalibrated = NO;
        _orientationFallbackUsed = NO;
    }
    if (dispatch_semaphore_wait(self.frameSemaphore, DISPATCH_TIME_NOW) != 0) {
        @synchronized(WBRealtimeGlassRenderer.class) {
            WBRealtimeDroppedFrameCount++;
        }
        return;
    }
    BOOL capturedThisFrame = NO;
    NSUInteger reuseCount = 0;
    double captureMilliseconds = WBRealtimeLastCaptureMilliseconds;
    if (!_backdropReady || _captureDirty) {
        if (CACurrentMediaTime() - _lastRegistrationTime < 0.05) {
            dispatch_semaphore_signal(self.frameSemaphore);
            return;
        }
        CFTimeInterval captureStarted = CACurrentMediaTime();
        if (![self captureBackdrop]) {
            dispatch_semaphore_signal(self.frameSemaphore);
            NSUInteger failureCount;
            @synchronized(WBRealtimeGlassRenderer.class) {
                failureCount = ++WBRealtimeFailureCount;
                WBRealtimeLastFailure = @"shared-window-capture-failed";
            }
            if (failureCount < 4 || failureCount % 120 == 0) {
                WBRealtimeWriteDiagnostics(renderers.count);
            }
            return;
        }
        captureMilliseconds = (CACurrentMediaTime() - captureStarted) * 1000.0;
        _backdropReady = YES;
        _captureDirty = NO;
        capturedThisFrame = YES;
    } else {
        @synchronized(WBRealtimeGlassRenderer.class) {
            reuseCount = ++WBRealtimeBackdropReuseCount;
        }
    }
    BOOL recordSurfaceFrames = capturedThisFrame || reuseCount % 120 == 0;
    NSMutableArray<NSDictionary *> *surfaceFrames = recordSurfaceFrames ? [NSMutableArray arrayWithCapacity:renderers.count] : nil;
    id<MTLTexture> backdrop = _cvTexture ? CVMetalTextureGetTexture(_cvTexture) : nil;
    id<MTLCommandBuffer> commandBuffer = backdrop ? [self.commandQueue commandBuffer] : nil;
    if (!commandBuffer) {
        dispatch_semaphore_signal(self.frameSemaphore);
        return;
    }
    CFTimeInterval encodeStarted = CACurrentMediaTime();
    __block NSUInteger encodedCount = 0;
    for (WBRealtimeGlassRenderer *renderer in renderers) {
        UIView *target = renderer.targetView;
        WBRealtimeMetalView *metalView = renderer.metalView;
        if (!target || !target.window || target.window != self.window || target.hidden || target.alpha < 0.01 || CGRectIsEmpty(renderer.requestedBounds)) {
            continue;
        }
        CGRect frameInWindow = [target convertRect:renderer.requestedBounds toView:self.window];
        if (!CGRectIntersectsRect(frameInWindow, self.window.bounds)) {
            continue;
        }
        CAMetalLayer *metalLayer = (CAMetalLayer *)metalView.layer;
        id<CAMetalDrawable> drawable = [metalLayer nextDrawable];
        if (!drawable) {
            continue;
        }
        MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
        pass.colorAttachments[0].texture = drawable.texture;
        pass.colorAttachments[0].loadAction = MTLLoadActionClear;
        pass.colorAttachments[0].storeAction = MTLStoreActionStore;
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0);
        id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:pass];
        if (!encoder) {
            continue;
        }
        CGRect windowBounds = self.window.bounds;
        CGFloat radius = MIN([WBBubbleThemeProvider cornerRadius], MIN(CGRectGetWidth(renderer.requestedBounds), CGRectGetHeight(renderer.requestedBounds)) * 0.5);
        WBRealtimeUniforms uniforms = {
            .windowSize = {(float)CGRectGetWidth(windowBounds), (float)CGRectGetHeight(windowBounds)},
            .glassOrigin = {(float)(CGRectGetMinX(frameInWindow) - CGRectGetMinX(windowBounds)), (float)(CGRectGetMinY(frameInWindow) - CGRectGetMinY(windowBounds))},
            .glassSize = {(float)CGRectGetWidth(frameInWindow), (float)CGRectGetHeight(frameInWindow)},
            .cornerRadius = (float)radius,
            .edgeWidth = 15.0f,
            .refraction = 13.0f,
            .dispersion = 1.6f,
            .zoom = 2.2f,
            .tint = 0.32f,
            .dark = target.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? 1.0f : 0.0f,
            .time = (float)fmod(CACurrentMediaTime(), 1000.0),
            .textureYFlip = _textureYFlipped ? 1.0f : 0.0f
        };
        [encoder setRenderPipelineState:WBRealtimePipeline];
        [encoder setFragmentTexture:backdrop atIndex:0];
        [encoder setFragmentBytes:&uniforms length:sizeof(uniforms) atIndex:0];
        [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
        [encoder endEncoding];
        [commandBuffer presentDrawable:drawable];
        BOOL firstFrame = !renderer.hasRenderedFrame;
        renderer.hasRenderedFrame = YES;
        if (firstFrame) {
            [target setNeedsLayout];
        }
        encodedCount++;
    }
    if (encodedCount == 0) {
        dispatch_semaphore_signal(self.frameSemaphore);
        return;
    }
    double encodeMilliseconds = (CACurrentMediaTime() - encodeStarted) * 1000.0;
    dispatch_semaphore_t semaphore = self.frameSemaphore;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
        if (buffer.status == MTLCommandBufferStatusError) {
            @synchronized(WBRealtimeGlassRenderer.class) {
                WBRealtimeFailureCount++;
                WBRealtimeLastFailure = [NSString stringWithFormat:@"metal-command-failed:%@", buffer.error.localizedDescription ?: @"unknown"];
            }
        }
        dispatch_semaphore_signal(semaphore);
    }];
    [commandBuffer commit];
    @synchronized(WBRealtimeGlassRenderer.class) {
        if (capturedThisFrame) {
            WBRealtimeCaptureCount++;
        }
        WBRealtimeFrameCount += encodedCount;
        WBRealtimeLastFailure = @"none";
        WBRealtimeLastCaptureMilliseconds = captureMilliseconds;
        WBRealtimeLastEncodeMilliseconds = encodeMilliseconds;
        WBRealtimeLastCaptureScale = _captureScale;
        WBRealtimeLastPixelWidth = _pixelWidth;
        WBRealtimeLastPixelHeight = _pixelHeight;
        if (surfaceFrames) {
            WBRealtimeLastSurfaceFrames = [surfaceFrames copy];
        }
    }
    if (capturedThisFrame || reuseCount % 120 == 0) {
        WBRealtimeWriteDiagnostics(renderers.count);
    }
}

@end

@implementation WBRealtimeGlassRenderer

+ (BOOL)isAvailable {
    WBRealtimeProbe();
    return WBRealtimeCapabilityAvailable;
}

+ (NSDictionary<NSString *,id> *)capabilitySnapshot {
    BOOL available = [self isAvailable];
    @synchronized(self) {
        return @{
            @"available": @(available),
            @"capabilityProbed": @(WBRealtimeCapabilityProbed),
            @"probeReason": WBRealtimeProbeReason,
            @"applicationSucceeded": @(WBRealtimeFrameCount > 0),
            @"captureCount": @(WBRealtimeCaptureCount),
            @"renderedFrameCount": @(WBRealtimeFrameCount),
            @"droppedFrameCount": @(WBRealtimeDroppedFrameCount),
            @"failureCount": @(WBRealtimeFailureCount),
            @"lastFailure": WBRealtimeLastFailure,
            @"backdropReuseCount": @(WBRealtimeBackdropReuseCount),
            @"textureYFlipped": @(WBRealtimeTextureYFlipped),
            @"orientationCalibrated": @(WBRealtimeOrientationCalibrated),
            @"orientationFallbackUsed": @(WBRealtimeOrientationFallbackUsed),
            @"redMarkerPixels": @(WBRealtimeRedMarkerPixels),
            @"greenMarkerPixels": @(WBRealtimeGreenMarkerPixels),
            @"redMarkerRow": @(WBRealtimeRedMarkerRow),
            @"greenMarkerRow": @(WBRealtimeGreenMarkerRow),
            @"lastSurfaceFrames": WBRealtimeLastSurfaceFrames,
            @"captureSourceClass": WBRealtimeCaptureSourceClass,
            @"captureSourceFrame": WBRealtimeCaptureSourceFrame,
            @"capturePolicy": WBRealtimeCapturePolicy,
            @"samplingMode": @"isolated-wallpaper-or-window-backdrop-live-metal-uv-sdf"
        };
    }
}

- (instancetype)init {
    self = [super init];
    if (self) {
        WBRealtimeProbe();
        _metalView = [WBRealtimeMetalView new];
        _metalView.userInteractionEnabled = NO;
        _metalView.backgroundColor = UIColor.clearColor;
        _metalView.opaque = NO;
        _shapeMask = [CAShapeLayer layer];
        _shapeMask.fillColor = UIColor.whiteColor.CGColor;
        _metalView.layer.mask = _shapeMask;
        CAMetalLayer *layer = (CAMetalLayer *)_metalView.layer;
        layer.device = WBRealtimeDevice;
        layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        layer.framebufferOnly = YES;
        layer.opaque = NO;
        layer.contentsScale = UIScreen.mainScreen.scale;
    }
    return self;
}

- (WBRealtimeGlassResult)applyToView:(UIView *)view path:(UIBezierPath *)path bounds:(CGRect)bounds {
    if (!NSThread.isMainThread || ![WBRealtimeGlassRenderer isAvailable] || !view || !path || !view.window || CGRectIsEmpty(bounds)) {
        return WBRealtimeGlassResultFailed;
    }
    WBRealtimeGlassManager *manager = [WBRealtimeGlassManager managerForWindow:view.window];
    if (self.manager != manager) {
        [self.manager removeRenderer:self];
        self.targetView = view;
        self.requestedBounds = bounds;
        self.manager = manager;
        [manager addRenderer:self];
        self.hasRenderedFrame = NO;
    } else {
        self.targetView = view;
        self.requestedBounds = bounds;
    }
    if (self.metalView.superview != view) {
        [self.metalView removeFromSuperview];
        NSUInteger index = MIN((NSUInteger)1, view.subviews.count);
        [view insertSubview:self.metalView atIndex:index];
    }
    self.metalView.frame = bounds;
    self.shapeMask.frame = self.metalView.bounds;
    self.shapeMask.path = path.CGPath;
    CAMetalLayer *layer = (CAMetalLayer *)self.metalView.layer;
    CGFloat scale = UIScreen.mainScreen.scale;
    layer.drawableSize = CGSizeMake(MAX(1.0, CGRectGetWidth(bounds) * scale), MAX(1.0, CGRectGetHeight(bounds) * scale));
    return self.hasRenderedFrame ? WBRealtimeGlassResultApplied : WBRealtimeGlassResultPending;
}

- (void)reset {
    [self.manager removeRenderer:self];
    self.manager = nil;
    self.targetView = nil;
    self.hasRenderedFrame = NO;
    [self.metalView removeFromSuperview];
}

@end
