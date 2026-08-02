#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface WBVersionGate : NSObject

+ (BOOL)allowsDiscovery;
+ (BOOL)allowsUIModification;
+ (NSDictionary<NSString *, id> *)snapshot;

@end

NS_ASSUME_NONNULL_END
