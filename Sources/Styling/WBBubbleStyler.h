#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "WBBubbleThemeProvider.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, WBBubbleTailSide) {
    WBBubbleTailSideLeft = 0,
    WBBubbleTailSideRight
};

typedef NS_ENUM(NSInteger, WBBubbleSegmentPosition) {
    WBBubbleSegmentPositionSingle = 0,
    WBBubbleSegmentPositionTop,
    WBBubbleSegmentPositionMiddle,
    WBBubbleSegmentPositionBottom
};

@interface WBBubbleStyler : NSObject

+ (BOOL)applyToBubbleView:(UIView *)bubbleView direction:(WBBubbleDirection)direction tailSide:(WBBubbleTailSide)tailSide segmentPosition:(WBBubbleSegmentPosition)segmentPosition;
+ (BOOL)captureArtworkUpdate:(nullable id)artwork forBubbleView:(UIView *)bubbleView animated:(BOOL)animated;
+ (void)removeFromBubbleView:(UIView *)bubbleView;

@end

NS_ASSUME_NONNULL_END
