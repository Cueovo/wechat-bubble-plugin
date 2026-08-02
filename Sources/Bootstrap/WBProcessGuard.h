#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface WBProcessGuard : NSObject

+ (BOOL)isWeChatMainProcess;
+ (NSDictionary<NSString *, id> *)snapshot;

@end

NS_ASSUME_NONNULL_END
