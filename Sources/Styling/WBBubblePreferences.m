#import "WBBubblePreferences.h"
#import <dispatch/dispatch.h>
#import <math.h>

NSString * const WBBubblePreferencesDidChangeNotification = @"com.wechatbubble.preferences.changed";

static NSString * const WBEnabledKey = @"com.wechatbubble.enabled";
static NSString * const WBMaterialKey = @"com.wechatbubble.material";
static NSString * const WBLightOutgoingFillKey = @"com.wechatbubble.light.outgoing.fill";
static NSString * const WBLightIncomingFillKey = @"com.wechatbubble.light.incoming.fill";
static NSString * const WBDarkOutgoingFillKey = @"com.wechatbubble.dark.outgoing.fill";
static NSString * const WBDarkIncomingFillKey = @"com.wechatbubble.dark.incoming.fill";
static NSString * const WBLightOutgoingBorderKey = @"com.wechatbubble.light.outgoing.border";
static NSString * const WBLightIncomingBorderKey = @"com.wechatbubble.light.incoming.border";
static NSString * const WBDarkOutgoingBorderKey = @"com.wechatbubble.dark.outgoing.border";
static NSString * const WBDarkIncomingBorderKey = @"com.wechatbubble.dark.incoming.border";
static NSString * const WBCornerRadiusKey = @"com.wechatbubble.cornerRadius";
static NSString * const WBBorderWidthKey = @"com.wechatbubble.borderWidth";
static NSString * const WBOpacityKey = @"com.wechatbubble.opacity";
static NSString * const WBSchemaVersionKey = @"com.wechatbubble.schemaVersion";
static NSString * const WBLegacyOutgoingColorKey = @"com.wechatbubble.outgoingColor";
static NSString * const WBLegacyIncomingColorKey = @"com.wechatbubble.incomingColor";
static NSInteger const WBSchemaVersion = 3;

@implementation WBBubblePreferences

+ (NSUserDefaults *)defaults {
    return NSUserDefaults.standardUserDefaults;
}

+ (NSDictionary<NSString *, id> *)defaultValues {
    return @{
        WBEnabledKey: @YES,
        WBMaterialKey: @(WBBubbleMaterialSolid),
        WBLightOutgoingFillKey: @"DCC8FF",
        WBLightIncomingFillKey: @"E8F0FF",
        WBDarkOutgoingFillKey: @"4C3E70",
        WBDarkIncomingFillKey: @"26344A",
        WBLightOutgoingBorderKey: @"8B68C9",
        WBLightIncomingBorderKey: @"708FB8",
        WBDarkOutgoingBorderKey: @"9B84DC",
        WBDarkIncomingBorderKey: @"5B7497",
        WBCornerRadiusKey: @5.0,
        WBBorderWidthKey: @1.0,
        WBOpacityKey: @1.0,
        WBSchemaVersionKey: @(WBSchemaVersion)
    };
}

+ (NSArray<NSString *> *)storedKeys {
    return [[self defaultValues].allKeys arrayByAddingObjectsFromArray:@[WBLegacyOutgoingColorKey, WBLegacyIncomingColorKey]];
}

