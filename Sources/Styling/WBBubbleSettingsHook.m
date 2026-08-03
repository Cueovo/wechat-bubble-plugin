#import "WBBubbleSettingsHook.h"
#import "WBBubbleSettingsViewController.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>

static void (*WBOriginalSettingsViewDidLoad)(id, SEL);
static BOOL WBSettingsHookInstalled;
static BOOL WBSettingsEntryAvailable;
static const void *WBSettingsEntryAddedKey = &WBSettingsEntryAddedKey;

static char WBTypeCode(const char *type) {
    while (*type == 'r' || *type == 'n' || *type == 'N' || *type == 'o' || *type == 'O' || *type == 'R' || *type == 'V') {
        type++;
    }
    return *type;
}

static BOOL WBReturnMatches(Method method, char expected) {
    if (!method) {
        return NO;
    }
    char type[16] = {0};
    method_getReturnType(method, type, sizeof(type));
    return WBTypeCode(type) == expected;
}

static BOOL WBArgumentMatches(Method method, unsigned int index, char expected) {
    if (!method) {
        return NO;
    }
    char type[16] = {0};
    method_getArgumentType(method, index, type, sizeof(type));
    return WBTypeCode(type) == expected;
}

static BOOL WBIntegerArgumentMatches(Method method, unsigned int index) {
    if (!method) {
        return NO;
    }
    char type = 0;
    char encoding[16] = {0};
    method_getArgumentType(method, index, encoding, sizeof(encoding));
    type = WBTypeCode(encoding);
    return type == 'c' || type == 'C' || type == 's' || type == 'S' || type == 'i' || type == 'I' || type == 'l' || type == 'L' || type == 'q' || type == 'Q' || type == 'B';
}

static BOOL WBSettingsAPISignaturesMatch(Class cellInfoClass, Class sectionInfoClass, id tableViewInfo, SEL cellSelector, SEL sectionSelector, SEL addCellSelector, SEL addSectionSelector) {
    Method cellMethod = class_getClassMethod(cellInfoClass, cellSelector);
    Method sectionMethod = class_getClassMethod(sectionInfoClass, sectionSelector);
    Method addCellMethod = class_getInstanceMethod(sectionInfoClass, addCellSelector);
    Method addSectionMethod = class_getInstanceMethod(object_getClass(tableViewInfo), addSectionSelector);
    BOOL addCellReturnValid = WBReturnMatches(addCellMethod, 'v') || WBReturnMatches(addCellMethod, '@');
    BOOL addSectionReturnValid = WBReturnMatches(addSectionMethod, 'v') || WBReturnMatches(addSectionMethod, '@');
    return cellMethod && method_getNumberOfArguments(cellMethod) == 6 && WBReturnMatches(cellMethod, '@') && WBArgumentMatches(cellMethod, 2, ':') && WBArgumentMatches(cellMethod, 3, '@') && WBArgumentMatches(cellMethod, 4, '@') && WBIntegerArgumentMatches(cellMethod, 5) && sectionMethod && method_getNumberOfArguments(sectionMethod) == 2 && WBReturnMatches(sectionMethod, '@') && addCellMethod && method_getNumberOfArguments(addCellMethod) == 3 && addCellReturnValid && WBArgumentMatches(addCellMethod, 2, '@') && addSectionMethod && method_getNumberOfArguments(addSectionMethod) == 3 && addSectionReturnValid && WBArgumentMatches(addSectionMethod, 2, '@');
}

static id WBIvarValue(id object, NSString *name) {
    Class currentClass = object_getClass(object);
    Ivar ivar = NULL;
    while (currentClass && !ivar) {
        ivar = class_getInstanceVariable(currentClass, name.UTF8String);
        currentClass = class_getSuperclass(currentClass);
    }
    return ivar ? object_getIvar(object, ivar) : nil;
}

