#import "WBVersionGate.h"

@implementation WBVersionGate

+ (NSString *)shortVersion {
    return [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
}

+ (NSString *)buildVersion {
    return [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"";
}

+ (BOOL)allowsDiscovery {
    return [[self shortVersion] isEqualToString:@"8.0.60"] && [[self buildVersion] isEqualToString:@"8.0.60.35"];
}

+ (BOOL)allowsUIModification {
    return [self allowsDiscovery];
}

+ (NSDictionary<NSString *, id> *)snapshot {
    BOOL discoveryAllowed = [self allowsDiscovery];
    BOOL uiModificationAllowed = [self allowsUIModification];
    return @{
        @"shortVersion": [self shortVersion],
        @"buildVersion": [self buildVersion],
        @"support": uiModificationAllowed ? @"supported" : @"unknown",
        @"discoveryAllowed": @(discoveryAllowed),
        @"uiModificationAllowed": @(uiModificationAllowed)
    };
}

@end
