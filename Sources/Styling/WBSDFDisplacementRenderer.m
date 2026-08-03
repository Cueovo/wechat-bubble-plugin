#import "WBSDFDisplacementRenderer.h"
#import "../Discovery/WBDiagnostics.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <math.h>

static BOOL WBSDFCapabilityProbed;
static BOOL WBSDFCapabilityAvailable;
static BOOL WBSDFDisabledForProcess;
static NSString *WBSDFProbeReason = @"not-probed";
static NSArray<NSString *> *WBSDFReportedInputKeys;
static NSString *WBSDFLastRuntimeFailure = @"none";
static NSUInteger WBSDFRuntimeFailureCount;
static BOOL WBSDFRuntimeApplicationSucceeded;
static BOOL WBSDFRuntimeSnapshotScheduled;
static NSUInteger WBSDFRuntimeSnapshotGeneration;
static NSUInteger WBSDFRuntimeSnapshotRetryCount;

static id WBSDFCreateFilter(NSString *type) {
    Class filterClass = NSClassFromString(@"CAFilter");
    SEL selector = NSSelectorFromString(@"filterWithType:");
    if (!filterClass || ![filterClass respondsToSelector:selector]) {
        return nil;
    }
    return ((id (*)(id, SEL, id))objc_msgSend)(filterClass, selector, type);
}

static NSArray<NSString *> *WBSDFInputKeys(id filter) {
    SEL selector = NSSelectorFromString(@"inputKeys");
    id keys = [filter respondsToSelector:selector] ? ((id (*)(id, SEL))objc_msgSend)(filter, selector) : nil;
    return [keys isKindOfClass:NSArray.class] ? keys : nil;
}

static void WBSDFProbeCapability(void) {
    @synchronized(WBSDFDisplacementRenderer.class) {
        if (WBSDFCapabilityProbed) {
            return;
        }
        WBSDFCapabilityProbed = YES;
        @try {
            if (!NSClassFromString(@"CABackdropLayer")) {
                WBSDFProbeReason = @"cabackdroplayer-unavailable";
                return;
            }
            id displacement = WBSDFCreateFilter(@"displacementMap");
            if (!displacement) {
                WBSDFProbeReason = @"displacement-filter-unavailable";
                return;
            }
            WBSDFReportedInputKeys = [WBSDFInputKeys(displacement) copy] ?: @[];
            WBSDFCapabilityAvailable = YES;
            WBSDFProbeReason = @"available";
        } @catch (__unused NSException *exception) {
            WBSDFProbeReason = @"capability-probe-exception";
        }
    }
}

static void WBSDFScheduleRuntimeSnapshot(void) {
    NSDictionary<NSString *, id> *runtime;
    NSUInteger scheduledGeneration;
    @synchronized(WBSDFDisplacementRenderer.class) {
        WBSDFRuntimeSnapshotGeneration++;
        if (WBSDFRuntimeSnapshotScheduled) {
            return;
        }
        WBSDFRuntimeSnapshotScheduled = YES;
        scheduledGeneration = WBSDFRuntimeSnapshotGeneration;
        runtime = @{
            @"applicationSucceeded": @(WBSDFRuntimeApplicationSucceeded),
            @"disabledForProcess": @(WBSDFDisabledForProcess),
            @"lastRuntimeFailure": WBSDFLastRuntimeFailure,
            @"runtimeFailureCount": @(WBSDFRuntimeFailureCount),
            @"updatedAt": NSDate.date
        };
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        BOOL updated = [WBDiagnostics updateStyling:@{@"sdfRuntime": runtime} error:nil];
        BOOL needsUpdate;
        BOOL shouldRetry;
        NSUInteger retryCount;
        @synchronized(WBSDFDisplacementRenderer.class) {
            WBSDFRuntimeSnapshotScheduled = NO;
            needsUpdate = updated && WBSDFRuntimeSnapshotGeneration != scheduledGeneration;
            shouldRetry = NO;
            if (updated) {
                WBSDFRuntimeSnapshotRetryCount = 0;
            } else if (WBSDFRuntimeSnapshotRetryCount < 4) {
                WBSDFRuntimeSnapshotRetryCount++;
                shouldRetry = YES;
            }
            retryCount = WBSDFRuntimeSnapshotRetryCount;
        }
        if (needsUpdate) {
            WBSDFScheduleRuntimeSnapshot();
        } else if (shouldRetry) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(retryCount * 0.5 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                WBSDFScheduleRuntimeSnapshot();
            });
        }
    });
}

