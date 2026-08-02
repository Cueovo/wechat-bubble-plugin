#import "WBCapabilityRegistry.h"
#import <objc/runtime.h>

@implementation WBCapabilityRegistry

+ (NSDictionary<NSString *, NSNumber *> *)selectorAvailabilityForClass:(Class)candidateClass names:(NSArray<NSString *> *)names {
    NSMutableDictionary<NSString *, NSNumber *> *availability = [NSMutableDictionary dictionary];
    for (NSString *name in names) {
        availability[name] = @([candidateClass instancesRespondToSelector:NSSelectorFromString(name)]);
    }
    return availability;
}

+ (NSDictionary<NSString *, id> *)snapshotForClassName:(NSString *)className {
    Class candidateClass = NSClassFromString(className);
    if (!candidateClass) {
        return @{@"available": @NO};
    }
    Class superclass = class_getSuperclass(candidateClass);
    NSMutableDictionary<NSString *, id> *snapshot = [@{
        @"available": @YES,
        @"superclass": superclass ? NSStringFromClass(superclass) : @""
    } mutableCopy];
    if ([className isEqualToString:@"TextMessageCellView"]) {
        snapshot[@"requiredSelectors"] = [self selectorAvailabilityForClass:candidateClass names:@[
            @"layoutContentView",
            @"getBgImageView",
            @"getRichTextView",
            @"getHeadImageView"
        ]];
    }
    return snapshot;
}

+ (NSDictionary<NSString *, id> *)discoverySnapshot {
    NSArray<NSString *> *candidateNames = @[
        @"CommonMessageCellView",
        @"ChatTableViewCell",
        @"BaseChatCellView",
        @"TextMessageCellView"
    ];
    NSMutableDictionary<NSString *, id> *classes = [NSMutableDictionary dictionary];
    for (NSString *className in candidateNames) {
        classes[className] = [self snapshotForClassName:className];
    }
    return @{
        @"mode": @"required-runtime-capability-check",
        @"candidateClasses": classes,
        @"hookInstalled": @NO,
        @"recursiveViewTreeScanned": @NO
    };
}

@end
