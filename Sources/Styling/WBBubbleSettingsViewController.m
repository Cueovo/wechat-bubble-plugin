#import "WBBubbleSettingsViewController.h"
#import "WBBubblePreferences.h"
#import <math.h>
#import <objc/message.h>

typedef NS_ENUM(NSInteger, WBSettingsColorTarget) {
    WBSettingsColorTargetLightOutgoingFill = 0,
    WBSettingsColorTargetLightIncomingFill,
    WBSettingsColorTargetLightOutgoingBorder,
    WBSettingsColorTargetLightIncomingBorder,
    WBSettingsColorTargetDarkOutgoingFill,
    WBSettingsColorTargetDarkIncomingFill,
    WBSettingsColorTargetDarkOutgoingBorder,
    WBSettingsColorTargetDarkIncomingBorder
};

@interface WBBubbleSettingsViewController () <UIColorPickerViewControllerDelegate>
@property (nonatomic, assign) WBSettingsColorTarget colorTarget;
@end

@implementation WBBubbleSettingsViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"聊天气泡";
    self.tableView.rowHeight = 52.0;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 5;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 1;
        case 1:
        case 2: return 4;
        case 3: return 3;
        case 4: return 2;
        default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"功能";
        case 1: return @"浅色模式";
        case 2: return @"深色模式";
        case 3: return @"外观";
        default: return nil;
    }
}

- (UITableViewCell *)baseCellWithTitle:(NSString *)title detail:(NSString *)detail {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.textLabel.text = title;
    cell.detailTextLabel.text = detail;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (UIView *)colorSwatch:(UIColor *)color {
    UIView *swatch = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 32.0, 32.0)];
    swatch.backgroundColor = color;
    return swatch;
}

- (UISlider *)sliderWithMinimum:(CGFloat)minimum maximum:(CGFloat)maximum value:(CGFloat)value action:(SEL)action {
    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0.0, 0.0, 170.0, 36.0)];
    slider.minimumValue = minimum;
    slider.maximumValue = maximum;
    slider.value = value;
    slider.continuous = NO;
    [slider addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    return slider;
}

- (WBSettingsColorTarget)colorTargetForIndexPath:(NSIndexPath *)indexPath {
    return (WBSettingsColorTarget)(indexPath.row + (indexPath.section == 2 ? 4 : 0));
}

- (BOOL)targetIsDark:(WBSettingsColorTarget)target {
    return target >= WBSettingsColorTargetDarkOutgoingFill;
}

- (BOOL)targetIsBorder:(WBSettingsColorTarget)target {
    NSInteger value = target % 4;
    return value == 2 || value == 3;
}

- (BOOL)targetIsOutgoing:(WBSettingsColorTarget)target {
    return target % 2 == 0;
}

- (UIColor *)colorForTarget:(WBSettingsColorTarget)target {
    BOOL outgoing = [self targetIsOutgoing:target];
    BOOL dark = [self targetIsDark:target];
    return [self targetIsBorder:target] ? [WBBubblePreferences borderColorForOutgoing:outgoing dark:dark] : [WBBubblePreferences fillColorForOutgoing:outgoing dark:dark];
}

- (NSString *)hexForTarget:(WBSettingsColorTarget)target {
    BOOL outgoing = [self targetIsOutgoing:target];
    BOOL dark = [self targetIsDark:target];
    return [self targetIsBorder:target] ? [WBBubblePreferences borderColorHexForOutgoing:outgoing dark:dark] : [WBBubblePreferences fillColorHexForOutgoing:outgoing dark:dark];
}

