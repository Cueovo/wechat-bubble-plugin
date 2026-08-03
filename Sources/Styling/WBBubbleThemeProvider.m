#import "WBBubbleThemeProvider.h"
#import "WBBubblePreferences.h"

@implementation WBBubbleThemeProvider

+ (UIColor *)colorWithRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue {
    return [UIColor colorWithRed:red / 255.0 green:green / 255.0 blue:blue / 255.0 alpha:1.0];
}

+ (BOOL)isEnabled {
    return [WBBubblePreferences isEnabled];
}

+ (NSString *)themeIdentifier {
    return @"stage03-fixed-v2";
}

+ (UIColor *)fillColorForDirection:(WBBubbleDirection)direction traitCollection:(UITraitCollection *)traitCollection {
    BOOL dark = traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    if (direction == WBBubbleDirectionOutgoing) {
        return dark ? [self colorWithRed:76 green:62 blue:112] : [self colorWithRed:220 green:200 blue:255];
    }
    return dark ? [self colorWithRed:38 green:52 blue:74] : [self colorWithRed:232 green:240 blue:255];
}

+ (UIColor *)borderColorForDirection:(WBBubbleDirection)direction traitCollection:(UITraitCollection *)traitCollection {
    BOOL dark = traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    if (direction == WBBubbleDirectionOutgoing) {
        return dark ? [self colorWithRed:155 green:132 blue:220] : [self colorWithRed:139 green:104 blue:201];
    }
    return dark ? [self colorWithRed:91 green:116 blue:151] : [self colorWithRed:112 green:143 blue:184];
}

+ (CGFloat)fillOpacity {
    return 1.0;
}

+ (CGFloat)cornerRadius {
    return 5.0;
}

+ (CGFloat)borderWidth {
    return 1.0;
}

@end