static void WBSDFRecordRuntimeFailure(NSString *reason, BOOL disableForProcess) {
    @synchronized(WBSDFDisplacementRenderer.class) {
        WBSDFLastRuntimeFailure = reason;
        WBSDFRuntimeFailureCount++;
        if (disableForProcess) {
            WBSDFDisabledForProcess = YES;
        }
    }
    WBSDFScheduleRuntimeSnapshot();
}

static void WBSDFRecordRuntimeSuccess(void) {
    @synchronized(WBSDFDisplacementRenderer.class) {
        if (WBSDFRuntimeApplicationSucceeded) {
            return;
        }
        WBSDFRuntimeApplicationSucceeded = YES;
    }
    WBSDFScheduleRuntimeSnapshot();
}

static NSCache<NSString *, UIImage *> *WBSDFImageCache(void) {
    static NSCache<NSString *, UIImage *> *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSCache new];
        cache.countLimit = 96;
        cache.totalCostLimit = 16 * 1024 * 1024;
    });
    return cache;
}

static NSMutableSet<NSString *> *WBSDFPendingKeys(void) {
    static NSMutableSet<NSString *> *keys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keys = [NSMutableSet set];
    });
    return keys;
}

static dispatch_queue_t WBSDFGenerationQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.bi8bo.wechat.bubble.sdf-generation", DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(queue, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0));
    });
    return queue;
}

static void WBSDistanceTransform1D(const float *input, NSInteger count, float *output, NSInteger *sites, float *boundaries) {
    NSInteger last = 0;
    sites[0] = 0;
    boundaries[0] = -INFINITY;
    boundaries[1] = INFINITY;
    for (NSInteger q = 1; q < count; q++) {
        NSInteger site = sites[last];
        float boundary = ((input[q] + (float)(q * q)) - (input[site] + (float)(site * site))) / (2.0f * (float)(q - site));
        while (last > 0 && boundary <= boundaries[last]) {
            last--;
            site = sites[last];
            boundary = ((input[q] + (float)(q * q)) - (input[site] + (float)(site * site))) / (2.0f * (float)(q - site));
        }
        last++;
        sites[last] = q;
        boundaries[last] = boundary;
        boundaries[last + 1] = INFINITY;
    }
    last = 0;
    for (NSInteger q = 0; q < count; q++) {
        while (boundaries[last + 1] < (float)q) {
            last++;
        }
        float delta = (float)(q - sites[last]);
        output[q] = delta * delta + input[sites[last]];
    }
}

static float *WBSDFDistanceTransform(const uint8_t *mask, size_t width, size_t height, BOOL distanceToInside) {
    if (!mask || width < 1 || height < 1 || width > SIZE_MAX / height) {
        return NULL;
    }
    size_t count = width * height;
    size_t maximum = MAX(width, height);
    if (count > SIZE_MAX / sizeof(float) || maximum > SIZE_MAX / sizeof(float) || maximum > SIZE_MAX / sizeof(NSInteger)) {
        return NULL;
    }
    float *vertical = calloc(count, sizeof(float));
    float *result = calloc(count, sizeof(float));
    float *input = calloc(maximum, sizeof(float));
    float *output = calloc(maximum, sizeof(float));
    NSInteger *sites = calloc(maximum, sizeof(NSInteger));
    float *boundaries = calloc(maximum + 1, sizeof(float));
    if (!vertical || !result || !input || !output || !sites || !boundaries) {
        free(vertical);
        free(result);
        free(input);
        free(output);
        free(sites);
        free(boundaries);
        return NULL;
    }
    const float distant = 1.0e10f;
    for (size_t x = 0; x < width; x++) {
        for (size_t y = 0; y < height; y++) {
            BOOL inside = mask[y * width + x] >= 128;
            input[y] = (distanceToInside ? inside : !inside) ? 0.0f : distant;
        }
        WBSDistanceTransform1D(input, (NSInteger)height, output, sites, boundaries);
        for (size_t y = 0; y < height; y++) {
            vertical[y * width + x] = output[y];
        }
    }
    for (size_t y = 0; y < height; y++) {
        for (size_t x = 0; x < width; x++) {
            input[x] = vertical[y * width + x];
        }
        WBSDistanceTransform1D(input, (NSInteger)width, output, sites, boundaries);
        for (size_t x = 0; x < width; x++) {
            result[y * width + x] = sqrtf(output[x]);
        }
    }
    free(vertical);
    free(input);
    free(output);
    free(sites);
    free(boundaries);
    return result;
}

