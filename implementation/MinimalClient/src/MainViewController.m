// MainViewController.m — 车辆信息 + 能力 + 控制面板
// 左上角：按 VIN 单选下拉（UIMenu，交接文档 P1 要求）
// 控制按钮：用户已授权执行；每个指令带确认弹窗。
#import "MainViewController.h"
#import "MCSDK.h"
#import "MCHostAuth.h"
#import "MCConfiguration.h"

@interface MainViewController ()
@property (nonatomic, strong) NSArray<MCVehicleInfo *> *vehicles;
@property (nonatomic, copy) NSString *currentVIN;
@property (nonatomic, strong) UILabel *infoLabel;    // 车辆静态信息
@property (nonatomic, strong) UILabel *statusLabel;  // 只读状态
@property (nonatomic, strong) UITextView *logView;
@end

@implementation MainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.title = @"一汽大众·车控";
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"车辆…" style:UIBarButtonItemStylePlain target:nil action:nil];

    CGFloat W = self.view.bounds.size.width;
    self.infoLabel = [[UILabel alloc] init];
    self.infoLabel.font = [UIFont systemFontOfSize:13];
    self.infoLabel.numberOfLines = 0;
    self.infoLabel.text = @"等待自动登录…";

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.font = [UIFont fontWithName:@"Menlo" size:11];
    self.statusLabel.numberOfLines = 0;

    self.logView = [[UITextView alloc] init];
    self.logView.font = [UIFont fontWithName:@"Menlo" size:10];
    self.logView.editable = NO;
    self.logView.layer.borderWidth = 1;
    self.logView.layer.borderColor = [UIColor systemGray4Color].CGColor;
    [self.logView.heightAnchor constraintEqualToConstant:150].active = YES;

    // 控制按钮：2 列 × 4 行
    NSArray *titles = @[
        @"闪灯", @"鸣笛+闪灯", @"锁车", @"解锁",
        @"车窗通风", @"车窗全开", @"车窗全关", @"空调开22℃",
        @"空调关", @"辅热开", @"辅热关", @"发动机启",
        @"发动机停", @"刷新状态", @"停车位置", @"行程记录",
        @"空调状态", @"健康告警", @"门窗细态", @"能力清单"];
    NSMutableArray *rows = [NSMutableArray array];
    for (NSUInteger r = 0; r < 5; r++) {
        NSMutableArray *row = [NSMutableArray array];
        for (NSUInteger c = 0; c < 4; c++) {
            NSString *t = titles[r * 4 + c];
            UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
            [b setTitle:t forState:UIControlStateNormal];
            [b.layer setBorderWidth:1];
            b.layer.borderColor = [UIColor systemBlueColor].CGColor;
            b.layer.cornerRadius = 6;
            [b addTarget:self action:@selector(onAction:) forControlEvents:UIControlEventTouchUpInside];
            b.accessibilityLabel = t;
            [b.heightAnchor constraintEqualToConstant:40].active = YES;
            [row addObject:b];
        }
        UIStackView *sv = [[UIStackView alloc] initWithArrangedSubviews:row];
        sv.axis = UILayoutConstraintAxisHorizontal;
        sv.distribution = UIStackViewDistributionFillEqually;
        sv.spacing = 8;
        [rows addObject:sv];
    }
    UIStackView *grid = [[UIStackView alloc] initWithArrangedSubviews:rows];
    grid.axis = UILayoutConstraintAxisVertical;
    grid.spacing = 8;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:
        @[self.infoLabel, self.statusLabel, grid, self.logView]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;

    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];
    [self.view addSubview:scroll];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:12],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-12],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-16],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-32],
    ]];

    // 自动登录（持久会话）
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSString *imported = [[NSUserDefaults standardUserDefaults] stringForKey:@"imported.idToken"];
        if (imported.length == 0) { [self log:@"无持久会话"]; return; }
        [self log:@"自动登录…"];
        [[MCSDK shared] initializeSDK:^(NSError *err) {
            if (err) { [self log:@"初始化失败: %@", err.localizedDescription]; return; }
            [[MCSDK shared] loginMBBWithIdentityToken:imported completion:^(NSError *merr) {
                if (merr) { [self log:@"自动登录失败: %@", merr.localizedDescription]; return; }
                [self log:@"已登录，加载车辆…"];
                [self loadCatalog];
            }];
        }];
    });
}

