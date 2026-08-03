#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface WBSafeMode : NSObject

+ (void)beginLaunch;
+ (BOOL)isActive;
+ (void)markLaunchSuccessful;
+ (BOOL)prepareRecoveryForNextLaunch;
+ (NSTimeInterval)stableLaunchWindow;
+ (NSDictionary<NSString *, id> *)snapshot;

@end

NS_ASSUME_NONNULL_END
