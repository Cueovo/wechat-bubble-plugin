#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface WBDiagnostics : NSObject

+ (nullable NSURL *)writeSnapshot:(NSDictionary<NSString *, id> *)snapshot error:(NSError **)error;
+ (BOOL)updateDiscovery:(NSDictionary<NSString *, id> *)update error:(NSError **)error;
+ (BOOL)updateStyling:(NSDictionary<NSString *, id> *)update error:(NSError **)error;
+ (BOOL)updateSettings:(NSDictionary<NSString *, id> *)update error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