- (void)log:(NSString *)fmt, ... {
    va_list ap; va_start(ap, fmt);
    NSString *line = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    dispatch_async(dispatch_get_main_queue(), ^{
        self.logView.text = [NSString stringWithFormat:@"%@%@\n", self.logView.text, line];
        NSLog(@"[MC] %@", line);
    });
}

#pragma mark 车辆目录与左上角单选下拉

- (void)loadCatalog {
    [[MCSDK shared] catalogWithCompletion:^(NSArray<MCVehicleInfo *> *infos, NSError *err) {
        if (!infos) { [self log:@"车辆目录失败: %@", err.localizedDescription]; return; }
        self.vehicles = infos;
        [self log:@"%lu 辆车已加载", (unsigned long)infos.count];
        NSString *pick = self.currentVIN ?: infos.firstObject.vin;
        [self rebuildMenu:pick];
        [self selectVIN:pick];
    }];
}

- (void)rebuildMenu:(NSString *)pick {
    NSMutableArray<UIAction *> *actions = [NSMutableArray array];
    for (MCVehicleInfo *v in self.vehicles) {
        NSString *sub = [NSString stringWithFormat:@"%@ · %@…%@",
            v.displayName.length ? v.displayName : @"?", [v.vin substringToIndex:8],
            [v.vin substringFromIndex:11]];
        NSString *title = [v.vin isEqualToString:pick]
            ? [@"✓ " stringByAppendingString:sub] : sub;
        [actions addObject:[UIAction actionWithTitle:title image:nil identifier:v.vin
            handler:^(__kindof UIAction *a) { [self selectVIN:v.vin]; }]];
    }
    self.navigationItem.leftBarButtonItem.menu = [UIMenu menuWithTitle:@"切换车辆" children:actions];
}

- (MCVehicleInfo *)currentInfo {
    return [self.vehicles filteredArrayUsingPredicate:
        [NSPredicate predicateWithFormat:@"vin == %@", self.currentVIN]].firstObject;
}

- (void)selectVIN:(NSString *)vin {
    self.currentVIN = vin;
    [self rebuildMenu:vin];
    MCVehicleInfo *v = [self currentInfo];
    if (!v) return;
    self.navigationItem.leftBarButtonItem.title = v.displayName.length ? v.displayName : vin;
    self.infoLabel.text = [NSString stringWithFormat:
        @"%@\n%@ 年款 · 产地 %@ · 变速箱 %@\n发动机 %@ · 颜色色号 %@ · MMI %@\nVIN %@",
        v.displayName, v.modelYear.length ? v.modelYear : @"?", v.countryCode, v.transmission,
        v.engine, v.color, v.mmi, v.vin];
    self.statusLabel.text = @"加载状态…";
    [[MCSDK shared] selectVehicleWithVIN:vin completion:^(NSError *err) {
        if (err) { [self log:@"选车失败: %@", err.localizedDescription]; return; }
        [self refreshStatus];
    }];
}

- (void)refreshStatus {
    [[MCSDK shared] statusOfCurrentVehicleWithCompletion:^(NSString *summary, NSError *err) {
        if (err) { self.statusLabel.text = [@"状态失败: " stringByAppendingString:err.localizedDescription]; return; }
        self.statusLabel.text = [self prettyStatus:summary];
    }];
}

