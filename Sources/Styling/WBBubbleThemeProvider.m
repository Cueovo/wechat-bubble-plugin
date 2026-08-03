#import "WBBubbleThemeProvider.h"
#import "WBBubblePreferences.h"
#import "WBSDFDisplacementRenderer.h"
#import <objc/message.h>
#import <objc/runtime.h>

static BOOL WBNativeGlassAvailable;
static NSString *WBNativeGlassReason = @"not-probed";

@implementation WBBubbleThemeProvider

+ (BOOL)isEnabled {
    return [WBBubblePreferences isEnabled];
}

+ (BOOL)usesGlassMaterial {
    return [WBBubblePreferences material] == WBBubbleMaterialGlass;
}

+ (BOOL)nativeLiquidGlassAvailable {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class glassEffectClass = NSClassFromString(@"UIGlassEffect");
        if (!glassEffectClass || ![glassEffectClass isSubclassOfClass:UIVisualEffect.class]) {
            WBNativeGlassReason = @"class-unavailable";
            return;
        }
        SEL tintSelector = NSSelectorFromString(@"setTintColor:");
        SEL interactiveSelector = NSSelectorFromString(@"setInteractive:");
        Method tintMethod = class_getInstanceMethod(glassEffectClass, tintSelector);
        Method interactiveMethod = class_getInstanceMethod(glassEffectClass, interactiveSelector);
        if (!tintMethod || !interactiveMethod || method_getNumberOfArguments(tintMethod) != 3 || method_getNumberOfArguments(interactiveMethod) != 3) {
            WBNativeGlassReason = @"method-signature-unavailable";
            return;
        }
        char tintType[8] = {0};
        char interactiveType[8] = {0};
        method_getArgumentType(tintMethod, 2, tintType, sizeof(tintType));
        method_getArgumentType(interactiveMethod, 2, interactiveType, sizeof(interactiveType));
        if (tintType[0] != '@' || (interactiveType[0] != 'B' && interactiveType[0] != 'c')) {
            WBNativeGlassReason = @"method-signature-invalid";
            return;
        }
        @try {
            id effect = [[glassEffectClass alloc] init];
            if (![effect isKindOfClass:UIVisualEffect.class]) {
                WBNativeGlassReason = @"initialization-failed";
                return;
            }
            ((void (*)(id, SEL, id))objc_msgSend)(effect, tintSelector, nil);
            ((void (*)(id, SEL, BOOL))objc_msgSend)(effect, interactiveSelector, NO);
            WBNativeGlassAvailable = YES;
            WBNativeGlassReason = @"available";
        } @catch (__unused NSException *exception) {
            WBNativeGlassReason = @"initialization-exception";
        }
    });
    @synchronized(self) {
        return WBNativeGlassAvailable;
    }
}

+ (void)disableNativeLiquidGlassForProcess {
    @synchronized(self) {
        WBNativeGlassAvailable = NO;
        WBNativeGlassReason = @"runtime-installation-failed";
    }
}

+ (BOOL)sdfDisplacementAvailable {
    return [WBSDFDisplacementRenderer isAvailable];
}

+ (NSDictionary<NSString *, id> *)glassCapabilitySnapshot {
    BOOL nativeAvailable = [self nativeLiquidGlassAvailable];
    NSString *nativeReason;
    @synchronized(self) {
        nativeReason = WBNativeGlassReason;
    }
    return @{
        @"nativeLiquidGlassAvailable": @(nativeAvailable),
        @"nativeLiquidGlassReason": nativeReason,
        @"sdfDisplacement": [WBSDFDisplacementRenderer capabilitySnapshot]
    };
}

+ (NSString *)materialIdentifier {
    return [WBBubblePreferences materialIdentifier];
}

+ (NSString *)resolvedMaterialBackend {
    if (![self usesGlassMaterial]) {
        return @"solid";
    }
    if ([self nativeLiquidGlassAvailable]) {
        return @"native-uiglass-effect";
    }
    return [self sdfDisplacementAvailable] ? @"compatibility-sdf-displacement" : @"compatibility-colorless-lens";
}

+ (NSString *)themeIdentifier {
    return [NSString stringWithFormat:@"stage05-material-v3-%@", [self resolvedMaterialBackend]];
}

+ (UIColor *)fillColorForDirection:(WBBubbleDirection)direction traitCollection:(UITraitCollection *)traitCollection {
    BOOL outgoing = direction == WBBubbleDirectionOutgoing;
    BOOL dark = traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    return [WBBubblePreferences fillColorForOutgoing:outgoing dark:dark];
}

+ (UIColor *)borderColorForDirection:(WBBubbleDirection)direction traitCollection:(UITraitCollection *)traitCollection {
    BOOL outgoing = direction == WBBubbleDirectionOutgoing;
    BOOL dark = traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    return [WBBubblePreferences borderColorForOutgoing:outgoing dark:dark];
}

+ (CGFloat)fillOpacity {
    return [WBBubblePreferences opacity];
}

+ (CGFloat)cornerRadius {
    return [WBBubblePreferences cornerRadius];
}

+ (CGFloat)borderWidth {
    return [WBBubblePreferences borderWidth];
}

@end
