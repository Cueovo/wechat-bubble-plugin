#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "WBBubbleThemeProvider.h"

NS_ASSUME_NONNULL_BEGIN

@interface WBBubbleStyler : NSObject

+ (BOOL)applyToBubbleView:(UIView *)bubbleView direction:(WBBubbleDirection)direction;
+ (void)removeFromBubbleView:(UIView *)bubbleView;

@end

NS_ASSUME_NONNULL_END
