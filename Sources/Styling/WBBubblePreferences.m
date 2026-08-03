#import "WBBubblePreferences.h"
#import <math.h>

NSString * const WBBubblePreferencesDidChangeNotification = @"com.wechatbubble.preferences.changed";

static NSString * const WBEnabledKey = @"com.wechatbubble.enabled";
static NSString * const WBOutgoingColorKey = @"com.wechatbubble.outgoingColor";
static NSString * const WBIncomingColorKey = @"com.wechatbubble.incomingColor";
static NSString * const WBCornerRadiusKey = @"com.wechatbubble.cornerRadius";
static NSString * const WBBorderWidthKey = @"com.wechatbubble.borderWidth";
static NSString * const WBOpacityKey = @"com.wechatbubble.opacity";
static NSString * const WBSchemaVersionKey = @"com.wechatbubble.schemaVersion";
static NSInteger const WBSchemaVersion = 1;

@implementation WBBubblePreferences

+ (NSUserDefaults *)defaults {
    return [NSUserDefaults standardUserDefaults];
}

+ (NSDictionary<NSString *, id> *)defaultValues {
    return @{
        WBEnabledKey: @YES,
        WBOutgoingColorKey: @"D1B8FF",
        WBIncomingColorKey: @"BDE0FF",
        WBCornerRadiusKey: @8.0,
        WBBorderWidthKey: @0.5,
        WBOpacityKey: @0.8,
        WBSchemaVersionKey: @(WBSchemaVersion)
    };
}

+ (void)initialize {
    if (self != WBBubblePreferences.class) {
        return;
    }
    [[self defaults] registerDefaults:[self defaultValues]];
    if ([[self defaults] integerForKey:WBSchemaVersionKey] != WBSchemaVersion) {
        [[self defaults] setInteger:WBSchemaVersion forKey:WBSchemaVersionKey];
    }
}

+ (CGFloat)clamp:(CGFloat)value minimum:(CGFloat)minimum maximum:(CGFloat)maximum {
    return MIN(MAX(value, minimum), maximum);
}

+ (NSString *)hexStringForColor:(UIColor *)color {
    CGFloat red = 0.0;
    CGFloat green = 0.0;
    CGFloat blue = 0.0;
    if (![color getRed:&red green:&green blue:&blue alpha:NULL]) {
        return nil;
    }
    return [NSString stringWithFormat:@"%02lX%02lX%02lX", (long)lrint(red * 255.0), (long)lrint(green * 255.0), (long)lrint(blue * 255.0)];
}

+ (UIColor *)colorForHex:(NSString *)hex fallback:(NSString *)fallback {
    NSString *normalized = [[(hex ?: fallback) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] uppercaseString];
    if ([normalized hasPrefix:@"#"]) {
        normalized = [normalized substringFromIndex:1];
    }
    unsigned int value = 0;
    if (normalized.length != 6 || ![[NSScanner scannerWithString:normalized] scanHexInt:&value]) {
        normalized = fallback;
        [[NSScanner scannerWithString:normalized] scanHexInt:&value];
    }
    return [UIColor colorWithRed:((value >> 16) & 0xFF) / 255.0 green:((value >> 8) & 0xFF) / 255.0 blue:(value & 0xFF) / 255.0 alpha:1.0];
}

+ (void)notifyChange {
    [[NSNotificationCenter defaultCenter] postNotificationName:WBBubblePreferencesDidChangeNotification object:nil];
}

+ (void)setObject:(id)object forKey:(NSString *)key {
    [[self defaults] setObject:object forKey:key];
    [self notifyChange];
}

+ (BOOL)isEnabled {
    return [[self defaults] boolForKey:WBEnabledKey];
}

+ (UIColor *)fillColorForOutgoing:(BOOL)outgoing {
    NSString *fallback = outgoing ? [self defaultValues][WBOutgoingColorKey] : [self defaultValues][WBIncomingColorKey];
    UIColor *color = [self colorForHex:outgoing ? [self outgoingColorHex] : [self incomingColorHex] fallback:fallback];
    return [color colorWithAlphaComponent:[self opacity]];
}

+ (CGFloat)cornerRadius {
    return [self clamp:[[self defaults] doubleForKey:WBCornerRadiusKey] minimum:4.0 maximum:24.0];
}

+ (CGFloat)borderWidth {
    return [self clamp:[[self defaults] doubleForKey:WBBorderWidthKey] minimum:0.0 maximum:3.0];
}

+ (CGFloat)opacity {
    return [self clamp:[[self defaults] doubleForKey:WBOpacityKey] minimum:0.35 maximum:1.0];
}

+ (NSString *)outgoingColorHex {
    return [[self defaults] stringForKey:WBOutgoingColorKey] ?: [self defaultValues][WBOutgoingColorKey];
}

+ (NSString *)incomingColorHex {
    return [[self defaults] stringForKey:WBIncomingColorKey] ?: [self defaultValues][WBIncomingColorKey];
}

+ (void)setEnabled:(BOOL)enabled {
    [self setObject:@(enabled) forKey:WBEnabledKey];
}

+ (void)setOutgoingColor:(UIColor *)color {
    NSString *hex = [self hexStringForColor:color];
    if (hex) {
        [self setObject:hex forKey:WBOutgoingColorKey];
    }
}

+ (void)setIncomingColor:(UIColor *)color {
    NSString *hex = [self hexStringForColor:color];
    if (hex) {
        [self setObject:hex forKey:WBIncomingColorKey];
    }
}

+ (void)setCornerRadius:(CGFloat)cornerRadius {
    [self setObject:@([self clamp:cornerRadius minimum:4.0 maximum:24.0]) forKey:WBCornerRadiusKey];
}

+ (void)setBorderWidth:(CGFloat)borderWidth {
    [self setObject:@([self clamp:borderWidth minimum:0.0 maximum:3.0]) forKey:WBBorderWidthKey];
}

+ (void)setOpacity:(CGFloat)opacity {
    [self setObject:@([self clamp:opacity minimum:0.35 maximum:1.0]) forKey:WBOpacityKey];
}

+ (void)reset {
    for (NSString *key in [self defaultValues]) {
        [[self defaults] removeObjectForKey:key];
    }
    [[self defaults] registerDefaults:[self defaultValues]];
    [self notifyChange];
}

+ (NSDictionary<NSString *, id> *)snapshot {
    return @{
        @"schemaVersion": @(WBSchemaVersion),
        @"enabled": @([self isEnabled]),
        @"outgoingColor": [self outgoingColorHex],
        @"incomingColor": [self incomingColorHex],
        @"cornerRadius": @([self cornerRadius]),
        @"borderWidth": @([self borderWidth]),
        @"opacity": @([self opacity])
    };
}

@end
