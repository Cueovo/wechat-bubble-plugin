#import "WBBubbleSettingsHook.h"
#import "WBBubbleSettingsViewController.h"
#import "../Discovery/WBDiagnostics.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>

static void (*WBOriginalSettingsLifecycle)(id, SEL);
static BOOL WBSettingsHookInstalled;
static BOOL WBSettingsEntryAvailable;
static BOOL WBSettingsEntryModelAdded;
static BOOL WBSettingsTableInfoAvailable;
static BOOL WBSettingsAPISignaturesValid;
static BOOL WBSettingsTableReloaded;
static BOOL WBSettingsHookUsesReloadTableData;
static NSString *WBSettingsLifecycleName = @"unavailable";
static NSString *WBSettingsEntryReason = @"not-attempted";
static const void *WBSettingsEntryAddedKey = &WBSettingsEntryAddedKey;
static const void *WBSettingsLifecycleInProgressKey = &WBSettingsLifecycleInProgressKey;

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
    char encoding[16] = {0};
    method_getArgumentType(method, index, encoding, sizeof(encoding));
    char type = WBTypeCode(encoding);
    return type == 'c' || type == 'C' || type == 's' || type == 'S' || type == 'i' || type == 'I' || type == 'l' || type == 'L' || type == 'q' || type == 'Q' || type == 'B';
}

