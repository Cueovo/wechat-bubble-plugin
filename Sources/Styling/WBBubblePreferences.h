#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const WBBubblePreferencesDidChangeNotification;

@interface WBBubblePreferences : NSObject

+ (BOOL)isEnabled;
+ (UIColor *)fillColorForOutgoing:(BOOL)outgoing;
+ (CGFloat)cornerRadius;
+ (CGFloat)borderWidth;
+ (CGFloat)opacity;
+ (NSString *)outgoingColorHex;
+ (NSString *)incomingColorHex;
+ (void)setEnabled:(BOOL)enabled;
+ (void)setOutgoingColor:(UIColor *)color;
+ (void)setIncomingColor:(UIColor *)color;
+ (void)setCornerRadius:(CGFloat)cornerRadius;
+ (void)setBorderWidth:(CGFloat)borderWidth;
+ (void)setOpacity:(CGFloat)opacity;
+ (void)reset;
+ (NSDictionary<NSString *, id> *)snapshot;

@end

NS_ASSUME_NONNULL_END
