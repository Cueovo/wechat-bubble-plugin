#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>
#import <mach-o/dyld.h>
#import "Bootstrap/WBProcessGuard.h"
#import "Bootstrap/WBSafeMode.h"
#import "Bootstrap/WBVersionGate.h"
#import "Discovery/WBCapabilityRegistry.h"
#import "Discovery/WBDiagnostics.h"
#import "Styling/WBTextBubbleStyleHook.h"
#import "Styling/WBBubblePreferences.h"
#import "Styling/WBBubbleSettingsHook.h"

NSString * const WeChatBubbleBuildStage = @"sdf-explicit-offset-circle-profile";

static BOOL WBStyleHookInstalled;
static BOOL WBStableLaunchConfirmationScheduled;
static NSUInteger WBStableLaunchConfirmationGeneration;
static NSTimeInterval WBStableForegroundStartedAt;

static BOOL WBAllowsStyling(void) {
    return [WBVersionGate allowsUIModification] && ![WBSafeMode isActive];
}

static void WBRunBootstrap(BOOL hookInstalled) {
    if (![WBProcessGuard isWeChatMainProcess]) {
        return;
    }
    BOOL versionAllowed = [WBVersionGate allowsUIModification];
    BOOL activationAllowed = versionAllowed && ![WBSafeMode isActive];
    NSMutableDictionary<NSString *, id> *styling = [[WBTextBubbleStyleHook configurationSnapshot] mutableCopy];
    styling[@"activationAllowed"] = @(activationAllowed);
    styling[@"hookInstalled"] = @(hookInstalled);
    if (!versionAllowed) {
        styling[@"mode"] = @"disabled";
        styling[@"reason"] = @"unsupported-wechat-version";
    } else if ([WBSafeMode isActive]) {
        styling[@"mode"] = @"disabled";
        styling[@"reason"] = @"safe-mode-active";
    } else if (!hookInstalled) {
        styling[@"mode"] = @"disabled";
        styling[@"reason"] = @"required-runtime-capability-missing";
    }
    NSDictionary<NSString *, id> *snapshot = @{
        @"diagnosticsFormat": @17,
        @"pluginVersion": @"0.6.4",
        @"buildStage": WeChatBubbleBuildStage,
        @"timestamp": NSDate.date,
        @"process": [WBProcessGuard snapshot],
        @"versionGate": [WBVersionGate snapshot],
        @"safety": [WBSafeMode snapshot],
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

static void WBScheduleStableLaunchConfirmation(void) {
    if (WBStableLaunchConfirmationScheduled) {
        return;
    }
    WBStableLaunchConfirmationScheduled = YES;
    WBStableForegroundStartedAt = NSProcessInfo.processInfo.systemUptime;
    NSUInteger generation = ++WBStableLaunchConfirmationGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)([WBSafeMode stableLaunchWindow] * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (generation != WBStableLaunchConfirmationGeneration) {
            return;
        }
        WBStableLaunchConfirmationScheduled = NO;
        NSTimeInterval activeDuration = NSProcessInfo.processInfo.systemUptime - WBStableForegroundStartedAt;
        if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive || activeDuration < [WBSafeMode stableLaunchWindow]) {
            return;
        }
        [WBSafeMode markLaunchSuccessful];
        WBRunBootstrap(WBStyleHookInstalled);
    });
}

static void WBCancelStableLaunchConfirmation(void) {
    WBStableLaunchConfirmationScheduled = NO;
    WBStableForegroundStartedAt = 0.0;
    WBStableLaunchConfirmationGeneration++;
}

static void WBAttemptInstallAndBootstrap(NSUInteger attempt) {
    if ([WBVersionGate allowsUIModification]) {
        [WBBubbleSettingsHook installIfPossible];
    }
    if (!WBAllowsStyling()) {
        WBRunBootstrap(NO);
        return;
    }
    WBStyleHookInstalled = [WBTextBubbleStyleHook install];
    if (WBStyleHookInstalled || attempt >= 40) {
        WBRunBootstrap(WBStyleHookInstalled);
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
        }
        if (WBAllowsStyling()) {
            WBStyleHookInstalled = [WBTextBubbleStyleHook install] || WBStyleHookInstalled;
        }
    });
}

__attribute__((constructor))
static void WBInitialize(void) {
    @autoreleasepool {
        if (![WBProcessGuard isWeChatMainProcess]) {
            return;
        }
        [WBSafeMode beginLaunch];
        _dyld_register_func_for_add_image(WBImageAdded);
        BOOL versionAllowed = [WBVersionGate allowsUIModification];
        if (versionAllowed) {
            [WBBubbleSettingsHook installIfPossible];
        }
        WBStyleHookInstalled = WBAllowsStyling() && [WBTextBubbleStyleHook install];
        dispatch_async(dispatch_get_main_queue(), ^{
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{
                [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *notification) {
                    WBScheduleStableLaunchConfirmation();
                }];
                [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *notification) {
                    WBCancelStableLaunchConfirmation();
                }];
                if (UIApplication.sharedApplication.applicationState == UIApplicationStateActive) {
                    WBScheduleStableLaunchConfirmation();
                }
                if (WBStyleHookInstalled) {
                    WBRunBootstrap(YES);
                } else {
                    WBAttemptInstallAndBootstrap(0);
                }
            });
        });
    }
}
