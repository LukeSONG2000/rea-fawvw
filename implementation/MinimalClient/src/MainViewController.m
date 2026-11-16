// MainViewController.m — P0 验证界面（刻意保持最小）
// 流程：登录 → SDK 初始化结果 → 车辆 VIN 列表 → 点选车辆 → 只读状态。
// P1 才做左上角车名下拉单选菜单（交接文档：P0 未通过前不大规模重做页面）。
#import "MainViewController.h"
#import "MCSDK.h"
#import "MCHostAuth.h"
#import "MCConfiguration.h"
#import "MCKeychainForensics.h"
#import "MCReadonlyVerification.h"

@interface MainViewController ()
@end

@implementation MainViewController

- (void)doLogin:(id)sender {
    // 复用官方登录（会话导入模式）：官方 App 的 idToken 已写入本 App 沙盒
    // NSUserDefaults(imported.idToken)。存在则跳过网关密码登录，直接做 MBB 令牌交换。
    NSString *imported = [[NSUserDefaults standardUserDefaults] stringForKey:@"imported.idToken"];
    if (imported.length > 0) {
        [self log:@"使用本机导入的身份令牌进行一次 MBB 验证…"];
        [self runSDKInitAndMBBLoginWithToken:imported];
        return;
    }
    [self.userField resignFirstResponder]; [self.passField resignFirstResponder];
    if (self.userField.text.length == 0 || self.passField.text.length == 0) {
        [self log:@"请输入账号与密码（或导入官方会话）"]; return;
    }
    [self runSDKInitAndGatewayLogin];
}

- (void)runSDKInitAndMBBLoginWithToken:(NSString *)identityToken {
    [self log:@"SDK 初始化…"];
    [[MCSDK shared] initializeSDK:^(NSError *err) {
        if (err) { [self log:@"SDK 初始化失败: %@", err.localizedDescription]; return; }
        [self log:@"MBB 令牌交换…"];
        [[MCSDK shared] loginMBBWithIdentityToken:identityToken completion:^(NSError *merr) {
            [self log:@"%@", merr ? [NSString stringWithFormat:@"MBB 登录失败: %@", merr.localizedDescription]
                                  : @"登录完成（只读会话）"];
        }];
    }];
}

