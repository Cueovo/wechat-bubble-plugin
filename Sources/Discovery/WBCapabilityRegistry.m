#import "WBCapabilityRegistry.h"
#import <objc/runtime.h>
#import <stdlib.h>

@implementation WBCapabilityRegistry

+ (BOOL)isRelevantSelectorName:(NSString *)name {
    NSString *lowercaseName = name.lowercaseString;
    for (NSString *term in @[@"layout", @"config", @"update", @"reload", @"cell", @"view", @"message"]) {
        if ([lowercaseName containsString:term]) {
            return YES;
        }
    }
    return NO;
}

+ (NSArray<NSString *> *)relevantMethodsForClass:(Class)candidateClass {
    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(candidateClass, &methodCount);
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (unsigned int index = 0; index < methodCount && names.count < 80; index++) {
        NSString *name = NSStringFromSelector(method_getName(methods[index]));
        if ([self isRelevantSelectorName:name]) {
            [names addObject:name];
        }
    }
    free(methods);
    [names sortUsingSelector:@selector(compare:)];
    return names;
}

+ (NSDictionary<NSString *, id> *)snapshotForClassName:(NSString *)className {
    Class candidateClass = NSClassFromString(className);
    if (!candidateClass) {
        return @{@"available": @NO};
    }
    Class superclass = class_getSuperclass(candidateClass);
    return @{
        @"available": @YES,
        @"superclass": superclass ? NSStringFromClass(superclass) : @"",
        @"relevantInstanceMethods": [self relevantMethodsForClass:candidateClass]
    };
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
        @"mode": @"read-only-runtime-capability-scan",
        @"candidateClasses": classes,
        @"hookInstalled": @NO,
        @"recursiveViewTreeScanned": @NO
    };
}

@end
