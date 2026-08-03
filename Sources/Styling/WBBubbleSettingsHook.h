#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface WBBubbleSettingsHook : NSObject
+ (void)installIfPossible;
+ (NSDictionary<NSString *, id> *)configurationSnapshot;
@end

NS_ASSUME_NONNULL_END