- (void)runSDKInitAndGatewayLogin {
    [self log:@"1/3 SDK 初始化…"];
    [[MCSDK shared] initializeSDK:^(NSError *err) {
        if (err) { [self log:@"SDK 初始化失败: %@", err.localizedDescription]; return; }
        [self log:@"2/3 宿主网关密码登录…"];
        [MCHostAuth loginWithUsername:self.userField.text password:self.passField.text
            completion:^(NSString *token, NSError *gerr) {
                if (!token) { [self log:@"网关登录失败: %@", gerr.localizedDescription];
                              [self log:@"（请求字段/令牌字段未取证，属预期；见 P0-EVIDENCE）"]; return; }
                [self log:@"3/3 MBB 令牌交换…"];
                [[MCSDK shared] loginMBBWithIdentityToken:token completion:^(NSError *merr) {
                    [self log:@"%@", merr ? [NSString stringWithFormat:@"MBB 登录失败: %@", merr.localizedDescription]
                                          : @"登录完成（只读会话）"];
                }];
            }];
    }];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.title = @"一汽大众·车控 PoC";

    self.userField = [[UITextField alloc] initWithFrame:CGRectMake(20, 120, self.view.bounds.size.width - 40, 44)];
    self.userField.placeholder = @"手机号（仅登录用，不记录）";
    self.userField.keyboardType = UIKeyboardTypePhonePad;
    self.userField.borderStyle = UITextBorderStyleRoundedRect;
    self.userField.autocorrectionType = UITextAutocorrectionTypeNo;

    self.passField = [[UITextField alloc] initWithFrame:CGRectMake(20, 174, self.view.bounds.size.width - 40, 44)];
    self.passField.placeholder = @"密码";
    self.passField.secureTextEntry = YES;
    self.passField.borderStyle = UITextBorderStyleRoundedRect;

    UIButton *loginBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    loginBtn.frame = CGRectMake(20, 230, self.view.bounds.size.width - 40, 50);
    [loginBtn setTitle:@"登录（网关密码 → MBB）" forState:UIControlStateNormal];
    [loginBtn addTarget:self action:@selector(doLogin:) forControlEvents:UIControlEventTouchUpInside];

    self.vehicleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 296, self.view.bounds.size.width - 40, 30)];
    self.vehicleLabel.text = @"车辆：未登录";
    self.vehicleLabel.font = [UIFont systemFontOfSize:15];

    UIButton *vinsBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    vinsBtn.frame = CGRectMake(20, 334, (self.view.bounds.size.width - 50) / 2, 44);
    [vinsBtn setTitle:@"读取车辆 VIN" forState:UIControlStateNormal];
    [vinsBtn addTarget:self action:@selector(loadVins:) forControlEvents:UIControlEventTouchUpInside];

    UIButton *statusBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    statusBtn.frame = CGRectMake(30 + (self.view.bounds.size.width - 50) / 2, 334, (self.view.bounds.size.width - 50) / 2, 44);
    [statusBtn setTitle:@"当前车状态（只读）" forState:UIControlStateNormal];
    [statusBtn addTarget:self action:@selector(queryStatus:) forControlEvents:UIControlEventTouchUpInside];

    self.logView = [[UITextView alloc] initWithFrame:CGRectMake(20, 394, self.view.bounds.size.width - 40, self.view.bounds.size.height - 460)];
    self.logView.font = [UIFont fontWithName:@"Menlo" size:11];
    self.logView.editable = NO;
    self.logView.layer.borderWidth = 1;
    self.logView.layer.borderColor = [UIColor systemGray4Color].CGColor;

    for (UIView *v in @[self.userField, self.passField, loginBtn, self.vehicleLabel, vinsBtn, statusBtn, self.logView])
        [self.view addSubview:v];

    [self log:@"PoC 就绪。SDK 类探测: %@", [MCSDK shared].sdkAvailable ? @"可用" : @"不可用"];
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        [MCKeychainForensics dumpGenericPasswordSummary];
        [MCKeychainForensics findIdentityTokenCandidates];
    });

    // 崩溃取证模式：启动 5 秒后自动执行 SDK 初始化（无需凭据、不发网络请求）。
    // 触发与点击登录相同的 initializeSDK 路径，配合 console 启动捕获 fatalError 消息。
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if ([NSProcessInfo.processInfo.environment[@"MC_P0_AUTORUN"] isEqualToString:@"1"]) {
            [self log:@"开始一次只读链路验证…"];
            [MCReadonlyVerification runWithProgress:^(NSString *message) { [self log:@"%@",message]; }];
            return;
        }
        [self log:@"自动初始化（取证模式）…"];
        [[MCSDK shared] initializeSDK:^(NSError *err) {
            [self log:@"自动初始化结果: %@", err ? err.localizedDescription : @"成功"];
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

- (void)loadVins:(id)sender {
    [[MCSDK shared] vehicleVinsWithCompletion:^(NSArray<NSString *> *vins, NSError *err) {
        if (err) { [self log:@"车辆读取失败: %@", err.localizedDescription]; return; }
        self.vins = vins;
        [self log:@"车辆 VIN: %@", vins];
        if (vins.count > 0) {
            [self log:@"选择首辆（useVehicle）"];
            [[MCSDK shared] useVehicleWithVIN:vins[0]];
        }
    }];
}

- (void)queryStatus:(id)sender {
    [[MCSDK shared] statusOfCurrentVehicleWithCompletion:^(NSString *summary, NSError *err) {
        [self log:@"%@", err ? [NSString stringWithFormat:@"状态失败: %@", err.localizedDescription]
                             : [NSString stringWithFormat:@"状态: %@", summary]];
    }];
}

@end