+ (NSString *)normalizedHex:(id)value fallback:(NSString *)fallback {
    if (![value isKindOfClass:NSString.class]) {
        return fallback;
    }
    NSString *normalized = [[(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] uppercaseString];
    if ([normalized hasPrefix:@"#"]) {
        normalized = [normalized substringFromIndex:1];
    }
    unsigned int parsed = 0;
    NSScanner *scanner = [NSScanner scannerWithString:normalized];
    if (normalized.length != 6 || ![scanner scanHexInt:&parsed] || !scanner.isAtEnd) {
        return fallback;
    }
    return normalized;
}

+ (void)removeStoredValues {
    for (NSString *key in [self storedKeys]) {
        [[self defaults] removeObjectForKey:key];
    }
}

+ (void)normalizeStoredValues {
    NSUserDefaults *defaults = [self defaults];
    NSDictionary<NSString *, id> *fallbacks = [self defaultValues];
    NSArray<NSString *> *colorKeys = @[
        WBLightOutgoingFillKey,
        WBLightIncomingFillKey,
        WBDarkOutgoingFillKey,
        WBDarkIncomingFillKey,
        WBLightOutgoingBorderKey,
        WBLightIncomingBorderKey,
        WBDarkOutgoingBorderKey,
        WBDarkIncomingBorderKey
    ];
    for (NSString *key in colorKeys) {
        id value = [defaults objectForKey:key];
        if (value) {
            [defaults setObject:[self normalizedHex:value fallback:fallbacks[key]] forKey:key];
        }
    }
    id enabled = [defaults objectForKey:WBEnabledKey];
    if (enabled && [enabled isKindOfClass:NSNumber.class]) {
        [defaults setBool:[enabled boolValue] forKey:WBEnabledKey];
    } else if (enabled) {
        [defaults removeObjectForKey:WBEnabledKey];
    }
    id material = [defaults objectForKey:WBMaterialKey];
    if (material && (![material isKindOfClass:NSNumber.class] || ([material integerValue] != WBBubbleMaterialSolid && [material integerValue] != WBBubbleMaterialGlass))) {
        [defaults removeObjectForKey:WBMaterialKey];
    }
    NSDictionary<NSString *, NSArray<NSNumber *> *> *ranges = @{
        WBCornerRadiusKey: @[@4.0, @24.0],
        WBBorderWidthKey: @[@0.0, @3.0],
        WBOpacityKey: @[@0.35, @1.0]
    };
    for (NSString *key in ranges) {
        id value = [defaults objectForKey:key];
        if (!value) {
            continue;
        }
        if (![value isKindOfClass:NSNumber.class] || !isfinite([value doubleValue])) {
            [defaults removeObjectForKey:key];
            continue;
        }
        CGFloat minimum = ranges[key][0].doubleValue;
        CGFloat maximum = ranges[key][1].doubleValue;
        [defaults setDouble:MIN(MAX([value doubleValue], minimum), maximum) forKey:key];
    }
}

+ (void)initialize {
    if (self != WBBubblePreferences.class) {
        return;
    }
    NSUserDefaults *defaults = [self defaults];
    id storedSchema = [defaults objectForKey:WBSchemaVersionKey];
    BOOL schemaMissing = storedSchema == nil;
    double schemaValue = [storedSchema isKindOfClass:NSNumber.class] ? [storedSchema doubleValue] : NAN;
    BOOL schemaValid = !schemaMissing && isfinite(schemaValue) && floor(schemaValue) == schemaValue;
    NSInteger schema = schemaValid ? (NSInteger)schemaValue : 0;
    BOOL legacyValuesExist = [defaults objectForKey:WBLegacyOutgoingColorKey] != nil || [defaults objectForKey:WBLegacyIncomingColorKey] != nil;
    if (schema == 1 || (schemaMissing && legacyValuesExist)) {
        NSDictionary<NSString *, id> *fallbacks = [self defaultValues];
        NSString *outgoing = [self normalizedHex:[defaults objectForKey:WBLegacyOutgoingColorKey] fallback:fallbacks[WBLightOutgoingFillKey]];
        NSString *incoming = [self normalizedHex:[defaults objectForKey:WBLegacyIncomingColorKey] fallback:fallbacks[WBLightIncomingFillKey]];
        [defaults setObject:outgoing forKey:WBLightOutgoingFillKey];
        [defaults setObject:incoming forKey:WBLightIncomingFillKey];
        [defaults removeObjectForKey:WBLegacyOutgoingColorKey];
        [defaults removeObjectForKey:WBLegacyIncomingColorKey];
    } else if (schema == 2) {
        [defaults removeObjectForKey:WBMaterialKey];
    }
    if (!schemaMissing && !schemaValid) {
        [defaults removeObjectForKey:WBSchemaVersionKey];
    }
    [self normalizeStoredValues];
    [defaults setInteger:WBSchemaVersion forKey:WBSchemaVersionKey];
    [defaults registerDefaults:[self defaultValues]];
}

+ (NSString *)fillKeyForOutgoing:(BOOL)outgoing dark:(BOOL)dark {
    if (dark) {
        return outgoing ? WBDarkOutgoingFillKey : WBDarkIncomingFillKey;
    }
    return outgoing ? WBLightOutgoingFillKey : WBLightIncomingFillKey;
}

+ (NSString *)borderKeyForOutgoing:(BOOL)outgoing dark:(BOOL)dark {
    if (dark) {
        return outgoing ? WBDarkOutgoingBorderKey : WBDarkIncomingBorderKey;
    }
    return outgoing ? WBLightOutgoingBorderKey : WBLightIncomingBorderKey;
}

+ (NSString *)hexForKey:(NSString *)key {
    NSString *fallback = [self defaultValues][key];
    return [self normalizedHex:[[self defaults] objectForKey:key] fallback:fallback];
}

+ (UIColor *)colorForHex:(NSString *)hex alpha:(CGFloat)alpha {
    unsigned int value = 0;
    [[NSScanner scannerWithString:hex] scanHexInt:&value];
    return [UIColor colorWithRed:((value >> 16) & 0xFF) / 255.0 green:((value >> 8) & 0xFF) / 255.0 blue:(value & 0xFF) / 255.0 alpha:alpha];
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

+ (CGFloat)numberForKey:(NSString *)key minimum:(CGFloat)minimum maximum:(CGFloat)maximum {
    id value = [[self defaults] objectForKey:key];
    CGFloat fallback = [[self defaultValues][key] doubleValue];
    CGFloat number = [value isKindOfClass:NSNumber.class] ? [value doubleValue] : fallback;
    return MIN(MAX(number, minimum), maximum);
}

+ (void)notifyChange {
    void (^notification)(void) = ^{
        [NSNotificationCenter.defaultCenter postNotificationName:WBBubblePreferencesDidChangeNotification object:nil];
    };
    if (NSThread.isMainThread) {
        notification();
    } else {
        dispatch_async(dispatch_get_main_queue(), notification);
    }
}

+ (void)setObject:(id)object forKey:(NSString *)key {
    [[self defaults] setObject:object forKey:key];
    [self notifyChange];
}

+ (BOOL)isEnabled {
    id value = [[self defaults] objectForKey:WBEnabledKey];
    return [value isKindOfClass:NSNumber.class] ? [value boolValue] : YES;
}

+ (WBBubbleMaterial)material {
    id value = [[self defaults] objectForKey:WBMaterialKey];
    return [value isKindOfClass:NSNumber.class] && [value integerValue] == WBBubbleMaterialGlass ? WBBubbleMaterialGlass : WBBubbleMaterialSolid;
}

+ (NSString *)materialIdentifier {
    return [self material] == WBBubbleMaterialGlass ? @"glass" : @"solid";
}

+ (UIColor *)fillColorForOutgoing:(BOOL)outgoing dark:(BOOL)dark {
    return [self colorForHex:[self fillColorHexForOutgoing:outgoing dark:dark] alpha:[self opacity]];
}

+ (UIColor *)borderColorForOutgoing:(BOOL)outgoing dark:(BOOL)dark {
    return [self colorForHex:[self borderColorHexForOutgoing:outgoing dark:dark] alpha:1.0];
}

+ (NSString *)fillColorHexForOutgoing:(BOOL)outgoing dark:(BOOL)dark {
    return [self hexForKey:[self fillKeyForOutgoing:outgoing dark:dark]];
}

+ (NSString *)borderColorHexForOutgoing:(BOOL)outgoing dark:(BOOL)dark {
    return [self hexForKey:[self borderKeyForOutgoing:outgoing dark:dark]];
}

+ (CGFloat)cornerRadius {
    return [self numberForKey:WBCornerRadiusKey minimum:4.0 maximum:24.0];
}

+ (CGFloat)borderWidth {
    return [self numberForKey:WBBorderWidthKey minimum:0.0 maximum:3.0];
}

+ (CGFloat)opacity {
    return [self numberForKey:WBOpacityKey minimum:0.35 maximum:1.0];
}

+ (void)setEnabled:(BOOL)enabled {
    [self setObject:@(enabled) forKey:WBEnabledKey];
}

+ (void)setMaterial:(WBBubbleMaterial)material {
    [self setObject:@(material == WBBubbleMaterialGlass ? WBBubbleMaterialGlass : WBBubbleMaterialSolid) forKey:WBMaterialKey];
}

+ (void)setFillColor:(UIColor *)color outgoing:(BOOL)outgoing dark:(BOOL)dark {
    NSString *hex = [self hexStringForColor:color];
    if (hex) {
        [self setObject:hex forKey:[self fillKeyForOutgoing:outgoing dark:dark]];
    }
}

+ (void)setBorderColor:(UIColor *)color outgoing:(BOOL)outgoing dark:(BOOL)dark {
    NSString *hex = [self hexStringForColor:color];
    if (hex) {
        [self setObject:hex forKey:[self borderKeyForOutgoing:outgoing dark:dark]];
    }
}

+ (void)setCornerRadius:(CGFloat)cornerRadius {
    [self setObject:@(MIN(MAX(cornerRadius, 4.0), 24.0)) forKey:WBCornerRadiusKey];
}

+ (void)setBorderWidth:(CGFloat)borderWidth {
    [self setObject:@(MIN(MAX(borderWidth, 0.0), 3.0)) forKey:WBBorderWidthKey];
}

+ (void)setOpacity:(CGFloat)opacity {
    [self setObject:@(MIN(MAX(opacity, 0.35), 1.0)) forKey:WBOpacityKey];
}

+ (void)reset {
    [self removeStoredValues];
    [[self defaults] setInteger:WBSchemaVersion forKey:WBSchemaVersionKey];
    [self notifyChange];
}

+ (NSDictionary<NSString *, id> *)snapshot {
    return @{
        @"schemaVersion": @(WBSchemaVersion),
        @"enabled": @([self isEnabled]),
        @"material": [self materialIdentifier],
        @"light": @{
            @"outgoingFill": [self fillColorHexForOutgoing:YES dark:NO],
            @"incomingFill": [self fillColorHexForOutgoing:NO dark:NO],
            @"outgoingBorder": [self borderColorHexForOutgoing:YES dark:NO],
            @"incomingBorder": [self borderColorHexForOutgoing:NO dark:NO]
        },
        @"dark": @{
            @"outgoingFill": [self fillColorHexForOutgoing:YES dark:YES],
            @"incomingFill": [self fillColorHexForOutgoing:NO dark:YES],
            @"outgoingBorder": [self borderColorHexForOutgoing:YES dark:YES],
            @"incomingBorder": [self borderColorHexForOutgoing:NO dark:YES]
        },
        @"cornerRadius": @([self cornerRadius]),
        @"borderWidth": @([self borderWidth]),
        @"opacity": @([self opacity])
    };
}

@end
