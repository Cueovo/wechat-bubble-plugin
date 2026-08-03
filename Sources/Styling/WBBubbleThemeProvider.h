#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, WBBubbleDirection) {
    WBBubbleDirectionUnknown = 0,
    WBBubbleDirectionIncoming,
    WBBubbleDirectionOutgoing
};

@interface WBBubbleThemeProvider : NSObject

+ (BOOL)isEnabled;
+ (BOOL)usesGlassMaterial;
+ (BOOL)nativeLiquidGlassAvailable;
+ (void)disableNativeLiquidGlassForProcess;
+ (BOOL)realtimeMetalAvailable;
+ (NSDictionary<NSString *, id> *)glassCapabilitySnapshot;
+ (NSString *)materialIdentifier;
+ (NSString *)resolvedMaterialBackend;
+ (NSString *)themeIdentifier;
+ (UIColor *)fillColorForDirection:(WBBubbleDirection)direction traitCollection:(UITraitCollection *)traitCollection;
+ (UIColor *)borderColorForDirection:(WBBubbleDirection)direction traitCollection:(UITraitCollection *)traitCollection;
+ (CGFloat)fillOpacity;
+ (CGFloat)cornerRadius;
+ (CGFloat)borderWidth;

@end

NS_ASSUME_NONNULL_END