static UIImage *WBSDFCreateDisplacementImage(UIBezierPath *path, CGRect bounds) {
    CGFloat boundsWidth = CGRectGetWidth(bounds);
    CGFloat boundsHeight = CGRectGetHeight(bounds);
    if (!path || CGRectIsNull(bounds) || CGRectIsEmpty(bounds) || !isfinite(boundsWidth) || !isfinite(boundsHeight) || boundsWidth > 512.0 || boundsHeight > 1024.0) {
        return nil;
    }
    size_t width = (size_t)MAX(2.0, ceil(boundsWidth));
    size_t height = (size_t)MAX(2.0, ceil(boundsHeight));
    if (width > SIZE_MAX / height || width * height > 262144) {
        return nil;
    }
    const size_t padding = 2;
    size_t paddedWidth = width + padding * 2;
    size_t paddedHeight = height + padding * 2;
    if (paddedWidth > SIZE_MAX / paddedHeight) {
        return nil;
    }
    size_t paddedCount = paddedWidth * paddedHeight;
    uint8_t *mask = calloc(paddedCount, sizeof(uint8_t));
    if (!mask) {
        return nil;
    }
    CGColorSpaceRef graySpace = CGColorSpaceCreateDeviceGray();
    CGContextRef maskContext = CGBitmapContextCreate(mask, paddedWidth, paddedHeight, 8, paddedWidth, graySpace, kCGImageAlphaNone);
    CGColorSpaceRelease(graySpace);
    if (!maskContext) {
        free(mask);
        return nil;
    }
    CGContextTranslateCTM(maskContext, (CGFloat)padding, (CGFloat)padding + (CGFloat)height);
    CGContextScaleCTM(maskContext, (CGFloat)width / boundsWidth, -(CGFloat)height / boundsHeight);
    CGContextTranslateCTM(maskContext, -CGRectGetMinX(bounds), -CGRectGetMinY(bounds));
    CGContextSetFillColorWithColor(maskContext, UIColor.whiteColor.CGColor);
    CGContextAddPath(maskContext, path.CGPath);
    CGContextFillPath(maskContext);
    CGContextRelease(maskContext);
    float *distanceToOutside = WBSDFDistanceTransform(mask, paddedWidth, paddedHeight, NO);
    float *distanceToInside = WBSDFDistanceTransform(mask, paddedWidth, paddedHeight, YES);
    if (!distanceToOutside || !distanceToInside) {
        free(mask);
        free(distanceToOutside);
        free(distanceToInside);
        return nil;
    }
    float *signedDistance = calloc(paddedCount, sizeof(float));
    size_t outputCount = width * height;
    if (!signedDistance || outputCount > SIZE_MAX / 4) {
        free(mask);
        free(distanceToOutside);
        free(distanceToInside);
        free(signedDistance);
        return nil;
    }
    uint8_t *pixels = calloc(outputCount * 4, sizeof(uint8_t));
    if (!pixels) {
        free(mask);
        free(distanceToOutside);
        free(distanceToInside);
        free(signedDistance);
        return nil;
    }
    for (size_t index = 0; index < paddedCount; index++) {
        signedDistance[index] = distanceToInside[index] - distanceToOutside[index];
    }
    const float edgeWidth = 14.0f;
    for (size_t y = 0; y < height; y++) {
        size_t paddedY = y + padding;
        for (size_t x = 0; x < width; x++) {
            size_t paddedX = x + padding;
            size_t paddedIndex = paddedY * paddedWidth + paddedX;
            size_t outputIndex = y * width + x;
            float dx = signedDistance[paddedY * paddedWidth + paddedX + 1] - signedDistance[paddedY * paddedWidth + paddedX - 1];
            float dy = signedDistance[(paddedY + 1) * paddedWidth + paddedX] - signedDistance[(paddedY - 1) * paddedWidth + paddedX];
            float length = sqrtf(dx * dx + dy * dy);
            float normalX = length > 0.0001f ? dx / length : 0.0f;
            float normalY = length > 0.0001f ? dy / length : 0.0f;
            float edge = mask[paddedIndex] >= 128 ? fmaxf(0.0f, fminf(1.0f, 1.0f - distanceToOutside[paddedIndex] / edgeWidth)) : 0.0f;
            edge = edge * edge * (3.0f - 2.0f * edge);
            pixels[outputIndex * 4] = (uint8_t)lrintf(fmaxf(0.0f, fminf(255.0f, 127.5f + normalX * edge * 127.5f)));
            pixels[outputIndex * 4 + 1] = (uint8_t)lrintf(fmaxf(0.0f, fminf(255.0f, 127.5f + normalY * edge * 127.5f)));
            pixels[outputIndex * 4 + 2] = 128;
            pixels[outputIndex * 4 + 3] = 255;
        }
    }
    free(mask);
    free(distanceToOutside);
    free(distanceToInside);
    free(signedDistance);
    CGColorSpaceRef rgbSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef imageContext = CGBitmapContextCreate(pixels, width, height, 8, width * 4, rgbSpace, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(rgbSpace);
    if (!imageContext) {
        free(pixels);
        return nil;
    }
    CGImageRef imageRef = CGBitmapContextCreateImage(imageContext);
    CGContextRelease(imageContext);
    UIImage *image = nil;
    if (imageRef) {
        image = [UIImage imageWithCGImage:imageRef scale:1.0 orientation:UIImageOrientationUp];
        CGImageRelease(imageRef);
    }
    free(pixels);
    return image;
}

static CALayer *WBSDFFindBackdropLayer(UIView *view) {
    NSString *layerName = NSStringFromClass(view.layer.class);
    NSString *viewName = NSStringFromClass(view.class);
    if ([layerName containsString:@"Backdrop"] || [viewName containsString:@"Backdrop"]) {
        return view.layer;
    }
    for (UIView *subview in view.subviews) {
        CALayer *layer = WBSDFFindBackdropLayer(subview);
        if (layer) {
            return layer;
        }
    }
    return nil;
}

@interface WBSDFDisplacementRenderer ()
@property (nonatomic, weak) UIVisualEffectView *effectView;
@property (nonatomic, strong) CALayer *backdropLayer;
@property (nonatomic, copy) NSArray *originalFilters;
@property (nonatomic, copy) NSArray *installedFilters;
@property (nonatomic, copy) NSString *installedImageCacheKey;
@property (nonatomic, assign) BOOL backdropRetryScheduled;
@end

@implementation WBSDFDisplacementRenderer

+ (BOOL)isAvailable {
    WBSDFProbeCapability();
    @synchronized(self) {
        return WBSDFCapabilityAvailable && !WBSDFDisabledForProcess;
    }
}

+ (NSDictionary<NSString *, id> *)capabilitySnapshot {
    BOOL available = [self isAvailable];
    @synchronized(self) {
        return @{
            @"available": @(available),
            @"capabilityProbed": @(WBSDFCapabilityProbed),
            @"probeReason": WBSDFProbeReason,
            @"reportedInputKeys": WBSDFReportedInputKeys ?: @[],
            @"inputValidationMode": @"guarded-kvc-runtime",
            @"applicationSucceeded": @(WBSDFRuntimeApplicationSucceeded),
            @"disabledForProcess": @(WBSDFDisabledForProcess),
            @"lastRuntimeFailure": WBSDFLastRuntimeFailure,
            @"runtimeFailureCount": @(WBSDFRuntimeFailureCount)
        };
    }
}

- (NSString *)imageCacheKeyForBaseKey:(NSString *)baseKey bounds:(CGRect)bounds {
    size_t width = (size_t)MAX(2.0, ceil(CGRectGetWidth(bounds)));
    size_t height = (size_t)MAX(2.0, ceil(CGRectGetHeight(bounds)));
    return [NSString stringWithFormat:@"v2-%@-%zux%zu-%.2f", baseKey, width, height, UIScreen.mainScreen.scale];
}

- (WBSDFApplicationResult)scheduleImageForPath:(UIBezierPath *)path bounds:(CGRect)bounds cacheKey:(NSString *)cacheKey effectView:(UIVisualEffectView *)effectView {
    NSMutableSet<NSString *> *pendingKeys = WBSDFPendingKeys();
    @synchronized(pendingKeys) {
        if ([pendingKeys containsObject:cacheKey]) {
            return WBSDFApplicationResultPending;
        }
        [pendingKeys addObject:cacheKey];
    }
    UIBezierPath *pathCopy = [path copy];
    __weak UIVisualEffectView *weakEffectView = effectView;
    dispatch_async(WBSDFGenerationQueue(), ^{
        UIImage *image = WBSDFCreateDisplacementImage(pathCopy, bounds);
        if (image) {
            NSUInteger cost = (NSUInteger)(CGImageGetWidth(image.CGImage) * CGImageGetHeight(image.CGImage) * 4);
            [WBSDFImageCache() setObject:image forKey:cacheKey cost:cost];
        } else {
            WBSDFRecordRuntimeFailure(@"sdf-image-generation-failed", YES);
        }
        @synchronized(pendingKeys) {
            [pendingKeys removeObject:cacheKey];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            UIVisualEffectView *strongEffectView = weakEffectView;
            [strongEffectView.superview setNeedsLayout];
        });
    });
    return WBSDFApplicationResultPending;
}

