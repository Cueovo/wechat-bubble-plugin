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

static id<MTLDevice> WBRealtimeDevice;
static id<MTLRenderPipelineState> WBRealtimePipeline;

static NSString *WBRealtimeShaderSource(void) {
    return @"#include <metal_stdlib>\n"
    @"using namespace metal;\n"
    @"struct VertexOut { float4 position [[position]]; float2 uv; };\n"
    @"struct GlassUniforms { float2 windowSize; float2 glassOrigin; float2 glassSize; float cornerRadius; float edgeWidth; float refraction; float dispersion; float zoom; float tint; float dark; float time; };\n"
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
    @"float2 base=(u.glassOrigin+local+lensOffset)/u.windowSize; float2 chroma=normal*u.dispersion*edge/u.windowSize;\n"
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
}
@property (nonatomic, weak) UIWindow *window;
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
            @"samplingMode": @"continuous-shared-window-capture-metal-sdf",
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
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, WBRealtimeDevice, nil, &_textureCache);
    }
    return self;
}

- (void)dealloc {
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

- (void)addRenderer:(WBRealtimeGlassRenderer *)renderer {
    [self.renderers addObject:renderer];
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
    }
}

- (BOOL)prepareCaptureBuffer {
    UIWindow *window = self.window;
    CGSize size = window.bounds.size;
    if (!window || size.width < 1.0 || size.height < 1.0 || !isfinite(size.width) || !isfinite(size.height)) {
        return NO;
    }
    CGFloat scale = MIN(MAX(UIScreen.mainScreen.scale * 0.42, 1.0), 1.25);
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
    for (UIView *cell in cells.allObjects) {
        [hiddenLayers addObject:cell.layer];
        [savedOpacities addObject:@(cell.layer.opacity)];
        cell.layer.opacity = 0.0f;
    }
    BOOL succeeded = YES;
    @try {
        [window.layer renderInContext:context];
    } @catch (__unused NSException *exception) {
        succeeded = NO;
    } @finally {
        [hiddenLayers enumerateObjectsUsingBlock:^(CALayer *layer, NSUInteger index, __unused BOOL *stop) {
            layer.opacity = savedOpacities[index].floatValue;
        }];
        [CATransaction commit];
        CGContextRelease(context);
        CVPixelBufferUnlockBaseAddress(_pixelBuffer, 0);
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
    if (dispatch_semaphore_wait(self.frameSemaphore, DISPATCH_TIME_NOW) != 0) {
        @synchronized(WBRealtimeGlassRenderer.class) {
            WBRealtimeDroppedFrameCount++;
        }
        return;
    }
    CFTimeInterval captureStarted = CACurrentMediaTime();
    if (![self captureBackdrop]) {
        dispatch_semaphore_signal(self.frameSemaphore);
        @synchronized(WBRealtimeGlassRenderer.class) {
            WBRealtimeFailureCount++;
            WBRealtimeLastFailure = @"shared-window-capture-failed";
        }
        if (WBRealtimeFailureCount < 4 || WBRealtimeFailureCount % 120 == 0) {
            WBRealtimeWriteDiagnostics(renderers.count);
        }
        return;
    }
    double captureMilliseconds = (CACurrentMediaTime() - captureStarted) * 1000.0;
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
        CGFloat radius = MIN([WBBubbleThemeProvider cornerRadius], MIN(CGRectGetWidth(renderer.requestedBounds), CGRectGetHeight(renderer.requestedBounds)) * 0.5);
        WBRealtimeUniforms uniforms = {
            .windowSize = {(float)CGRectGetWidth(self.window.bounds), (float)CGRectGetHeight(self.window.bounds)},
            .glassOrigin = {(float)CGRectGetMinX(frameInWindow), (float)CGRectGetMinY(frameInWindow)},
            .glassSize = {(float)CGRectGetWidth(frameInWindow), (float)CGRectGetHeight(frameInWindow)},
            .cornerRadius = (float)radius,
            .edgeWidth = 15.0f,
            .refraction = 13.0f,
            .dispersion = 1.6f,
            .zoom = 2.2f,
            .tint = 0.32f,
            .dark = target.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? 1.0f : 0.0f,
            .time = (float)fmod(CACurrentMediaTime(), 1000.0)
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
        WBRealtimeCaptureCount++;
        WBRealtimeFrameCount += encodedCount;
        WBRealtimeLastFailure = @"none";
        WBRealtimeLastCaptureMilliseconds = captureMilliseconds;
        WBRealtimeLastEncodeMilliseconds = encodeMilliseconds;
        WBRealtimeLastCaptureScale = _captureScale;
        WBRealtimeLastPixelWidth = _pixelWidth;
        WBRealtimeLastPixelHeight = _pixelHeight;
    }
    if (WBRealtimeCaptureCount == 1 || WBRealtimeCaptureCount % 120 == 0) {
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
            @"samplingMode": @"continuous-shared-window-capture-metal-sdf"
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
        self.manager = manager;
        [manager addRenderer:self];
        self.hasRenderedFrame = NO;
    }
    self.targetView = view;
    self.requestedBounds = bounds;
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
