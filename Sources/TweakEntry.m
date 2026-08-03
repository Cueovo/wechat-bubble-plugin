#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <mach-o/dyld.h>
#import "Bootstrap/WBProcessGuard.h"
#import "Bootstrap/WBVersionGate.h"
#import "Discovery/WBCapabilityRegistry.h"
#import "Discovery/WBDiagnostics.h"
#import "Styling/WBTextBubbleStyleHook.h"
#import "Styling/WBBubblePreferences.h"
#import "Styling/WBBubbleSettingsHook.h"

NSString * const WeChatBubbleBuildStage = @"preferences";

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
        @"diagnosticsFormat": @6,
        @"pluginVersion": @"0.3.0",
        @"buildStage": WeChatBubbleBuildStage,
        @"timestamp": NSDate.date,
        @"process": [WBProcessGuard snapshot],
        @"versionGate": [WBVersionGate snapshot],
        @"discovery": @{
            @"mode": @"validated",
            @"explorationHookInstalled": @NO,
            @"capabilities": [WBCapabilityRegistry discoverySnapshot],
            @"messageDataRead": @YES,
            @"messageModelMetadataRead": @YES,
            @"messageContentRead": @NO,
            @"textRead": @NO,
            @"recursiveViewTreeScanned": @YES
        },
        @"styling": styling,
        @"preferences": [WBBubblePreferences snapshot],
        @"settings": [WBBubbleSettingsHook configurationSnapshot]
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
    [WBBubbleSettingsHook installIfPossible];
    BOOL hookInstalled = [WBTextBubbleStyleHook install];
    if (hookInstalled || attempt >= 40) {
        WBRunBootstrap(hookInstalled);
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        WBAttemptInstallAndBootstrap(attempt + 1);
    });
}

static void WBImageAdded(const struct mach_header *header, intptr_t slide) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([WBVersionGate allowsUIModification]) {
            [WBBubbleSettingsHook installIfPossible];
            [WBTextBubbleStyleHook install];
        }
    });
}

__attribute__((constructor))
static void WBInitialize(void) {
    @autoreleasepool {
        if (![WBProcessGuard isWeChatMainProcess]) {
            return;
        }
        _dyld_register_func_for_add_image(WBImageAdded);
        BOOL activationAllowed = [WBVersionGate allowsUIModification];
        if (activationAllowed) {
            [WBBubbleSettingsHook installIfPossible];
        }
        BOOL hookInstalled = activationAllowed && [WBTextBubbleStyleHook install];
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
