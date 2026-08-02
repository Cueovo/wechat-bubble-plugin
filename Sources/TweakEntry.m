#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import "Bootstrap/WBProcessGuard.h"
#import "Bootstrap/WBVersionGate.h"
#import "Discovery/WBCapabilityRegistry.h"
#import "Discovery/WBDiagnostics.h"
#import "Styling/WBTextBubbleStyleHook.h"

NSString * const WeChatBubbleBuildStage = @"text-bubble-core";

static void WBRunBootstrap(void) {
    if (![WBProcessGuard isWeChatMainProcess]) {
        return;
    }
    BOOL activationAllowed = [WBVersionGate allowsUIModification];
    BOOL hookInstalled = activationAllowed && [WBTextBubbleStyleHook install];
    NSMutableDictionary<NSString *, id> *styling = [[WBTextBubbleStyleHook configurationSnapshot] mutableCopy];
    styling[@"activationAllowed"] = @(activationAllowed);
    styling[@"hookInstalled"] = @(hookInstalled);
    if (!activationAllowed) {
        styling[@"mode"] = @"disabled";
        styling[@"reason"] = @"unsupported-wechat-version";
    } else if (!hookInstalled) {
        styling[@"mode"] = @"disabled";
        styling[@"reason"] = @"required-runtime-capability-missing";
    }
    NSDictionary<NSString *, id> *snapshot = @{
        @"diagnosticsFormat": @4,
        @"pluginVersion": @"0.1.0",
        @"buildStage": WeChatBubbleBuildStage,
        @"timestamp": NSDate.date,
        @"process": [WBProcessGuard snapshot],
        @"versionGate": [WBVersionGate snapshot],
        @"discovery": @{
            @"mode": @"validated",
            @"explorationHookInstalled": @NO,
            @"capabilities": [WBCapabilityRegistry discoverySnapshot],
            @"messageDataRead": @NO,
            @"textRead": @NO,
            @"recursiveViewTreeScanned": @NO
        },
        @"styling": styling
    };
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