- (NSString *)prettyStatus:(NSString *)raw {
    NSData *d = [raw dataUsingEncoding:NSUTF8StringEncoding];
    id j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
    if (![j isKindOfClass:NSDictionary.class]) return raw;
    NSDictionary *x = j;
    NSDateFormatter *df = [NSDateFormatter new]; df.dateFormat = @"MM-dd HH:mm";
    NSMutableString *s = [NSMutableString string];
    if (x[@"timestamp"]) [s appendFormat:@"状态时间 %@\n",
        [df stringFromDate:[NSDate dateWithTimeIntervalSince1970:[x[@"timestamp"] doubleValue]]]];
    NSDictionary *m = x[@"mileage"]; if (m[@"mileage"]) [s appendFormat:@"总里程 %@ km\n", m[@"mileage"]];
    NSDictionary *f = x[@"fuelLevel"]; if (f[@"level"]) [s appendFormat:@"油量 %@%%\n", f[@"level"]];
    NSDictionary *r = x[@"primaryEngineRange"]; if (r[@"range"]) [s appendFormat:@"续航 %@ km\n", r[@"range"]];
    if (x[@"nextServiceInKm"]) [s appendFormat:@"下次保养 %@km / %@天\n", x[@"nextServiceInKm"], x[@"nextServiceInDays"] ?: @"-"];
    if (x[@"nextOilServiceInKm"]) [s appendFormat:@"下次换油 %@km / %@天\n", x[@"nextOilServiceInKm"], x[@"nextOilServiceInDays"] ?: @"-"];
    if ([x[@"bodyStatus"] isKindOfClass:NSDictionary.class]) {
        NSDictionary *b = x[@"bodyStatus"];
        if (b[@"centralLockStatus"]) [s appendFormat:@"中央门锁 %@\n", [b[@"centralLockStatus"] description]];
        id comps = b[@"vehicleComponents"];
        if ([comps isKindOfClass:NSArray.class] && [(NSArray *)comps count]) {
            [s appendFormat:@"部件 %lu 项（门窗/机盖/天窗）\n", (unsigned long)[(NSArray *)comps count]];
        }
    }
    return s.length ? s : raw;
}

#pragma mark 控制与查询按钮

