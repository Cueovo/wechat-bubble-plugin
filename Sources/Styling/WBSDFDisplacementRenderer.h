#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, WBSDFApplicationResult) {
    WBSDFApplicationResultFailed = 0,
    WBSDFApplicationResultPending,
    WBSDFApplicationResultApplied
};

@interface WBSDFDisplacementRenderer : NSObject

+ (BOOL)isAvailable;
+ (NSDictionary<NSString *, id> *)capabilitySnapshot;

- (WBSDFApplicationResult)applyToEffectView:(UIVisualEffectView *)effectView path:(UIBezierPath *)path bounds:(CGRect)bounds cacheKey:(NSString *)cacheKey;
- (BOOL)requiresFilterReapplication;
- (void)reset;

@end

NS_ASSUME_NONNULL_END
