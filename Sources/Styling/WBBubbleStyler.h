#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "WBBubbleThemeProvider.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, WBBubbleTailSide) {
    WBBubbleTailSideLeft = 0,
    WBBubbleTailSideRight
};

@interface WBBubbleStyler : NSObject

+ (BOOL)applyToBubbleView:(UIView *)bubbleView direction:(WBBubbleDirection)direction tailSide:(WBBubbleTailSide)tailSide;
+ (void)removeFromBubbleView:(UIView *)bubbleView;

@end

NS_ASSUME_NONNULL_END