- (void)onAction:(UIButton *)sender {
    NSString *what = sender.accessibilityLabel;
    NSDictionary<NSString *, void (^)(void)> *handlers = @{
        @"闪灯": ^{ [[MCSDK shared] flashLights:^(NSString *st){[self log:@"闪灯结果: %@",st];} error:^(NSString *e){[self log:@"闪灯失败: %@",e];}]; },
        @"鸣笛+闪灯": ^{ [[MCSDK shared] honkAndFlash:^(NSString *st){[self log:@"鸣笛闪灯结果: %@",st];} error:^(NSString *e){[self log:@"鸣笛闪灯失败: %@",e];}]; },
        @"锁车": ^{ [[MCSDK shared] lockVehicle:^(NSString *st){[self log:@"锁车结果: %@",st];} error:^(NSString *e){[self log:@"锁车失败: %@",e];}]; },
        @"解锁": ^{ [[MCSDK shared] unlockVehicle:^(NSString *st){[self log:@"解锁结果: %@",st];} error:^(NSString *e){[self log:@"解锁失败: %@",e];}]; },
        @"车窗通风": ^{ [[MCSDK shared] windowVenting:^(NSString *st){[self log:@"通风结果: %@",st];} error:^(NSString *e){[self log:@"通风失败: %@",e];}]; },
        @"刷新状态": ^{ [self refreshStatus]; },
        @"停车位置": ^{ [[MCSDK shared] locationOfCurrentVehicleWithCompletion:^(NSString *sum, NSError *err) {
            [self log:@"%@", err ? [NSString stringWithFormat:@"位置失败: %@", err.localizedDescription]
                                 : [NSString stringWithFormat:@"位置: %@", sum]]; }]; },
        @"能力清单": ^{ [self showFeatures]; },
        @"车窗全开": ^{ [[MCSDK shared] windowOpen:^(NSString *st){[self log:@"车窗全开结果: %@",st];} error:^(NSString *e){[self log:@"车窗全开失败: %@",e];}]; },
        @"车窗全关": ^{ [[MCSDK shared] windowClose:^(NSString *st){[self log:@"车窗全关结果: %@",st];} error:^(NSString *e){[self log:@"车窗全关失败: %@",e];}]; },
        @"空调开22℃": ^{ [[MCSDK shared] climateStart:22.0 onStatus:^(NSString *st){[self log:@"空调开启结果: %@",st];} error:^(NSString *e){[self log:@"空调开启失败: %@",e];}]; },
        @"空调关": ^{ [[MCSDK shared] climateStop:^(NSString *st){[self log:@"空调关闭结果: %@",st];} error:^(NSString *e){[self log:@"空调关闭失败: %@",e];}]; },
        @"辅热开": ^{ [[MCSDK shared] auxHeatStart:^(NSString *st){[self log:@"辅热开启结果: %@",st];} error:^(NSString *e){[self log:@"辅热开启失败: %@",e];}]; },
        @"辅热关": ^{ [[MCSDK shared] auxHeatStop:^(NSString *st){[self log:@"辅热关闭结果: %@",st];} error:^(NSString *e){[self log:@"辅热关闭失败: %@",e];}]; },
        @"发动机启": ^{ [self promptSpinThenStartEngine]; },
        @"发动机停": ^{ [[MCSDK shared] engineStop:^(NSString *st){[self log:@"发动机停止结果: %@",st];} error:^(NSString *e){[self log:@"发动机停止失败: %@",e];}]; },
        @"空调状态": ^{ [[MCSDK shared] climateStatusWithCompletion:^(NSString *sum, NSError *err) {
            dispatch_async(dispatch_get_main_queue(), ^{ self.statusLabel.text = err ? [NSString stringWithFormat:@"空调状态失败: %@", err.localizedDescription] : [NSString stringWithFormat:@"空调状态: %@", sum]; }); }]; },
        @"健康告警": ^{ [[MCSDK shared] healthWarningsWithCompletion:^(NSString *sum, NSError *err) {
            dispatch_async(dispatch_get_main_queue(), ^{ self.statusLabel.text = err ? [NSString stringWithFormat:@"健康告警失败: %@", err.localizedDescription] : [NSString stringWithFormat:@"健康告警: %@", sum]; }); }]; },
        @"门窗细态": ^{ [self refreshStatus]; },
        @"行程记录": ^{ [[MCSDK shared] tripsOfCurrentVehicleWithCompletion:^(NSArray<NSDictionary *> *trips, NSError *err) {
            if (err) { [self log:@"行程失败: %@", err.localizedDescription]; return; }
            [self log:@"%lu 条行程", (unsigned long)trips.count];
            NSMutableString *s = [NSMutableString string];
            for (NSDictionary *t in trips) {
                [s appendFormat:@"• %@ 行程 %@km 用时 %@s 均速 %@ 油耗 %@L/100km\n",
                    t[@"tripEnd"], t[@"mileage"] ?: @"?", t[@"travelTime"] ?: @"?",
                    t[@"averageSpeed"] ?: @"?", t[@"averageFuelConsumption"] ?: @"?"];
            }
            dispatch_async(dispatch_get_main_queue(), ^{ self.statusLabel.text = s.length ? s : @"无行程记录"; });
        }]; },
    };
    void (^run)(void) = handlers[what];
    if (!run) return;
    NSArray *needConfirm = @[@"闪灯", @"鸣笛+闪灯", @"锁车", @"解锁", @"车窗通风", @"车窗全开", @"车窗全关", @"空调开22℃", @"空调关", @"辅热开", @"辅热关", @"发动机启", @"发动机停"];
    if (![needConfirm containsObject:what]) { run(); return; }
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:what
        message:[NSString stringWithFormat:@"对 %@（%@）执行「%@」？",
            self.navigationItem.leftBarButtonItem.title, self.currentVIN, what]
        preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"执行" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) { run(); }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)showFeatures {
    MCVehicleInfo *v = [self currentInfo];
    if (!v) return;
    NSDictionary *desc = [MCSDK featureDescriptions];
    NSMutableString *s = [NSMutableString stringWithFormat:@"%@ 支持的能力：\n", v.displayName];
    for (NSString *key in v.features) [s appendFormat:@"• %@\n", desc[key] ?: key];
    [s appendString:@"\nSDK 控制接口（部分需 SPIN/能力开通）："];
    [[MCSDK controlCatalog] enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSString *sdk, BOOL *stop) {
        [s appendFormat:@"\n• %@：%@", k, sdk];
    }];
    self.statusLabel.text = s;
}

- (void)promptSpinThenStartEngine {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"远程启动发动机"
        message:@"输入车机 SPIN 安全码（仅本次使用，不保存）" preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.secureTextEntry = YES; tf.keyboardType = UIKeyboardTypeNumberPad;
    }];
    [ac addAction:[UIAlertAction actionWithTitle:@"启动" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        NSString *spin = ac.textFields.firstObject.text;
        if (spin.length == 0) { [self log:@"未输入 SPIN，已取消"]; return; }
        [[MCSDK shared] engineStartWithSpin:spin onStatus:^(NSString *st) {
            [self log:@"远程启动结果: %@", st];
            dispatch_async(dispatch_get_main_queue(), ^{ self.statusLabel.text = [@"远程启动: " stringByAppendingString:st]; });
        } error:^(NSString *e) { [self log:@"远程启动失败: %@", e]; }];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

@end
