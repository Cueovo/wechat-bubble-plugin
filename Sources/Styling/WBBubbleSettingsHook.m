#import "WBBubbleSettingsHook.h"
#import "WBBubbleSettingsViewController.h"
#import "../Discovery/WBDiagnostics.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>

static void (*WBOriginalSettingsReload)(id, SEL);
static void (*WBOriginalSettingsWillAppear)(id, SEL);
static void (*WBOriginalSettingsViewWillAppear)(id, SEL, BOOL);
static void (*WBOriginalSettingsViewDidLoad)(id, SEL);
static BOOL WBSettingsHookInstalled;
static BOOL WBSettingsEntryAvailable;
static BOOL WBSettingsEntryModelAdded;
static BOOL WBSettingsTableInfoAvailable;
static BOOL WBSettingsTableManagerAvailable;
static BOOL WBSettingsAPISignaturesValid;
static BOOL WBSettingsTableReloaded;
static BOOL WBSettingsHookUsesReloadTableData;
static BOOL WBSettingsPluginsManagerAvailable;
static BOOL WBSettingsPluginsPortalAvailable;
static BOOL WBSettingsPluginsPortalRegistered;
static BOOL WBSettingsPluginsPortalDidRegister;
static BOOL WBSettingsDuplicateEntryFound;
static NSString *WBSettingsLifecycleName = @"unavailable";
static NSString *WBSettingsLastLifecycleName = @"not-invoked";
static NSString *WBSettingsModelPath = @"unavailable";
static NSString *WBSettingsInsertionMethod = @"none";
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

static BOOL WBNoArgumentObjectMethodMatches(Method method) {
    return method && method_getNumberOfArguments(method) == 2 && WBReturnMatches(method, '@') && WBArgumentMatches(method, 0, '@') && WBArgumentMatches(method, 1, ':');
}

static BOOL WBNoArgumentVoidMethodMatches(Method method) {
    return method && method_getNumberOfArguments(method) == 2 && WBReturnMatches(method, 'v') && WBArgumentMatches(method, 0, '@') && WBArgumentMatches(method, 1, ':');
}

static BOOL WBBooleanArgumentVoidMethodMatches(Method method) {
    return method && method_getNumberOfArguments(method) == 3 && WBReturnMatches(method, 'v') && WBArgumentMatches(method, 0, '@') && WBArgumentMatches(method, 1, ':') && WBIntegerArgumentMatches(method, 2);
}

static BOOL WBObjectArgumentMethodMatches(Method method) {
    BOOL returnValid = WBReturnMatches(method, 'v') || WBReturnMatches(method, '@');
    return method && method_getNumberOfArguments(method) == 3 && returnValid && WBArgumentMatches(method, 0, '@') && WBArgumentMatches(method, 1, ':') && WBArgumentMatches(method, 2, '@');
}

static BOOL WBCellFactoryMethodMatches(Method method) {
    return method && method_getNumberOfArguments(method) == 6 && WBReturnMatches(method, '@') && WBArgumentMatches(method, 0, '@') && WBArgumentMatches(method, 1, ':') && WBArgumentMatches(method, 2, ':') && WBArgumentMatches(method, 3, '@') && WBArgumentMatches(method, 4, '@') && WBIntegerArgumentMatches(method, 5);
}

static void WBSendObjectArgument(id target, SEL selector, id argument, Method method) {
    if (WBReturnMatches(method, '@')) {
        ((id (*)(id, SEL, id))objc_msgSend)(target, selector, argument);
    } else {
        ((void (*)(id, SEL, id))objc_msgSend)(target, selector, argument);
    }
}

