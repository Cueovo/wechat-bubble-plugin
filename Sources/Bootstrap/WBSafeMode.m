#import "WBSafeMode.h"

static NSString * const WBLaunchPendingKey = @"com.wechatbubble.safety.launchPending";
static NSString * const WBIncompleteLaunchCountKey = @"com.wechatbubble.safety.incompleteLaunchCount";
static NSString * const WBLaunchStartedAtKey = @"com.wechatbubble.safety.launchStartedAt";
static NSString * const WBLastSuccessfulLaunchKey = @"com.wechatbubble.safety.lastSuccessfulLaunch";
static NSUInteger const WBIncompleteLaunchThreshold = 3;
static NSTimeInterval const WBStableLaunchWindow = 20.0;
static BOOL WBLaunchBegan;
static BOOL WBSafeModeActive;

@implementation WBSafeMode

+ (NSUserDefaults *)defaults {
    return NSUserDefaults.standardUserDefaults;
}

+ (void)beginLaunch {
    @synchronized(self) {
        if (WBLaunchBegan) {
            return;
        }
        NSUserDefaults *defaults = [self defaults];
        NSInteger storedIncompleteLaunchCount = MAX([defaults integerForKey:WBIncompleteLaunchCountKey], 0);
        NSUInteger previousIncompleteLaunchCount = MIN((NSUInteger)storedIncompleteLaunchCount, WBIncompleteLaunchThreshold);
        NSUInteger incompleteLaunchCount = [defaults boolForKey:WBLaunchPendingKey] ? previousIncompleteLaunchCount + 1 : 0;
        WBSafeModeActive = incompleteLaunchCount >= WBIncompleteLaunchThreshold;
        [defaults setInteger:(NSInteger)incompleteLaunchCount forKey:WBIncompleteLaunchCountKey];
        [defaults setBool:YES forKey:WBLaunchPendingKey];
        [defaults setObject:NSDate.date forKey:WBLaunchStartedAtKey];
        [defaults synchronize];
        WBLaunchBegan = YES;
    }
}

+ (BOOL)isActive {
    @synchronized(self) {
        return WBSafeModeActive;
    }
}

+ (void)markLaunchSuccessful {
    @synchronized(self) {
        if (!WBLaunchBegan) {
            return;
        }
        NSUserDefaults *defaults = [self defaults];
        [defaults setBool:NO forKey:WBLaunchPendingKey];
        [defaults setInteger:0 forKey:WBIncompleteLaunchCountKey];
        [defaults removeObjectForKey:WBLaunchStartedAtKey];
        [defaults setObject:NSDate.date forKey:WBLastSuccessfulLaunchKey];
        [defaults synchronize];
    }
}

+ (BOOL)prepareRecoveryForNextLaunch {
    @synchronized(self) {
        if (!WBSafeModeActive) {
            return NO;
        }
        NSUserDefaults *defaults = [self defaults];
        [defaults setBool:NO forKey:WBLaunchPendingKey];
        [defaults setInteger:0 forKey:WBIncompleteLaunchCountKey];
        [defaults removeObjectForKey:WBLaunchStartedAtKey];
        [defaults synchronize];
        return YES;
    }
}

+ (NSTimeInterval)stableLaunchWindow {
    return WBStableLaunchWindow;
}

+ (NSDictionary<NSString *, id> *)snapshot {
    @synchronized(self) {
        NSUserDefaults *defaults = [self defaults];
        BOOL launchPending = [defaults boolForKey:WBLaunchPendingKey];
        return @{
            @"active": @(WBSafeModeActive),
            @"currentLaunchActive": @(WBSafeModeActive),
            @"nextLaunchRecoveryPrepared": @(WBSafeModeActive && !launchPending),
            @"launchPending": @(launchPending),
            @"incompleteLaunchCount": @([defaults integerForKey:WBIncompleteLaunchCountKey]),
            @"incompleteLaunchThreshold": @(WBIncompleteLaunchThreshold),
            @"stableLaunchWindowSeconds": @(WBStableLaunchWindow),
            @"launchStartedAt": [defaults objectForKey:WBLaunchStartedAtKey] ?: NSNull.null,
            @"lastSuccessfulLaunch": [defaults objectForKey:WBLastSuccessfulLaunchKey] ?: NSNull.null
        };
    }
}

@end
