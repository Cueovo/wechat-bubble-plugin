#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import "Bootstrap/WBProcessGuard.h"
#import "Bootstrap/WBVersionGate.h"
#import "Discovery/WBCapabilityRegistry.h"
#import "Discovery/WBDiagnostics.h"
#import "Styling/WBTextBubbleStyleHook.h"

NSString * const WeChatBubbleBuildStage = @"text-bubble-core";

static void WBRunBootstrap(BOOL hookInstalled) {
    if (![WBProcessGuard isWeChatMainProcess]) {
        return;
    }
    BOOL activationAllowed = [WBVersionGate allowsUIModification];
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
        @"pluginVersion": @"0.1.1",
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

static void WBAttemptInstallAndBootstrap(NSUInteger attempt) {
    if (![WBVersionGate allowsUIModification]) {
        WBRunBootstrap(NO);
        return;
    }
    BOOL hookInstalled = [WBTextBubbleStyleHook install];
    if (hookInstalled || attempt >= 5) {
        WBRunBootstrap(hookInstalled);
        return;
    }
    static const NSTimeInterval delays[] = {0.05, 0.1, 0.2, 0.4, 0.8};
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delays[attempt] * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        WBAttemptInstallAndBootstrap(attempt + 1);
    });
}

__attribute__((constructor))
static void WBInitialize(void) {
    @autoreleasepool {
        if (![WBProcessGuard isWeChatMainProcess]) {
            return;
        }
        BOOL hookInstalled = [WBVersionGate allowsUIModification] && [WBTextBubbleStyleHook install];
        dispatch_async(dispatch_get_main_queue(), ^{
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{
                if (hookInstalled) {
                    WBRunBootstrap(YES);
                } else {
                    WBAttemptInstallAndBootstrap(0);
                }
            });
        });
    }
}