static void WBSendObjectIntegerArguments(id target, SEL selector, id argument, unsigned int index, Method method) {
    if (WBReturnMatches(method, '@')) {
        ((id (*)(id, SEL, id, unsigned int))objc_msgSend)(target, selector, argument, index);
    } else {
        ((void (*)(id, SEL, id, unsigned int))objc_msgSend)(target, selector, argument, index);
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

static id WBSafeValueForKey(id object, NSString *key) {
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static id WBObjectFromNoArgumentSelector(id object, SEL selector) {
    Method method = class_getInstanceMethod(object_getClass(object), selector);
    return WBNoArgumentObjectMethodMatches(method) ? ((id (*)(id, SEL))objc_msgSend)(object, selector) : nil;
}

static NSArray *WBSettingsSections(id tableManager) {
    id sections = WBObjectFromNoArgumentSelector(tableManager, NSSelectorFromString(@"getAllSections"));
    if (![sections isKindOfClass:NSArray.class]) {
        sections = WBSafeValueForKey(tableManager, @"sections");
    }
    return [sections isKindOfClass:NSArray.class] ? sections : nil;
}

static NSArray *WBSettingsCells(id section) {
    id cells = WBObjectFromNoArgumentSelector(section, NSSelectorFromString(@"getAllCells"));
    if (![cells isKindOfClass:NSArray.class]) {
        cells = WBSafeValueForKey(section, @"cells");
    }
    return [cells isKindOfClass:NSArray.class] ? cells : nil;
}

static NSString *WBSettingsCellTitle(id cell) {
    id cellConfig = WBSafeValueForKey(cell, @"cellConfig");
    id leftConfig = WBSafeValueForKey(cellConfig, @"leftConfig");
    id title = WBSafeValueForKey(leftConfig, @"title");
    return [title isKindOfClass:NSString.class] ? [title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : nil;
}

static BOOL WBTableManagerContainsTitle(id tableManager, NSSet<NSString *> *titles) {
    for (id section in WBSettingsSections(tableManager)) {
        for (id cell in WBSettingsCells(section)) {
            NSString *title = WBSettingsCellTitle(cell);
            if (title.length > 0 && [titles containsObject:title]) {
                return YES;
            }
        }
    }
    return NO;
}

static BOOL WBReloadSettingsTable(id object, id tableModel) {
    id tableView = WBIvarValue(object, @"m_tableView");
    if (![tableView respondsToSelector:@selector(reloadData)]) {
        tableView = WBObjectFromNoArgumentSelector(tableModel, NSSelectorFromString(@"getTableView"));
    }
    if (![tableView respondsToSelector:@selector(reloadData)]) {
        return NO;
    }
    ((void (*)(id, SEL))objc_msgSend)(tableView, @selector(reloadData));
    return YES;
}

static void WBOpenBubbleSettings(id object, __unused SEL selector) {
    id navigationController = WBSafeValueForKey(object, @"navigationController");
    if (![navigationController respondsToSelector:@selector(pushViewController:animated:)]) {
        return;
    }
    WBBubbleSettingsViewController *settings = [[WBBubbleSettingsViewController alloc] init];
    ((void (*)(id, SEL, id, BOOL))objc_msgSend)(navigationController, @selector(pushViewController:animated:), settings, YES);
}

static void WBResetSettingsEntryState(void) {
    WBSettingsEntryAvailable = NO;
    WBSettingsEntryModelAdded = NO;
    WBSettingsTableInfoAvailable = NO;
    WBSettingsTableManagerAvailable = NO;
    WBSettingsAPISignaturesValid = NO;
    WBSettingsTableReloaded = NO;
    WBSettingsPluginsManagerAvailable = NO;
    WBSettingsPluginsPortalAvailable = NO;
    WBSettingsPluginsPortalRegistered = NO;
    WBSettingsDuplicateEntryFound = NO;
    WBSettingsModelPath = @"unavailable";
    WBSettingsInsertionMethod = @"none";
}

static void WBMarkPluginsRegistration(NSString *reason) {
    WBSettingsPluginsPortalRegistered = YES;
    WBSettingsEntryAvailable = YES;
    WBSettingsAPISignaturesValid = YES;
    WBSettingsModelPath = @"WCPluginsMgr";
    WBSettingsInsertionMethod = @"registerControllerWithTitle:version:controller:";
    WBSettingsEntryReason = reason;
}

static BOOL WBRegisterWithPluginsManager(void) {
    Class managerClass = NSClassFromString(@"WCPluginsMgr");
    SEL sharedSelector = NSSelectorFromString(@"sharedInstance");
    SEL registerSelector = NSSelectorFromString(@"registerControllerWithTitle:version:controller:");
    Method sharedMethod = managerClass ? class_getClassMethod(managerClass, sharedSelector) : NULL;
    WBSettingsPluginsManagerAvailable = NO;
    if (!WBNoArgumentObjectMethodMatches(sharedMethod)) {
        return NO;
    }
    if (WBSettingsPluginsPortalDidRegister) {
        WBSettingsPluginsManagerAvailable = YES;
        WBMarkPluginsRegistration(@"already-registered-with-plugins-manager");
        return YES;
    }
    id manager = nil;
    @try {
        manager = ((id (*)(id, SEL))objc_msgSend)(managerClass, sharedSelector);
    } @catch (__unused NSException *exception) {
        return NO;
    }
    Method registerMethod = manager ? class_getInstanceMethod(object_getClass(manager), registerSelector) : NULL;
    if (!registerMethod || method_getNumberOfArguments(registerMethod) != 5 || !WBReturnMatches(registerMethod, 'v') || !WBArgumentMatches(registerMethod, 0, '@') || !WBArgumentMatches(registerMethod, 1, ':') || !WBArgumentMatches(registerMethod, 2, '@') || !WBArgumentMatches(registerMethod, 3, '@') || !WBArgumentMatches(registerMethod, 4, '@')) {
        return NO;
    }
    WBSettingsPluginsManagerAvailable = YES;
    @try {
        ((void (*)(id, SEL, id, id, id))objc_msgSend)(manager, registerSelector, @"聊天气泡", @"0.6.2", NSStringFromClass(WBBubbleSettingsViewController.class));
    } @catch (__unused NSException *exception) {
        WBSettingsPluginsManagerAvailable = NO;
        return NO;
    }
    WBSettingsPluginsPortalDidRegister = YES;
    WBMarkPluginsRegistration(@"registered-with-plugins-manager");
    return YES;
}

static BOOL WBRegisterPluginsPortal(id object, id tableManager) {
    NSSet<NSString *> *portalTitles = [NSSet setWithObjects:@"插件", @"插件管理", nil];
    WBSettingsPluginsPortalAvailable = WBIvarValue(object, @"_pluginCellInfo") != nil || WBTableManagerContainsTitle(tableManager, portalTitles);
    return WBRegisterWithPluginsManager();
}

static BOOL WBAddModernSettingsEntry(id object, id tableManager) {
    Class cellClass = NSClassFromString(@"WCTableViewNormalCellManager");
    Class sectionClass = NSClassFromString(@"WCTableViewSectionManager");
    SEL cellSelector = NSSelectorFromString(@"normalCellForSel:target:title:accessoryType:");
    SEL sectionSelector = NSSelectorFromString(@"sectionInfoDefaut");
    SEL addCellSelector = NSSelectorFromString(@"addCell:");
    SEL insertSectionSelector = NSSelectorFromString(@"insertSection:At:");
    Method cellMethod = class_getClassMethod(cellClass, cellSelector);
    Method sectionMethod = class_getClassMethod(sectionClass, sectionSelector);
    Method addCellMethod = class_getInstanceMethod(sectionClass, addCellSelector);
    Method insertSectionMethod = class_getInstanceMethod(object_getClass(tableManager), insertSectionSelector);
    BOOL insertReturnValid = WBReturnMatches(insertSectionMethod, 'v') || WBReturnMatches(insertSectionMethod, '@');
    WBSettingsAPISignaturesValid = WBCellFactoryMethodMatches(cellMethod) && WBNoArgumentObjectMethodMatches(sectionMethod) && WBObjectArgumentMethodMatches(addCellMethod) && insertSectionMethod && method_getNumberOfArguments(insertSectionMethod) == 4 && insertReturnValid && WBArgumentMatches(insertSectionMethod, 0, '@') && WBArgumentMatches(insertSectionMethod, 1, ':') && WBArgumentMatches(insertSectionMethod, 2, '@') && WBIntegerArgumentMatches(insertSectionMethod, 3);
    if (!WBSettingsAPISignaturesValid) {
        return NO;
    }
    if (WBTableManagerContainsTitle(tableManager, [NSSet setWithObject:@"聊天气泡"])) {
        WBSettingsDuplicateEntryFound = YES;
        WBSettingsEntryAvailable = YES;
        WBSettingsModelPath = @"WCTableViewManager";
        WBSettingsInsertionMethod = @"existing-cell";
        WBSettingsEntryReason = @"entry-already-present";
        return YES;
    }
    id cell = ((id (*)(id, SEL, SEL, id, id, NSInteger))objc_msgSend)(cellClass, cellSelector, NSSelectorFromString(@"wb_openBubbleSettings"), object, @"聊天气泡", UITableViewCellAccessoryDisclosureIndicator);
    id section = ((id (*)(id, SEL))objc_msgSend)(sectionClass, sectionSelector);
    if (!cell || !section) {
        return NO;
    }
    WBSendObjectArgument(section, addCellSelector, cell, addCellMethod);
    WBSendObjectIntegerArguments(tableManager, insertSectionSelector, section, 0, insertSectionMethod);
    WBSettingsEntryModelAdded = YES;
    WBSettingsEntryAvailable = YES;
    WBSettingsModelPath = @"WCTableViewManager";
    WBSettingsInsertionMethod = @"insertSection:At:";
    WBSettingsTableReloaded = WBReloadSettingsTable(object, tableManager);
    WBSettingsEntryReason = WBSettingsTableReloaded ? @"modern-entry-added-table-reloaded" : @"modern-entry-added-table-unavailable";
    return YES;
}

static BOOL WBAddLegacySettingsEntry(id object, id tableViewInfo) {
    Class cellClass = NSClassFromString(@"MMTableViewCellInfo");
    Class sectionClass = NSClassFromString(@"MMTableViewSectionInfo");
    SEL cellSelector = NSSelectorFromString(@"normalCellForSel:target:title:accessoryType:");
    SEL sectionSelector = NSSelectorFromString(@"sectionInfoDefaut");
    SEL addCellSelector = NSSelectorFromString(@"addCell:");
    SEL addSectionSelector = NSSelectorFromString(@"addSection:");
    Method cellMethod = class_getClassMethod(cellClass, cellSelector);
    Method sectionMethod = class_getClassMethod(sectionClass, sectionSelector);
    Method addCellMethod = class_getInstanceMethod(sectionClass, addCellSelector);
    Method addSectionMethod = class_getInstanceMethod(object_getClass(tableViewInfo), addSectionSelector);
    WBSettingsAPISignaturesValid = WBCellFactoryMethodMatches(cellMethod) && WBNoArgumentObjectMethodMatches(sectionMethod) && WBObjectArgumentMethodMatches(addCellMethod) && WBObjectArgumentMethodMatches(addSectionMethod);
    if (!WBSettingsAPISignaturesValid) {
        return NO;
    }
    id cell = ((id (*)(id, SEL, SEL, id, id, NSInteger))objc_msgSend)(cellClass, cellSelector, NSSelectorFromString(@"wb_openBubbleSettings"), object, @"聊天气泡", UITableViewCellAccessoryDisclosureIndicator);
    id section = ((id (*)(id, SEL))objc_msgSend)(sectionClass, sectionSelector);
    if (!cell || !section) {
        return NO;
    }
    WBSendObjectArgument(section, addCellSelector, cell, addCellMethod);
    WBSendObjectArgument(tableViewInfo, addSectionSelector, section, addSectionMethod);
    WBSettingsEntryModelAdded = YES;
    WBSettingsEntryAvailable = YES;
    WBSettingsModelPath = @"MMTableViewInfo";
    WBSettingsInsertionMethod = @"addSection:";
    WBSettingsTableReloaded = WBReloadSettingsTable(object, tableViewInfo);
    WBSettingsEntryReason = WBSettingsTableReloaded ? @"legacy-entry-added-table-reloaded" : @"legacy-entry-added-table-unavailable";
    return YES;
}

static BOOL WBAddSettingsEntry(id object) {
    if (!WBSettingsHookUsesReloadTableData && objc_getAssociatedObject(object, WBSettingsEntryAddedKey)) {
        WBSettingsEntryReason = @"already-added";
        return YES;
    }
    WBResetSettingsEntryState();
    id tableManager = WBIvarValue(object, @"m_tableViewMgr");
    WBSettingsTableManagerAvailable = tableManager != nil;
    if (WBRegisterPluginsPortal(object, tableManager)) {
        objc_setAssociatedObject(object, WBSettingsEntryAddedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return YES;
    }
    if (tableManager && WBAddModernSettingsEntry(object, tableManager)) {
        objc_setAssociatedObject(object, WBSettingsEntryAddedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return YES;
    }
    id tableViewInfo = WBIvarValue(object, @"m_tableViewInfo");
    WBSettingsTableInfoAvailable = tableViewInfo != nil;
    if (tableViewInfo && WBAddLegacySettingsEntry(object, tableViewInfo)) {
        objc_setAssociatedObject(object, WBSettingsEntryAddedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return YES;
    }
    WBSettingsEntryReason = tableManager || tableViewInfo ? @"private-api-signature-mismatch" : @"settings-table-model-unavailable";
    return NO;
}

static NSDictionary<NSString *, id> *WBSettingsConfigurationSnapshot(void) {
    return @{
        @"targetClassAvailable": @(NSClassFromString(@"NewSettingViewController") != Nil),
        @"hookInstalled": @(WBSettingsHookInstalled),
        @"lifecycleSelector": WBSettingsLifecycleName,
        @"lastLifecycleSelector": WBSettingsLastLifecycleName,
        @"entryAvailable": @(WBSettingsEntryAvailable),
        @"entryModelAdded": @(WBSettingsEntryModelAdded),
        @"visibilityVerified": @NO,
        @"tableManagerAvailable": @(WBSettingsTableManagerAvailable),
        @"tableInfoAvailable": @(WBSettingsTableInfoAvailable),
        @"pluginsManagerAvailable": @(WBSettingsPluginsManagerAvailable),
        @"pluginsPortalAvailable": @(WBSettingsPluginsPortalAvailable),
        @"pluginsPortalRegistered": @(WBSettingsPluginsPortalRegistered),
        @"duplicateEntryFound": @(WBSettingsDuplicateEntryFound),
        @"modelPath": WBSettingsModelPath,
        @"insertionMethod": WBSettingsInsertionMethod,
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

static void WBCallOriginalSettingsLifecycle(id object, SEL selector) {
    if (selector == NSSelectorFromString(@"reloadTableData") && WBOriginalSettingsReload) {
        WBOriginalSettingsReload(object, selector);
    } else if (selector == NSSelectorFromString(@"willAppear") && WBOriginalSettingsWillAppear) {
        WBOriginalSettingsWillAppear(object, selector);
    } else if (selector == @selector(viewDidLoad) && WBOriginalSettingsViewDidLoad) {
        WBOriginalSettingsViewDidLoad(object, selector);
    }
}

static void WBSettingsLifecycleHook(id object, SEL selector) {
    if (objc_getAssociatedObject(object, WBSettingsLifecycleInProgressKey)) {
        WBCallOriginalSettingsLifecycle(object, selector);
        return;
    }
    objc_setAssociatedObject(object, WBSettingsLifecycleInProgressKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    WBCallOriginalSettingsLifecycle(object, selector);
    WBSettingsLastLifecycleName = NSStringFromSelector(selector);
    WBAddSettingsEntry(object);
    WBRecordSettingsDiagnostics();
    objc_setAssociatedObject(object, WBSettingsLifecycleInProgressKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void WBSettingsViewWillAppearHook(id object, SEL selector, BOOL animated) {
    if (objc_getAssociatedObject(object, WBSettingsLifecycleInProgressKey)) {
        if (WBOriginalSettingsViewWillAppear) {
            WBOriginalSettingsViewWillAppear(object, selector, animated);
        }
        return;
    }
    objc_setAssociatedObject(object, WBSettingsLifecycleInProgressKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (WBOriginalSettingsViewWillAppear) {
        WBOriginalSettingsViewWillAppear(object, selector, animated);
    }
    WBSettingsLastLifecycleName = NSStringFromSelector(selector);
    WBAddSettingsEntry(object);
    WBRecordSettingsDiagnostics();
    objc_setAssociatedObject(object, WBSettingsLifecycleInProgressKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@implementation WBBubbleSettingsHook

+ (void)installIfPossible {
    @synchronized(self) {
        BOOL pluginsRegistrationSucceeded = WBRegisterWithPluginsManager();
        if (WBSettingsHookInstalled) {
            return;
        }
        Class settingsClass = NSClassFromString(@"NewSettingViewController");
        SEL openSelector = NSSelectorFromString(@"wb_openBubbleSettings");
        SEL reloadSelector = NSSelectorFromString(@"reloadTableData");
        SEL willAppearSelector = NSSelectorFromString(@"willAppear");
        SEL viewWillAppearSelector = @selector(viewWillAppear:);
        SEL viewDidLoadSelector = @selector(viewDidLoad);
        Method reloadMethod = settingsClass ? class_getInstanceMethod(settingsClass, reloadSelector) : NULL;
        Method willAppearMethod = settingsClass ? class_getInstanceMethod(settingsClass, willAppearSelector) : NULL;
        Method viewWillAppearMethod = settingsClass ? class_getInstanceMethod(settingsClass, viewWillAppearSelector) : NULL;
        Method viewDidLoadMethod = settingsClass ? class_getInstanceMethod(settingsClass, viewDidLoadSelector) : NULL;
        BOOL reloadAvailable = WBNoArgumentVoidMethodMatches(reloadMethod);
        BOOL willAppearAvailable = WBNoArgumentVoidMethodMatches(willAppearMethod);
        BOOL viewWillAppearAvailable = WBBooleanArgumentVoidMethodMatches(viewWillAppearMethod);
        BOOL viewDidLoadAvailable = WBNoArgumentVoidMethodMatches(viewDidLoadMethod);
        if (!settingsClass || (!reloadAvailable && !willAppearAvailable && !viewWillAppearAvailable && !viewDidLoadAvailable)) {
            if (!pluginsRegistrationSucceeded) {
                WBSettingsEntryReason = @"lifecycle-unavailable";
            }
            return;
        }
        if (![settingsClass instancesRespondToSelector:openSelector] && !class_addMethod(settingsClass, openSelector, (IMP)WBOpenBubbleSettings, "v@:")) {
            if (!pluginsRegistrationSucceeded) {
                WBSettingsEntryReason = @"open-selector-install-failed";
            }
            return;
        }
        NSMutableArray<NSString *> *hookedSelectors = [NSMutableArray arrayWithCapacity:3];
        if (reloadAvailable) {
            MSHookMessageEx(settingsClass, reloadSelector, (IMP)WBSettingsLifecycleHook, (IMP *)&WBOriginalSettingsReload);
            if (WBOriginalSettingsReload) {
                [hookedSelectors addObject:NSStringFromSelector(reloadSelector)];
            }
        }
        if (willAppearAvailable) {
            MSHookMessageEx(settingsClass, willAppearSelector, (IMP)WBSettingsLifecycleHook, (IMP *)&WBOriginalSettingsWillAppear);
            if (WBOriginalSettingsWillAppear) {
                [hookedSelectors addObject:NSStringFromSelector(willAppearSelector)];
            }
        }
        if (viewWillAppearAvailable) {
            MSHookMessageEx(settingsClass, viewWillAppearSelector, (IMP)WBSettingsViewWillAppearHook, (IMP *)&WBOriginalSettingsViewWillAppear);
            if (WBOriginalSettingsViewWillAppear) {
                [hookedSelectors addObject:NSStringFromSelector(viewWillAppearSelector)];
            }
        }
        if (hookedSelectors.count == 0 && viewDidLoadAvailable) {
            MSHookMessageEx(settingsClass, viewDidLoadSelector, (IMP)WBSettingsLifecycleHook, (IMP *)&WBOriginalSettingsViewDidLoad);
            if (WBOriginalSettingsViewDidLoad) {
                [hookedSelectors addObject:NSStringFromSelector(viewDidLoadSelector)];
            }
        }
        WBSettingsHookUsesReloadTableData = WBOriginalSettingsReload != NULL || WBOriginalSettingsWillAppear != NULL || WBOriginalSettingsViewWillAppear != NULL;
        WBSettingsLifecycleName = hookedSelectors.count > 0 ? [hookedSelectors componentsJoinedByString:@","] : @"unavailable";
        WBSettingsHookInstalled = hookedSelectors.count > 0;
        if (!pluginsRegistrationSucceeded) {
            WBSettingsEntryReason = WBSettingsHookInstalled ? @"waiting-for-settings-screen" : @"hook-install-failed";
        }
    }
}

+ (NSDictionary<NSString *, id> *)configurationSnapshot {
    return WBSettingsConfigurationSnapshot();
}

@end
