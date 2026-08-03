#import "WBBubbleThemeProvider.h"
#import "WBBubblePreferences.h"

@implementation WBBubbleThemeProvider

+ (BOOL)isEnabled {
    return [WBBubblePreferences isEnabled];
}

+ (NSString *)themeIdentifier {
    return @"stage04-preferences-v1";
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
