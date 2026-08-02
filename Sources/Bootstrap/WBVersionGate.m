#import "WBVersionGate.h"

@implementation WBVersionGate

+ (NSString *)shortVersion {
    return [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
}

+ (NSString *)buildVersion {
    return [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"";
}

+ (BOOL)allowsDiscovery {
    return [[self shortVersion] isEqualToString:@"8.0.60"];
}

+ (NSDictionary<NSString *, id> *)snapshot {
    BOOL candidate = [self allowsDiscovery];
    return @{
        @"shortVersion": [self shortVersion],
        @"buildVersion": [self buildVersion],
        @"support": candidate ? @"candidate" : @"unknown",
        @"discoveryAllowed": @(candidate),
        @"uiModificationAllowed": @NO
    };
}

@end
