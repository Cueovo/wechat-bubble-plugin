#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const WBBubblePreferencesDidChangeNotification;

typedef NS_ENUM(NSInteger, WBBubbleMaterial) {
    WBBubbleMaterialSolid = 0,
    WBBubbleMaterialGlass
};

@interface WBBubblePreferences : NSObject

+ (BOOL)isEnabled;
+ (WBBubbleMaterial)material;
+ (NSString *)materialIdentifier;
+ (UIColor *)fillColorForOutgoing:(BOOL)outgoing dark:(BOOL)dark;
+ (UIColor *)borderColorForOutgoing:(BOOL)outgoing dark:(BOOL)dark;
+ (NSString *)fillColorHexForOutgoing:(BOOL)outgoing dark:(BOOL)dark;
+ (NSString *)borderColorHexForOutgoing:(BOOL)outgoing dark:(BOOL)dark;
+ (CGFloat)cornerRadius;
+ (CGFloat)borderWidth;
+ (CGFloat)opacity;
+ (void)setEnabled:(BOOL)enabled;
+ (void)setMaterial:(WBBubbleMaterial)material;
+ (void)setFillColor:(UIColor *)color outgoing:(BOOL)outgoing dark:(BOOL)dark;
+ (void)setBorderColor:(UIColor *)color outgoing:(BOOL)outgoing dark:(BOOL)dark;
+ (void)setCornerRadius:(CGFloat)cornerRadius;
+ (void)setBorderWidth:(CGFloat)borderWidth;
+ (void)setOpacity:(CGFloat)opacity;
+ (void)reset;
+ (NSDictionary<NSString *, id> *)snapshot;

@end

NS_ASSUME_NONNULL_END
