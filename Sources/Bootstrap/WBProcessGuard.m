#import "WBProcessGuard.h"

@implementation WBProcessGuard

+ (BOOL)isWeChatMainProcess {
    NSBundle *bundle = NSBundle.mainBundle;
    NSString *bundleIdentifier = bundle.bundleIdentifier ?: @"";
    NSString *executable = [bundle objectForInfoDictionaryKey:@"CFBundleExecutable"] ?: @"";
    NSString *processName = NSProcessInfo.processInfo.processName ?: @"";
    BOOL isApplication = [bundle.bundleURL.pathExtension.lowercaseString isEqualToString:@"app"];
    return isApplication && [bundleIdentifier isEqualToString:@"com.tencent.xin"] && executable.length > 0 && [processName isEqualToString:executable];
}

+ (NSDictionary<NSString *, id> *)snapshot {
    NSBundle *bundle = NSBundle.mainBundle;
    return @{
        @"bundleIdentifier": bundle.bundleIdentifier ?: @"",
        @"bundleExecutable": [bundle objectForInfoDictionaryKey:@"CFBundleExecutable"] ?: @"",
        @"processName": NSProcessInfo.processInfo.processName ?: @"",
        @"isWeChatMainProcess": @([self isWeChatMainProcess])
    };
}

@end
