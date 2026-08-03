#import "WBBubbleThemeProvider.h"
#import "WBBubblePreferences.h"

@implementation WBBubbleThemeProvider

+ (BOOL)isEnabled {
    return [WBBubblePreferences isEnabled];
}

+ (BOOL)usesGlassMaterial {
    return [WBBubblePreferences material] == WBBubbleMaterialGlass;
}

+ (BOOL)nativeLiquidGlassAvailable {
    Class glassEffectClass = NSClassFromString(@"UIGlassEffect");
    return glassEffectClass && [glassEffectClass isSubclassOfClass:UIVisualEffect.class] && [glassEffectClass instancesRespondToSelector:NSSelectorFromString(@"init")] && [glassEffectClass instancesRespondToSelector:NSSelectorFromString(@"setTintColor:")] && [glassEffectClass instancesRespondToSelector:NSSelectorFromString(@"setInteractive:")];
}

+ (NSString *)materialIdentifier {
    return [WBBubblePreferences materialIdentifier];
}

+ (NSString *)resolvedMaterialBackend {
    if (![self usesGlassMaterial]) {
        return @"solid";
    }
    return [self nativeLiquidGlassAvailable] ? @"native-uiglass-effect" : @"compatibility-colorless-lens";
}

+ (NSString *)themeIdentifier {
    return [NSString stringWithFormat:@"stage05-material-v2-%@", [self resolvedMaterialBackend]];
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
