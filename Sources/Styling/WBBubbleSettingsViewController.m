#import "WBBubbleSettingsViewController.h"
#import "WBBubblePreferences.h"
#import <math.h>

typedef NS_ENUM(NSInteger, WBSettingsColorTarget) {
    WBSettingsColorTargetOutgoing = 0,
    WBSettingsColorTargetIncoming
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
    return 4;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 2 ? 3 : (section == 1 ? 2 : 1);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[@"功能", @"颜色", @"外观", @""][section];
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
    swatch.layer.cornerRadius = 8.0;
    swatch.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    swatch.layer.borderColor = [UIColor colorWithWhite:0.5 alpha:0.5].CGColor;
    return swatch;
}

- (UISlider *)sliderWithMinimum:(CGFloat)minimum maximum:(CGFloat)maximum value:(CGFloat)value action:(SEL)action {
    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0.0, 0.0, 170.0, 36.0)];
    slider.minimumValue = minimum;
    slider.maximumValue = maximum;
    slider.value = value;
    [slider addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    return slider;
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
    if (indexPath.section == 1) {
        BOOL outgoing = indexPath.row == 0;
        UITableViewCell *cell = [self baseCellWithTitle:outgoing ? @"发送气泡颜色" : @"接收气泡颜色" detail:nil];
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        cell.accessoryView = [self colorSwatch:[WBBubblePreferences fillColorForOutgoing:outgoing]];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    if (indexPath.section == 2) {
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
    UITableViewCell *cell = [self baseCellWithTitle:@"恢复默认设置" detail:nil];
    cell.textLabel.textColor = UIColor.systemRedColor;
    cell.textLabel.textAlignment = NSTextAlignmentCenter;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1) {
        self.colorTarget = indexPath.row == 0 ? WBSettingsColorTargetOutgoing : WBSettingsColorTargetIncoming;
        UIColorPickerViewController *picker = [[UIColorPickerViewController alloc] init];
        picker.delegate = self;
        picker.supportsAlpha = NO;
        picker.selectedColor = [WBBubblePreferences fillColorForOutgoing:self.colorTarget == WBSettingsColorTargetOutgoing];
        [self presentViewController:picker animated:YES completion:nil];
    } else if (indexPath.section == 3) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"恢复默认设置" message:@"颜色和外观参数将恢复为默认值。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        __weak typeof(self) weakSelf = self;
        [alert addAction:[UIAlertAction actionWithTitle:@"恢复" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
            [WBBubblePreferences reset];
            [weakSelf.tableView reloadData];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)enabledChanged:(UISwitch *)sender {
    [WBBubblePreferences setEnabled:sender.isOn];
}

- (void)cornerRadiusChanged:(UISlider *)sender {
    [WBBubblePreferences setCornerRadius:round(sender.value)];
}

- (void)borderWidthChanged:(UISlider *)sender {
    [WBBubblePreferences setBorderWidth:round(sender.value * 10.0) / 10.0];
}

- (void)opacityChanged:(UISlider *)sender {
    [WBBubblePreferences setOpacity:round(sender.value * 20.0) / 20.0];
}

- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)viewController {
    if (self.colorTarget == WBSettingsColorTargetOutgoing) {
        [WBBubblePreferences setOutgoingColor:viewController.selectedColor];
    } else {
        [WBBubblePreferences setIncomingColor:viewController.selectedColor];
    }
    [self.tableView reloadData];
}

- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController *)viewController {
    if (self.colorTarget == WBSettingsColorTargetOutgoing) {
        [WBBubblePreferences setOutgoingColor:viewController.selectedColor];
    } else {
        [WBBubblePreferences setIncomingColor:viewController.selectedColor];
    }
}

@end