- (UITableViewCell *)colorCellForIndexPath:(NSIndexPath *)indexPath {
    WBSettingsColorTarget target = [self colorTargetForIndexPath:indexPath];
    NSString *title = @[@"发送气泡颜色", @"接收气泡颜色", @"发送描边颜色", @"接收描边颜色"][indexPath.row];
    UITableViewCell *cell = [self baseCellWithTitle:title detail:[NSString stringWithFormat:@"#%@", [self hexForTarget:target]]];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.accessoryView = [self colorSwatch:[self colorForTarget:target]];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        UITableViewCell *cell = [self baseCellWithTitle:@"启用自定义气泡" detail:nil];
        UISwitch *toggle = [[UISwitch alloc] init];
        toggle.on = [WBBubblePreferences isEnabled];
        [toggle addTarget:self action:@selector(enabledChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        return cell;
    }
    if (indexPath.section == 1 || indexPath.section == 2) {
        return [self colorCellForIndexPath:indexPath];
    }
    if (indexPath.section == 3) {
        if (indexPath.row == 0) {
            UITableViewCell *cell = [self baseCellWithTitle:@"圆角" detail:[NSString stringWithFormat:@"%.0f", [WBBubblePreferences cornerRadius]]];
            cell.accessoryView = [self sliderWithMinimum:4.0 maximum:24.0 value:[WBBubblePreferences cornerRadius] action:@selector(cornerRadiusChanged:)];
            return cell;
        }
        if (indexPath.row == 1) {
            UITableViewCell *cell = [self baseCellWithTitle:@"描边" detail:[NSString stringWithFormat:@"%.1f", [WBBubblePreferences borderWidth]]];
            cell.accessoryView = [self sliderWithMinimum:0.0 maximum:3.0 value:[WBBubblePreferences borderWidth] action:@selector(borderWidthChanged:)];
            return cell;
        }
        UITableViewCell *cell = [self baseCellWithTitle:@"透明度" detail:[NSString stringWithFormat:@"%.0f%%", [WBBubblePreferences opacity] * 100.0]];
        cell.accessoryView = [self sliderWithMinimum:0.35 maximum:1.0 value:[WBBubblePreferences opacity] action:@selector(opacityChanged:)];
        return cell;
    }
    NSString *title = indexPath.row == 0 ? @"恢复插件默认主题" : @"恢复微信原始外观";
    UITableViewCell *cell = [self baseCellWithTitle:title detail:nil];
    cell.textLabel.textColor = indexPath.row == 0 ? self.view.tintColor : UIColor.systemRedColor;
    cell.textLabel.textAlignment = NSTextAlignmentCenter;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1 || indexPath.section == 2) {
        self.colorTarget = [self colorTargetForIndexPath:indexPath];
        UIColorPickerViewController *picker = [[UIColorPickerViewController alloc] init];
        ((void (*)(id, SEL, id))objc_msgSend)(picker, NSSelectorFromString(@"setDelegate:"), self);
        ((void (*)(id, SEL, BOOL))objc_msgSend)(picker, NSSelectorFromString(@"setSupportsAlpha:"), NO);
        ((void (*)(id, SEL, id))objc_msgSend)(picker, NSSelectorFromString(@"setSelectedColor:"), [self colorForTarget:self.colorTarget]);
        [self presentViewController:picker animated:YES completion:nil];
        return;
    }
    if (indexPath.section != 4) {
        return;
    }
    BOOL resetTheme = indexPath.row == 0;
    NSString *title = resetTheme ? @"恢复插件默认主题" : @"恢复微信原始外观";
    NSString *message = resetTheme ? @"颜色和外观参数将恢复为插件默认值，并保持功能开启。" : @"自定义气泡将持续关闭，当前和后续文字气泡恢复微信原始样式；已保存的主题参数不会删除。";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"确认" style:(resetTheme ? UIAlertActionStyleDefault : UIAlertActionStyleDestructive) handler:^(__unused UIAlertAction *action) {
        if (resetTheme) {
            [WBBubblePreferences reset];
        } else {
            [WBBubblePreferences setEnabled:NO];
        }
        [weakSelf.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)enabledChanged:(UISwitch *)sender {
    [WBBubblePreferences setEnabled:sender.isOn];
}

- (void)cornerRadiusChanged:(UISlider *)sender {
    [WBBubblePreferences setCornerRadius:round(sender.value)];
    [self.tableView reloadData];
}

- (void)borderWidthChanged:(UISlider *)sender {
    [WBBubblePreferences setBorderWidth:round(sender.value * 10.0) / 10.0];
    [self.tableView reloadData];
}

- (void)opacityChanged:(UISlider *)sender {
    [WBBubblePreferences setOpacity:round(sender.value * 20.0) / 20.0];
    [self.tableView reloadData];
}

- (void)applySelectedColor:(UIColorPickerViewController *)viewController {
    UIColor *selectedColor = ((id (*)(id, SEL))objc_msgSend)(viewController, NSSelectorFromString(@"selectedColor"));
    BOOL outgoing = [self targetIsOutgoing:self.colorTarget];
    BOOL dark = [self targetIsDark:self.colorTarget];
    if ([self targetIsBorder:self.colorTarget]) {
        [WBBubblePreferences setBorderColor:selectedColor outgoing:outgoing dark:dark];
    } else {
        [WBBubblePreferences setFillColor:selectedColor outgoing:outgoing dark:dark];
    }
}

- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)viewController {
    [self applySelectedColor:viewController];
    [self.tableView reloadData];
}

- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController *)viewController {
    [self applySelectedColor:viewController];
}

@end
