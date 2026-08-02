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

+ (NSDictionary<NSString *, id> *)snapshot {
    BOOL supported = [self allowsDiscovery];
    return @{
        @"shortVersion": [self shortVersion],
        @"buildVersion": [self buildVersion],
        @"support": supported ? @"supported" : @"unknown",
        @"discoveryAllowed": @(supported),
        @"uiModificationAllowed": @NO
    };
}

@end