static BOOL WBNoArgumentVoidMethodMatches(Method method) {
    return method && method_getNumberOfArguments(method) == 2 && WBReturnMatches(method, 'v') && WBArgumentMatches(method, 0, '@') && WBArgumentMatches(method, 1, ':');
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

static void WBSendObjectArgument(id target, SEL selector, id argument, Method method) {
    if (WBReturnMatches(method, '@')) {
        ((id (*)(id, SEL, id))objc_msgSend)(target, selector, argument);
    } else {
        ((void (*)(id, SEL, id))objc_msgSend)(target, selector, argument);
    }
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

static BOOL WBReloadSettingsTable(id object, id tableViewInfo) {
    id tableView = WBIvarValue(object, @"m_tableView");
    SEL getTableViewSelector = NSSelectorFromString(@"getTableView");
    Method getTableViewMethod = class_getInstanceMethod(object_getClass(tableViewInfo), getTableViewSelector);
    if (![tableView respondsToSelector:@selector(reloadData)] && getTableViewMethod && method_getNumberOfArguments(getTableViewMethod) == 2 && WBReturnMatches(getTableViewMethod, '@') && WBArgumentMatches(getTableViewMethod, 0, '@') && WBArgumentMatches(getTableViewMethod, 1, ':')) {
        tableView = ((id (*)(id, SEL))objc_msgSend)(tableViewInfo, getTableViewSelector);
    }
    if (![tableView respondsToSelector:@selector(reloadData)]) {
        return NO;
    }
    ((void (*)(id, SEL))objc_msgSend)(tableView, @selector(reloadData));
    return YES;
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
    if (!WBSettingsHookUsesReloadTableData && objc_getAssociatedObject(object, WBSettingsEntryAddedKey)) {
        WBSettingsEntryReason = @"already-added";
        return YES;
    }
    WBSettingsEntryAvailable = NO;
    WBSettingsEntryModelAdded = NO;
    WBSettingsTableInfoAvailable = NO;
    WBSettingsAPISignaturesValid = NO;
    WBSettingsTableReloaded = NO;
    id tableViewInfo = WBIvarValue(object, @"m_tableViewInfo");
    WBSettingsTableInfoAvailable = tableViewInfo != nil;
    if (!tableViewInfo) {
        WBSettingsEntryReason = @"table-info-unavailable";
        return NO;
    }
    Class cellInfoClass = NSClassFromString(@"MMTableViewCellInfo");
    Class sectionInfoClass = NSClassFromString(@"MMTableViewSectionInfo");
    SEL cellSelector = NSSelectorFromString(@"normalCellForSel:target:title:accessoryType:");
    SEL sectionSelector = NSSelectorFromString(@"sectionInfoDefaut");
    SEL addCellSelector = NSSelectorFromString(@"addCell:");
    SEL addSectionSelector = NSSelectorFromString(@"addSection:");
    WBSettingsAPISignaturesValid = [cellInfoClass respondsToSelector:cellSelector] && [sectionInfoClass respondsToSelector:sectionSelector] && [tableViewInfo respondsToSelector:addSectionSelector] && WBSettingsAPISignaturesMatch(cellInfoClass, sectionInfoClass, tableViewInfo, cellSelector, sectionSelector, addCellSelector, addSectionSelector);
    if (!WBSettingsAPISignaturesValid) {
        WBSettingsEntryReason = @"private-api-signature-mismatch";
        return NO;
    }
    id cellInfo = ((id (*)(id, SEL, SEL, id, id, NSInteger))objc_msgSend)(cellInfoClass, cellSelector, NSSelectorFromString(@"wb_openBubbleSettings"), object, @"聊天气泡", UITableViewCellAccessoryDisclosureIndicator);
    id sectionInfo = ((id (*)(id, SEL))objc_msgSend)(sectionInfoClass, sectionSelector);
    if (!cellInfo || !sectionInfo || ![sectionInfo respondsToSelector:addCellSelector]) {
        WBSettingsEntryReason = @"entry-model-creation-failed";
        return NO;
    }
    Method addCellMethod = class_getInstanceMethod(sectionInfoClass, addCellSelector);
    Method addSectionMethod = class_getInstanceMethod(object_getClass(tableViewInfo), addSectionSelector);
    WBSendObjectArgument(sectionInfo, addCellSelector, cellInfo, addCellMethod);
    WBSendObjectArgument(tableViewInfo, addSectionSelector, sectionInfo, addSectionMethod);
    WBSettingsEntryModelAdded = YES;
    WBSettingsEntryAvailable = YES;
    WBSettingsTableReloaded = WBReloadSettingsTable(object, tableViewInfo);
    WBSettingsEntryReason = WBSettingsTableReloaded ? @"entry-model-added-table-reloaded" : @"entry-model-added-table-unavailable";
    objc_setAssociatedObject(object, WBSettingsEntryAddedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return WBSettingsEntryAvailable;
}

static NSDictionary<NSString *, id> *WBSettingsConfigurationSnapshot(void) {
    return @{
        @"targetClassAvailable": @(NSClassFromString(@"NewSettingViewController") != Nil),
        @"hookInstalled": @(WBSettingsHookInstalled),
        @"lifecycleSelector": WBSettingsLifecycleName,
        @"entryAvailable": @(WBSettingsEntryAvailable),
        @"entryModelAdded": @(WBSettingsEntryModelAdded),
        @"visibilityVerified": @NO,
        @"tableInfoAvailable": @(WBSettingsTableInfoAvailable),
        @"apiSignaturesValid": @(WBSettingsAPISignaturesValid),
        @"tableReloaded": @(WBSettingsTableReloaded),
        @"reason": WBSettingsEntryReason
    };
}

static void WBRecordSettingsDiagnostics(void) {
    NSError *error = nil;
    BOOL updated = [WBDiagnostics updateSettings:WBSettingsConfigurationSnapshot() error:&error];
    NSLog(@"[WeChatBubble] settings-entry=%@ diagnostics=%@", WBSettingsEntryReason, updated ? @"updated" : @"failed");
}

static void WBSettingsLifecycleHook(id object, SEL selector) {
    if (objc_getAssociatedObject(object, WBSettingsLifecycleInProgressKey)) {
        if (WBOriginalSettingsLifecycle) {
            WBOriginalSettingsLifecycle(object, selector);
        }
        return;
    }
    objc_setAssociatedObject(object, WBSettingsLifecycleInProgressKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (WBOriginalSettingsLifecycle) {
        WBOriginalSettingsLifecycle(object, selector);
    }
    WBAddSettingsEntry(object);
    WBRecordSettingsDiagnostics();
    objc_setAssociatedObject(object, WBSettingsLifecycleInProgressKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@implementation WBBubbleSettingsHook

+ (void)installIfPossible {
    @synchronized(self) {
        if (WBSettingsHookInstalled) {
            return;
        }
        Class settingsClass = NSClassFromString(@"NewSettingViewController");
        SEL openSelector = NSSelectorFromString(@"wb_openBubbleSettings");
        SEL reloadSelector = NSSelectorFromString(@"reloadTableData");
        SEL viewDidLoadSelector = @selector(viewDidLoad);
        Method reloadMethod = settingsClass ? class_getInstanceMethod(settingsClass, reloadSelector) : NULL;
        Method viewDidLoadMethod = settingsClass ? class_getInstanceMethod(settingsClass, viewDidLoadSelector) : NULL;
        SEL lifecycleSelector = WBNoArgumentVoidMethodMatches(reloadMethod) ? reloadSelector : viewDidLoadSelector;
        Method lifecycleMethod = settingsClass ? class_getInstanceMethod(settingsClass, lifecycleSelector) : NULL;
        if (!settingsClass || !WBNoArgumentVoidMethodMatches(lifecycleMethod)) {
            WBSettingsEntryReason = @"lifecycle-unavailable";
            return;
        }
        if (![settingsClass instancesRespondToSelector:openSelector] && !class_addMethod(settingsClass, openSelector, (IMP)WBOpenBubbleSettings, "v@:")) {
            WBSettingsEntryReason = @"open-selector-install-failed";
            return;
        }
        WBSettingsHookUsesReloadTableData = lifecycleSelector == reloadSelector;
        WBSettingsLifecycleName = NSStringFromSelector(lifecycleSelector);
        MSHookMessageEx(settingsClass, lifecycleSelector, (IMP)WBSettingsLifecycleHook, (IMP *)&WBOriginalSettingsLifecycle);
        WBSettingsHookInstalled = WBOriginalSettingsLifecycle != NULL;
        WBSettingsEntryReason = WBSettingsHookInstalled ? @"waiting-for-settings-screen" : @"hook-install-failed";
    }
}

+ (NSDictionary<NSString *, id> *)configurationSnapshot {
    return WBSettingsConfigurationSnapshot();
}

@end
