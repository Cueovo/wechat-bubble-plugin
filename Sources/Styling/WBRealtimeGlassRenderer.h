#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, WBRealtimeGlassResult) {
    WBRealtimeGlassResultFailed = 0,
    WBRealtimeGlassResultPending = 1,
    WBRealtimeGlassResultApplied = 2
};

@interface WBRealtimeGlassRenderer : NSObject

+ (BOOL)isAvailable;
+ (NSDictionary<NSString *, id> *)capabilitySnapshot;
@property (nonatomic, copy, nullable) void (^renderStateDidChange)(BOOL active);
- (WBRealtimeGlassResult)applyToView:(UIView *)view path:(UIBezierPath *)path bounds:(CGRect)bounds;
- (void)reset;

@end

NS_ASSUME_NONNULL_END
