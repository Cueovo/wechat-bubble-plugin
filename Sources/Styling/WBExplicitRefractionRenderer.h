#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, WBExplicitRefractionResult) {
    WBExplicitRefractionResultFailed = 0,
    WBExplicitRefractionResultPending,
    WBExplicitRefractionResultApplied
};

@interface WBExplicitRefractionRenderer : NSObject

+ (BOOL)isAvailable;
+ (NSDictionary<NSString *, id> *)capabilitySnapshot;
- (WBExplicitRefractionResult)applyToView:(UIView *)view path:(UIBezierPath *)path bounds:(CGRect)bounds;
- (void)reset;

@end

NS_ASSUME_NONNULL_END