static void WBOpenBubbleSettings(id object, __unused SEL selector) {
    UIViewController *controller = [object isKindOfClass:UIViewController.class] ? object : nil;
    if (!controller.navigationController) {
        return;
    }
    WBBubbleSettingsViewController *settings = [[WBBubbleSettingsViewController alloc] init];
    [controller.navigationController pushViewController:settings animated:YES];
}

static BOOL WBAddSettingsEntry(id object) {
    if (objc_getAssociatedObject(object, WBSettingsEntryAddedKey)) {
        return YES;
    }
    id tableViewInfo = WBIvarValue(object, @"m_tableViewInfo");
    Class cellInfoClass = NSClassFromString(@"MMTableViewCellInfo");
    Class sectionInfoClass = NSClassFromString(@"MMTableViewSectionInfo");
    SEL cellSelector = NSSelectorFromString(@"normalCellForSel:target:title:accessoryType:");
    SEL sectionSelector = NSSelectorFromString(@"sectionInfoDefaut");
    SEL addCellSelector = NSSelectorFromString(@"addCell:");
    SEL addSectionSelector = NSSelectorFromString(@"addSection:");
    if (!tableViewInfo || ![cellInfoClass respondsToSelector:cellSelector] || ![sectionInfoClass respondsToSelector:sectionSelector] || ![tableViewInfo respondsToSelector:addSectionSelector] || !WBSettingsAPISignaturesMatch(cellInfoClass, sectionInfoClass, tableViewInfo, cellSelector, sectionSelector, addCellSelector, addSectionSelector)) {
        return NO;
    }
    id cellInfo = ((id (*)(id, SEL, SEL, id, id, NSInteger))objc_msgSend)(cellInfoClass, cellSelector, NSSelectorFromString(@"wb_openBubbleSettings"), object, @"聊天气泡", 1);
    id sectionInfo = ((id (*)(id, SEL))objc_msgSend)(sectionInfoClass, sectionSelector);
    if (!cellInfo || !sectionInfo || ![sectionInfo respondsToSelector:addCellSelector]) {
        return NO;
    }
    ((void (*)(id, SEL, id))objc_msgSend)(sectionInfo, addCellSelector, cellInfo);
    ((void (*)(id, SEL, id))objc_msgSend)(tableViewInfo, addSectionSelector, sectionInfo);
    objc_setAssociatedObject(object, WBSettingsEntryAddedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return YES;
}

static void WBSettingsViewDidLoadHook(id object, SEL selector) {
    if (WBOriginalSettingsViewDidLoad) {
        WBOriginalSettingsViewDidLoad(object, selector);
    }
    WBSettingsEntryAvailable = WBAddSettingsEntry(object);
}

@implementation WBBubbleSettingsHook

+ (void)installIfPossible {
    @synchronized(self) {
        if (WBSettingsHookInstalled) {
            return;
        }
        Class settingsClass = NSClassFromString(@"NewSettingViewController");
        SEL openSelector = NSSelectorFromString(@"wb_openBubbleSettings");
        SEL viewDidLoadSelector = @selector(viewDidLoad);
        if (!settingsClass || !class_getInstanceMethod(settingsClass, viewDidLoadSelector)) {
            return;
        }
        if (![settingsClass instancesRespondToSelector:openSelector]) {
            class_addMethod(settingsClass, openSelector, (IMP)WBOpenBubbleSettings, "v@:");
        }
        MSHookMessageEx(settingsClass, viewDidLoadSelector, (IMP)WBSettingsViewDidLoadHook, (IMP *)&WBOriginalSettingsViewDidLoad);
        WBSettingsHookInstalled = WBOriginalSettingsViewDidLoad != NULL;
    }
}

+ (NSDictionary<NSString *, id> *)configurationSnapshot {
    return @{
        @"targetClassAvailable": @(NSClassFromString(@"NewSettingViewController") != Nil),
        @"hookInstalled": @(WBSettingsHookInstalled),
        @"entryAvailable": @(WBSettingsEntryAvailable)
    };
}

@end