- (WBSDFApplicationResult)applyToEffectView:(UIVisualEffectView *)effectView path:(UIBezierPath *)path bounds:(CGRect)bounds cacheKey:(NSString *)cacheKey {
    if (![WBSDFDisplacementRenderer isAvailable] || !effectView || !path || CGRectIsNull(bounds) || CGRectIsEmpty(bounds)) {
        return WBSDFApplicationResultFailed;
    }
    NSString *imageCacheKey = [self imageCacheKeyForBaseKey:cacheKey bounds:bounds];
    UIImage *image = [WBSDFImageCache() objectForKey:imageCacheKey];
    if (!image) {
        return [self scheduleImageForPath:path bounds:bounds cacheKey:imageCacheKey effectView:effectView];
    }
    CALayer *backdropLayer = WBSDFFindBackdropLayer(effectView);
    if (!backdropLayer) {
        if (!self.backdropRetryScheduled) {
            self.backdropRetryScheduled = YES;
            __weak typeof(self) weakSelf = self;
            __weak UIVisualEffectView *weakEffectView = effectView;
            dispatch_async(dispatch_get_main_queue(), ^{
                weakSelf.backdropRetryScheduled = NO;
                [weakEffectView.superview setNeedsLayout];
            });
        }
        return WBSDFApplicationResultPending;
    }
    self.backdropRetryScheduled = NO;
    if (self.backdropLayer && self.backdropLayer != backdropLayer) {
        [self reset];
    }
    NSString *applicationStep = @"read-backdrop-filters";
    @try {
        id currentFilters = [backdropLayer valueForKey:@"filters"];
        if (self.backdropLayer == backdropLayer && [self.installedImageCacheKey isEqualToString:imageCacheKey] && self.installedFilters && [currentFilters isEqual:self.installedFilters]) {
            WBSDFRecordRuntimeSuccess();
            return WBSDFApplicationResultApplied;
        }
        applicationStep = @"create-displacement-filter";
        id displacement = WBSDFCreateFilter(@"displacementMap");
        if (!displacement) {
            WBSDFRecordRuntimeFailure(@"displacement-filter-creation-failed", YES);
            return WBSDFApplicationResultFailed;
        }
        applicationStep = @"set-input-mask-image";
        [displacement setValue:(__bridge id)image.CGImage forKey:@"inputMaskImage"];
        applicationStep = @"set-input-amount";
        [displacement setValue:@(11.0) forKey:@"inputAmount"];
        NSArray *baseFilters = self.originalFilters;
        if (self.backdropLayer != backdropLayer || !self.installedFilters || ![currentFilters isEqual:self.installedFilters]) {
            NSMutableArray *externalFilters = [currentFilters isKindOfClass:NSArray.class] ? [currentFilters mutableCopy] : [NSMutableArray array];
            id previousDisplacement = self.installedFilters.firstObject;
            if (previousDisplacement) {
                for (NSInteger index = (NSInteger)externalFilters.count - 1; index >= 0; index--) {
                    if (externalFilters[(NSUInteger)index] == previousDisplacement) {
                        [externalFilters removeObjectAtIndex:(NSUInteger)index];
                    }
                }
            }
            baseFilters = [externalFilters copy];
            self.originalFilters = baseFilters;
        }
        NSMutableArray *filters = [NSMutableArray arrayWithObject:displacement];
        [filters addObjectsFromArray:baseFilters];
        applicationStep = @"install-backdrop-filters";
        [backdropLayer setValue:filters forKey:@"filters"];
        @try {
            [backdropLayer setValue:@(UIScreen.mainScreen.scale) forKey:@"scale"];
        } @catch (__unused NSException *exception) {
        }
        self.effectView = effectView;
        self.backdropLayer = backdropLayer;
        self.installedFilters = [filters copy];
        self.installedImageCacheKey = imageCacheKey;
        WBSDFRecordRuntimeSuccess();
        return WBSDFApplicationResultApplied;
    } @catch (__unused NSException *exception) {
        [self reset];
        WBSDFRecordRuntimeFailure([NSString stringWithFormat:@"filter-application-exception-%@", applicationStep], YES);
        return WBSDFApplicationResultFailed;
    }
}

- (void)reset {
    @try {
        id currentFilters = [self.backdropLayer valueForKey:@"filters"];
        if (self.backdropLayer && self.installedFilters && [currentFilters isEqual:self.installedFilters]) {
            [self.backdropLayer setValue:self.originalFilters ?: @[] forKey:@"filters"];
        }
    } @catch (__unused NSException *exception) {
    }
    self.effectView = nil;
    self.backdropLayer = nil;
    self.originalFilters = nil;
    self.installedFilters = nil;
    self.installedImageCacheKey = nil;
    self.backdropRetryScheduled = NO;
}

@end
