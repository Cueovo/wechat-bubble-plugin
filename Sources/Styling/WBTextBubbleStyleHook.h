#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface WBTextBubbleStyleHook : NSObject

+ (BOOL)install;
+ (NSDictionary<NSString *, id> *)configurationSnapshot;

@end

NS_ASSUME_NONNULL_END
