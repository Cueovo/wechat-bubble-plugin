#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import "Bootstrap/WBProcessGuard.h"
#import "Bootstrap/WBVersionGate.h"
#import "Discovery/WBCapabilityRegistry.h"
#import "Discovery/WBDiagnostics.h"

NSString * const WeChatBubbleBuildStage = @"bubble-discovery";

static void WBRunBootstrap(void) {
    if (![WBProcessGuard isWeChatMainProcess]) {
        return;
    }
    NSMutableDictionary<NSString *, id> *snapshot = [@{
        @"diagnosticsFormat": @1,
        @"pluginVersion": @"0.0.2",
        @"buildStage": WeChatBubbleBuildStage,
        @"timestamp": NSDate.date,
        @"process": [WBProcessGuard snapshot],
        @"versionGate": [WBVersionGate snapshot]
    } mutableCopy];
    if ([WBVersionGate allowsDiscovery]) {
        snapshot[@"discovery"] = [WBCapabilityRegistry discoverySnapshot];
    } else {
        snapshot[@"discovery"] = @{
            @"mode": @"disabled",
            @"reason": @"unsupported-wechat-version",
            @"hookInstalled": @NO,
            @"viewTreeScanned": @NO
        };
    }
    NSError *error = nil;
    NSURL *fileURL = [WBDiagnostics writeSnapshot:snapshot error:&error];
    NSLog(@"[WeChatBubble] bootstrap=%@ diagnostics=%@", fileURL ? @"complete" : @"failed", fileURL.lastPathComponent ?: @"");
}

__attribute__((constructor))
static void WBInitialize(void) {
    @autoreleasepool {
        dispatch_async(dispatch_get_main_queue(), ^{
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    WBRunBootstrap();
                });
            });
        });
    }
}
