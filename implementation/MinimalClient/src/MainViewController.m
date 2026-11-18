#import "MainViewController.h"
#import "MCSDK.h"
#import "MCCapabilitySurvey.h"
#import "MCInformationViewController.h"
#import "MCUI.h"
#import "MCRemoteHardware.h"

static UIColor *RemoteColor(CGFloat v) {return [UIColor colorWithWhite:v alpha:1];}
static UILabel *Label(NSString *text,CGFloat size,UIFontWeight weight,UIColor *color) {
    UILabel *l=[UILabel new];l.text=text;l.font=MCFont(size,weight);l.textColor=color;l.numberOfLines=0;l.adjustsFontForContentSizeCategory=YES;return l;
}
static UIStackView *Stack(NSArray *views,BOOL horizontal,CGFloat spacing) {
    UIStackView *s=[[UIStackView alloc] initWithArrangedSubviews:views];s.axis=horizontal?UILayoutConstraintAxisHorizontal:UILayoutConstraintAxisVertical;s.spacing=spacing;return s;
}
@interface MainViewController ()
@property(nonatomic,strong) NSArray<MCVehicleInfo *> *vehicles;
@property(nonatomic,copy) NSString *currentVIN;
@property(nonatomic,strong) UILabel *rangeLabel,*fuelLabel,*mileageLabel,*snapshotLabel,*bodyLabel,*messageLabel,*vehicleLabel;
@property(nonatomic,strong) UIButton *refreshButton;
@property(nonatomic,strong) UIStackView *controlGrid;
@property(nonatomic,strong) NSMutableArray<UIButton *> *controlButtons;
@property(nonatomic,strong) MCRemoteKey *lockButton,*unlockButton;
@property(nonatomic,strong) UIRefreshControl *refreshControl;
@property(nonatomic,strong) UIActivityIndicatorView *activity;
@property(nonatomic) BOOL vehicleReady,selecting,commandRunning,refreshing,sessionLoading;
@property(nonatomic) NSUInteger generation,refreshGeneration,commandGeneration;
@end
@implementation MainViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor=MCPaper();self.title=@"车控";self.controlButtons=[NSMutableArray array];
    UINavigationBarAppearance *appearance=[UINavigationBarAppearance new];[appearance configureWithOpaqueBackground];appearance.backgroundColor=MCPaper();appearance.shadowColor=UIColor.clearColor;
    self.navigationController.navigationBar.standardAppearance=appearance;self.navigationController.navigationBar.scrollEdgeAppearance=appearance;self.navigationController.navigationBar.tintColor=UIColor.labelColor;
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"选择车辆 ⌄" style:UIBarButtonItemStylePlain target:nil action:nil];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"info.circle"] style:UIBarButtonItemStylePlain target:self action:@selector(openInformation)];
    self.navigationItem.rightBarButtonItem.accessibilityLabel=@"查看车辆信息";self.navigationItem.rightBarButtonItem.enabled=NO;
    [self buildRemote];[self startSession];
}
- (MCRemoteKey *)key:(NSString *)title icon:(NSString *)icon large:(BOOL)large {
    MCRemoteKey *button=[MCRemoteKey buttonWithType:UIButtonTypeCustom];
    [button configureTitle:title icon:icon large:large];
    button.backgroundColor=UIColor.clearColor;button.layer.cornerRadius=large?24:20;button.layer.borderWidth=0;
    button.accessibilityLabel=title;[button.heightAnchor constraintGreaterThanOrEqualToConstant:44].active=YES;
    [button addTarget:self action:@selector(keyDown:) forControlEvents:UIControlEventTouchDown];
    [self.controlButtons addObject:button];return button;
}
- (void)keyDown:(UIButton *)button {if(button.enabled) MCHapticPress();}
- (void)buildRemote {
    UIScrollView *scroll=[UIScrollView new];scroll.translatesAutoresizingMaskIntoConstraints=NO;scroll.alwaysBounceVertical=YES;[self.view addSubview:scroll];
    self.refreshControl=[UIRefreshControl new];[self.refreshControl addTarget:self action:@selector(refreshPressed) forControlEvents:UIControlEventValueChanged];scroll.refreshControl=self.refreshControl;
    UIView *remote=[MCRemoteHousing new];remote.translatesAutoresizingMaskIntoConstraints=NO;[scroll addSubview:remote];
    self.vehicleLabel=Label(@"车辆遥控器",13,UIFontWeightSemibold,RemoteColor(.64));
    UILabel *brand=Label(@"CAR CONTROL",10,UIFontWeightBold,RemoteColor(.47));
    UIStackView *brandRow=Stack(@[self.vehicleLabel,[UIView new],brand],YES,12);brandRow.alignment=UIStackViewAlignmentCenter;
    UIView *led=[MCLCDPanel new];
    UIColor *lcd=[UIColor colorWithRed:.15 green:.21 blue:.15 alpha:1];
    UILabel *caption=Label(@"车辆状态",13,UIFontWeightSemibold,lcd);
    self.refreshButton=[UIButton buttonWithType:UIButtonTypeSystem];[self.refreshButton setImage:[UIImage systemImageNamed:@"arrow.clockwise"] forState:UIControlStateNormal];self.refreshButton.tintColor=lcd;self.refreshButton.accessibilityLabel=@"刷新车辆状态";[self.refreshButton.widthAnchor constraintEqualToConstant:44].active=YES;[self.refreshButton.heightAnchor constraintEqualToConstant:44].active=YES;[self.refreshButton addTarget:self action:@selector(refreshPressed) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *ledTop=Stack(@[caption,[UIView new],self.refreshButton],YES,4);ledTop.alignment=UIStackViewAlignmentCenter;
    self.rangeLabel=[MCSevenSegmentLabel new];self.rangeLabel.text=@"—";self.rangeLabel.textColor=lcd;self.rangeLabel.font=[UIFont monospacedDigitSystemFontOfSize:56 weight:UIFontWeightLight];self.rangeLabel.adjustsFontSizeToFitWidth=YES;self.rangeLabel.minimumScaleFactor=.5;self.rangeLabel.numberOfLines=1;
    UILabel *rangeCaption=Label(@"预计续航 · km",12,UIFontWeightMedium,lcd);
    self.fuelLabel=Label(@"— %",28,UIFontWeightMedium,lcd);self.fuelLabel.font=[UIFont monospacedDigitSystemFontOfSize:28 weight:UIFontWeightMedium];
    UILabel *fuelCaption=Label(@"燃油余量",12,UIFontWeightMedium,lcd);
    UIStackView *range=Stack(@[self.rangeLabel,rangeCaption],NO,0),*fuel=Stack(@[self.fuelLabel,fuelCaption],NO,5);
    UIStackView *numbers=Stack(@[range,fuel],YES,16);numbers.distribution=UIStackViewDistributionFillProportionally;numbers.alignment=UIStackViewAlignmentBottom;
    self.bodyLabel=Label(@"等待车辆状态",13,UIFontWeightMedium,lcd);
    self.mileageLabel=Label(@"总里程 — km",12,UIFontWeightRegular,lcd);
    self.snapshotLabel=Label(@"尚未读取车况",11,UIFontWeightRegular,[lcd colorWithAlphaComponent:.75]);
    UIStackView *ledStack=Stack(@[ledTop,numbers,self.bodyLabel,self.mileageLabel,self.snapshotLabel],NO,6);ledStack.translatesAutoresizingMaskIntoConstraints=NO;[led addSubview:ledStack];
    [NSLayoutConstraint activateConstraints:@[[ledStack.topAnchor constraintEqualToAnchor:led.topAnchor constant:10],[ledStack.bottomAnchor constraintEqualToAnchor:led.bottomAnchor constant:-18],[ledStack.leadingAnchor constraintEqualToAnchor:led.leadingAnchor constant:20],[ledStack.trailingAnchor constraintEqualToAnchor:led.trailingAnchor constant:-20]]];
    self.lockButton=[self key:@"锁车" icon:@"lock.fill" large:YES];self.lockButton.silver=YES;self.lockButton.backgroundColor=UIColor.clearColor;self.lockButton.layer.borderColor=UIColor.clearColor.CGColor;
    [self.lockButton addTarget:self action:@selector(lockPressed) forControlEvents:UIControlEventTouchUpInside];
    self.unlockButton=[self key:@"解锁" icon:@"lock.open" large:NO];[self.unlockButton addTarget:self action:@selector(unlockPressed) forControlEvents:UIControlEventTouchUpInside];
    self.controlGrid=Stack(@[],NO,12);
    self.messageLabel=Label(@"正在恢复登录…",13,UIFontWeightRegular,RemoteColor(.70));self.messageLabel.textAlignment=NSTextAlignmentCenter;
    self.activity=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];self.activity.color=RemoteColor(.75);self.activity.hidesWhenStopped=YES;
    UIStackView *feedback=Stack(@[self.activity,self.messageLabel],YES,8);feedback.alignment=UIStackViewAlignmentCenter;feedback.distribution=UIStackViewDistributionFill;
    UIStackView *stack=Stack(@[brandRow,led,self.controlGrid,feedback],NO,18);stack.translatesAutoresizingMaskIntoConstraints=NO;[remote addSubview:stack];
    NSLayoutConstraint *width=[remote.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-32];width.priority=999;
    [NSLayoutConstraint activateConstraints:@[[scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],[scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],[scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],[scroll.contentLayoutGuide.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],[remote.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:14],[remote.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-30],[remote.centerXAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.centerXAnchor],width,[remote.widthAnchor constraintLessThanOrEqualToConstant:440],[remote.leadingAnchor constraintGreaterThanOrEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:16],[remote.trailingAnchor constraintLessThanOrEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-16],[stack.topAnchor constraintEqualToAnchor:remote.topAnchor constant:24],[stack.bottomAnchor constraintEqualToAnchor:remote.bottomAnchor constant:-62],[stack.leadingAnchor constraintEqualToAnchor:remote.leadingAnchor constant:22],[stack.trailingAnchor constraintEqualToAnchor:remote.trailingAnchor constant:-22]]];
    [self setControlsEnabled];
}
- (void)setMessage:(NSString *)text busy:(BOOL)busy {
    self.messageLabel.text=text;if(busy) [self.activity startAnimating];else [self.activity stopAnimating];
}
- (void)startSession {
    if(self.sessionLoading) return;
    if([NSProcessInfo.processInfo.environment[@"MC_CAPABILITY_SURVEY"] isEqual:@"1"]) {[MCCapabilitySurvey runWithProgress:^(NSString *message){[self setMessage:message busy:YES];}];return;}
    NSString *token=[NSUserDefaults.standardUserDefaults stringForKey:@"imported.idToken"];
    if(!token.length) {[self setMessage:@"尚无登录会话，请先完成登录接入" busy:NO];return;}
    self.sessionLoading=YES;[self setMessage:@"正在连接车辆服务…" busy:YES];
    [[MCSDK shared] initializeSDK:^(NSError *error){dispatch_async(dispatch_get_main_queue(),^{
        if(error) {self.sessionLoading=NO;[self setMessage:@"连接失败，下拉重试" busy:NO];return;}
        [[MCSDK shared] loginMBBWithIdentityToken:token completion:^(NSError *loginError){dispatch_async(dispatch_get_main_queue(),^{
            self.sessionLoading=NO;
            if(loginError) {[self setMessage:@"登录会话已失效，请重新登录" busy:NO];return;}[self loadCatalog];
        });}];
    });}];
}
- (MCVehicleInfo *)currentInfo {
    for(MCVehicleInfo *v in self.vehicles) if([v.vin isEqual:self.currentVIN]) return v;return nil;
}
- (void)loadCatalog {
    [[MCSDK shared] catalogWithCompletion:^(NSArray<MCVehicleInfo *> *vehicles,NSError *error){dispatch_async(dispatch_get_main_queue(),^{
        if(!vehicles.count) {[self setMessage:@"未能加载车辆，下拉重试" busy:NO];return;}
        self.vehicles=vehicles;NSString *saved=[NSUserDefaults.standardUserDefaults stringForKey:@"vehicle.defaultVIN"];
        MCVehicleInfo *pick=nil;for(MCVehicleInfo *v in vehicles) if([v.vin isEqual:saved]) pick=v;
        if(!pick) {for(MCVehicleInfo *v in vehicles) if([v.displayName.uppercaseString containsString:@"GTI"]) {pick=v;break;}pick=pick?:vehicles.firstObject;[NSUserDefaults.standardUserDefaults setObject:pick.vin forKey:@"vehicle.defaultVIN"];}
        [self selectVIN:pick.vin];
    });}];
}
- (void)rebuildMenu {
    NSString *defaultVIN=[NSUserDefaults.standardUserDefaults stringForKey:@"vehicle.defaultVIN"];
    NSMutableArray *choices=[NSMutableArray array];
    for(MCVehicleInfo *v in self.vehicles) {
        UIAction *a=[UIAction actionWithTitle:MCVehicleName(v.displayName) image:[UIImage systemImageNamed:@"car.side"] identifier:v.vin handler:^(__kindof UIAction *action){MCHapticSelect();[self selectVIN:v.vin];}];
        NSString *suffix=[v.vin substringFromIndex:MAX(0,(NSInteger)v.vin.length-6)];
        a.subtitle=[NSString stringWithFormat:@"%@年款 · 尾号 %@%@",v.modelYear?:@"—",suffix,[v.vin isEqual:defaultVIN]?@" · 默认启动":@""];
        a.state=[v.vin isEqual:self.currentVIN]?UIMenuElementStateOn:UIMenuElementStateOff;[choices addObject:a];
    }
    UIMenu *cars=[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline|UIMenuOptionsSingleSelection children:choices];
    BOOL isDefault=[defaultVIN isEqual:self.currentVIN];
    UIAction *setDefault=[UIAction actionWithTitle:isDefault?@"当前为默认车辆":@"将当前车辆设为默认" image:[UIImage systemImageNamed:isDefault?@"star.fill":@"star"] identifier:nil handler:^(__kindof UIAction *action){
        if(self.selecting || self.commandRunning || !self.currentVIN.length) return;MCHapticSelect();[NSUserDefaults.standardUserDefaults setObject:self.currentVIN forKey:@"vehicle.defaultVIN"];[self rebuildMenu];[self setMessage:@"默认车辆已保存，下次启动自动选择" busy:NO];
    }];if(isDefault) setDefault.attributes=UIMenuElementAttributesDisabled;
    self.navigationItem.leftBarButtonItem.menu=[UIMenu menuWithTitle:@"切换车辆" children:@[cars,[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[setDefault]]]];
    self.navigationItem.leftBarButtonItem.title=[NSString stringWithFormat:@"%@ ⌄",MCVehicleName([self currentInfo].displayName)];
}
- (void)selectVIN:(NSString *)vin {
    if(self.commandRunning || self.selecting) return;
    if([vin isEqual:self.currentVIN] && self.vehicleReady) return;
    self.selecting=YES;self.vehicleReady=NO;self.refreshing=NO;self.currentVIN=vin;NSUInteger generation=++self.generation;
    [self clearStatus];[self rebuildMenu];[self rebuildControls];[self setControlsEnabled];
    self.vehicleLabel.text=MCVehicleName([self currentInfo].displayName);[self setMessage:@"正在切换车辆…" busy:YES];
    [[MCSDK shared] selectVehicleWithVIN:vin completion:^(NSError *error){dispatch_async(dispatch_get_main_queue(),^{
        if(generation!=self.generation) return;
        self.selecting=NO;self.vehicleReady=!error;[self setControlsEnabled];
        if(error) {[self setMessage:@"切换失败，请重新选择车辆" busy:NO];MCHapticResult(NO);return;}[self refreshStatus];
    });}];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,30*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        if(self.selecting && generation==self.generation) {self.generation++;self.selecting=NO;self.vehicleReady=NO;[self setControlsEnabled];[self setMessage:@"切换超时，请重试" busy:NO];MCHapticResult(NO);}
    });
}
- (void)clearStatus {self.rangeLabel.text=@"—";self.fuelLabel.text=@"— %";self.mileageLabel.text=@"总里程 — km";self.snapshotLabel.text=@"正在读取车况…";self.bodyLabel.text=@"门窗状态待更新";}
- (void)setControlsEnabled {
    BOOL enabled=self.vehicleReady && !self.selecting && !self.commandRunning;
    for(UIButton *b in self.controlButtons) {b.enabled=enabled;b.alpha=enabled?1:.35;}
    BOOL supportsLocks=[[self currentInfo].features containsObject:@"lockUnlockFeature"];
    self.lockButton.enabled=enabled && supportsLocks;self.unlockButton.enabled=enabled && supportsLocks;self.lockButton.alpha=self.lockButton.enabled?1:.35;self.unlockButton.alpha=self.unlockButton.enabled?1:.35;
    self.navigationItem.leftBarButtonItem.enabled=!self.selecting && !self.commandRunning;
    self.navigationItem.rightBarButtonItem.enabled=self.vehicleReady;
    self.refreshButton.enabled=self.vehicleReady && !self.refreshing && !self.commandRunning;
}
- (void)rebuildControls {
    for(UIView *v in self.controlGrid.arrangedSubviews) {[self.controlGrid removeArrangedSubview:v];[v removeFromSuperview];}
    self.controlButtons=[NSMutableArray arrayWithObjects:self.lockButton,self.unlockButton,nil];
    NSArray *features=[self currentInfo].features;NSMutableArray *keys=[NSMutableArray array];
    NSArray *specs=@[@[@"车窗",@"car.side.air.fresh",@"lockUnlockFeature",@[@"车窗通风",@"车窗全开",@"车窗全关"]],@[@"闪灯",@"light.beacon.max",@"honkFlashFeature",@[@"闪灯"]],@[@"鸣笛",@"speaker.wave.2",@"honkFlashFeature",@[@"鸣笛并闪灯"]],@[@"发动机",@"engine.combustion",@"remoteStartFeature",@[@"启动发动机",@"停止发动机"]],@[@"空调",@"fan",@"climaterFeature",@[@"开启空调 · 22℃",@"关闭空调"]],@[@"辅助加热",@"heat.waves",@"auxiliaryHeatingFeature",@[@"开启辅助加热",@"关闭辅助加热"]]];
    for(NSArray *spec in specs) {
        if(![features containsObject:spec[2]]) continue;
        MCRemoteKey *b=[self key:spec[0] icon:spec[1] large:NO];NSMutableArray *actions=[NSMutableArray array];
        for(NSString *title in spec[3]) [actions addObject:[UIAction actionWithTitle:title image:nil identifier:nil handler:^(__kindof UIAction *action){MCHapticSelect();[self confirmCommand:title];}]];
        if(actions.count>1) {b.menu=[UIMenu menuWithTitle:spec[0] children:actions];b.showsMenuAsPrimaryAction=YES;b.showsDisclosure=YES;}
        else [b addTarget:self action:@selector(singleKeyPressed:) forControlEvents:UIControlEventTouchUpInside];
        [keys addObject:b];
    }
    UIView *pad=[UIView new];[pad.heightAnchor constraintEqualToConstant:262].active=YES;
    [self.controlGrid addArrangedSubview:pad];
    void (^place)(UIButton *,CGFloat,CGFloat,CGFloat,CGFloat)=^(UIButton *button,CGFloat x,CGFloat y,CGFloat w,CGFloat h){
        button.translatesAutoresizingMaskIntoConstraints=NO;[pad addSubview:button];button.layer.cornerRadius=MIN(w,h)/2;
        [NSLayoutConstraint activateConstraints:@[[button.centerXAnchor constraintEqualToAnchor:pad.centerXAnchor constant:x],[button.topAnchor constraintEqualToAnchor:pad.topAnchor constant:y],[button.widthAnchor constraintEqualToConstant:w],[button.heightAnchor constraintEqualToConstant:h]]];
    };
    place(self.unlockButton,0,0,88,68);place(self.lockButton,0,80,104,104);
    NSArray *positions=@[@[@(-110),@94,@78,@78],@[@110,@94,@78,@78],@[@(-71),@190,@82,@72],@[@71,@190,@82,@72]];
    for(NSUInteger i=0;i<MIN(keys.count,4);i++) {NSArray *p=positions[i];place(keys[i],[p[0] doubleValue],[p[1] doubleValue],[p[2] doubleValue],[p[3] doubleValue]);}
    for(NSUInteger i=4;i<keys.count;i++) [self.controlGrid addArrangedSubview:keys[i]];

}
- (void)refreshPressed {
    MCHapticPress();if(self.selecting || self.commandRunning) {[self.refreshControl endRefreshing];return;}
    if(!self.vehicles.count) {[self.refreshControl endRefreshing];[self startSession];return;}
    if(!self.vehicleReady) {[self.refreshControl endRefreshing];[self selectVIN:self.currentVIN];return;}
    [self refreshStatus];
}
- (void)refreshStatus {
    if(self.refreshing || !self.vehicleReady) {[self.refreshControl endRefreshing];return;}
    self.refreshing=YES;NSUInteger generation=self.generation,request=++self.refreshGeneration;NSString *vin=[self.currentVIN copy];[self setControlsEnabled];[self setMessage:@"正在读取最新车况记录…" busy:YES];
    [[MCSDK shared] informationForKey:@"vehicleStatus" completion:^(id value,NSError *error){
        if(generation!=self.generation || request!=self.refreshGeneration || ![vin isEqual:self.currentVIN]) return;
        self.refreshing=NO;[self.refreshControl endRefreshing];[self setControlsEnabled];
        if(error || ![value isKindOfClass:NSDictionary.class]) {[self setMessage:@"车况读取失败，可下拉重试" busy:NO];MCHapticResult(NO);return;}
        NSDictionary *s=value;
        NSDictionary *rangeValue=[s[@"primaryEngineRange"] isKindOfClass:NSDictionary.class]?s[@"primaryEngineRange"]:@{};
        NSDictionary *fuelValue=[s[@"fuelLevel"] isKindOfClass:NSDictionary.class]?s[@"fuelLevel"]:@{};
        NSDictionary *mileageValue=[s[@"mileage"] isKindOfClass:NSDictionary.class]?s[@"mileage"]:@{};
        id range=rangeValue[@"range"],fuel=fuelValue[@"level"],mileage=mileageValue[@"mileage"];
        NSNumberFormatter *nf=[NSNumberFormatter new];nf.numberStyle=NSNumberFormatterDecimalStyle;
        self.rangeLabel.text=range && range!=NSNull.null?[range description]:@"—";
        self.fuelLabel.text=fuel && fuel!=NSNull.null?[NSString stringWithFormat:@"%@ %%",fuel]:@"— %";
        self.mileageLabel.text=[NSString stringWithFormat:@"总里程 %@ km",[mileage isKindOfClass:NSNumber.class]?[nf stringFromNumber:mileage]:@"—"];
        self.snapshotLabel.text=s[@"timestamp"] && s[@"timestamp"]!=NSNull.null?[NSString stringWithFormat:@"车况采集于 %@",MCFriendlyValue(s[@"timestamp"],@"timestamp")]:@"车辆未提供采集时间";
        [self setMessage:@"车况已读取" busy:NO];
        [[MCSDK shared] rawStatusReportForVIN:vin completion:^(NSString *xml,NSError *rawError){
            if(generation!=self.generation || request!=self.refreshGeneration || ![vin isEqual:self.currentVIN] || rawError) return;
            NSArray *fields=[[MCSDK shared] parseRawXML:xml];NSMutableDictionary *byID=[NSMutableDictionary dictionary];for(NSDictionary *f in fields) if(f[@"id"]) byID[f[@"id"]]=f;
            BOOL allLocked=YES,known=YES;for(NSString *i in @[@"0x0301040001",@"0x0301040004",@"0x0301040007",@"0x030104000A"]) {NSString *text=byID[i][@"textId"];if(![text isEqual:@"door_locked"]) allLocked=NO;if(![text isEqual:@"door_locked"] && ![text isEqual:@"door_unlocked"]) known=NO;}
            BOOL windowsClosed=YES,windowsKnown=YES;for(NSString *i in @[@"0x0301050002",@"0x0301050004",@"0x0301050006",@"0x0301050008"]) {NSString *v=byID[i][@"value"];if(!v.length) windowsKnown=NO;else if(v.doubleValue!=0) windowsClosed=NO;}
            self.bodyLabel.text=[NSString stringWithFormat:@"%@  ·  %@",known?(allLocked?@"四门已锁":@"车门未全锁"):@"门锁状态未知",windowsKnown?(windowsClosed?@"四窗已关":@"车窗未全关"):@"车窗状态未知"];
        }];
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,30*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        if(self.refreshing && generation==self.generation && request==self.refreshGeneration) {self.refreshGeneration++;self.refreshing=NO;[self.refreshControl endRefreshing];[self setControlsEnabled];[self setMessage:@"读取超时，请下拉重试" busy:NO];MCHapticResult(NO);}
    });
}
- (void)openInformation {
    if(!self.vehicleReady) return;MCHapticSelect();__weak typeof(self) weakSelf=self;
    MCInformationViewController *vc=[[MCInformationViewController alloc] initWithVehicle:[self currentInfo] currentVIN:^NSString *{return weakSelf.currentVIN;}];[self.navigationController pushViewController:vc animated:YES];
}
- (void)singleKeyPressed:(UIButton *)button {[self confirmCommand:[button.accessibilityLabel isEqual:@"鸣笛"]?@"鸣笛并闪灯":button.accessibilityLabel];}
- (void)lockPressed {[self confirmCommand:@"锁车"];}
- (void)unlockPressed {[self confirmCommand:@"解锁"];}
- (void)confirmCommand:(NSString *)command {
    if(!self.vehicleReady || self.commandRunning || self.selecting) return;
    NSString *vin=[self.currentVIN copy];NSUInteger generation=self.generation;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:command message:[NSString stringWithFormat:@"对 %@（尾号 %@）执行此操作？",MCVehicleName([self currentInfo].displayName),[vin substringFromIndex:MAX(0,(NSInteger)vin.length-6)]] preferredStyle:UIAlertControllerStyleAlert];
    BOOL engine=[command isEqual:@"启动发动机"];
    BOOL protected=engine || [@[@"锁车",@"解锁",@"车窗通风",@"车窗全开",@"车窗全关"] containsObject:command];
    if(protected) {
        alert.message=[alert.message stringByAppendingString:engine?@"\n请输入车机安全码，仅本次使用。\n请确认车辆停放安全、周围通风良好。":@"\n如车辆要求安全码，请在此输入；仅本次使用。"];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *tf){tf.secureTextEntry=YES;tf.keyboardType=UIKeyboardTypeNumberPad;tf.placeholder=engine?@"SPIN 安全码":@"SPIN 安全码（如需）";}];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a){MCHapticSelect();}]];
    [alert addAction:[UIAlertAction actionWithTitle:command style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        MCHapticPress();if(generation!=self.generation || ![vin isEqual:self.currentVIN] || self.commandRunning) return;
        NSString *spin=[alert.textFields.firstObject.text copy];alert.textFields.firstObject.text=@"";if([command isEqual:@"启动发动机"] && !spin.length) {[self setMessage:@"未输入安全码，操作已取消" busy:NO];MCHapticResult(NO);return;}
        [self runCommand:command spin:spin];
    }]];[self presentViewController:alert animated:YES completion:nil];
}
- (void)runCommand:(NSString *)command spin:(NSString *)spin {
    self.commandRunning=YES;NSUInteger generation=self.generation,operation=++self.commandGeneration;NSString *vin=[self.currentVIN copy];[self setControlsEnabled];[self setMessage:[NSString stringWithFormat:@"正在%@…",command] busy:YES];
    __block BOOL finished=NO;
    void (^finish)(NSInteger,NSString *)=^(NSInteger result,NSString *status){dispatch_async(dispatch_get_main_queue(),^{
        if(finished || generation!=self.generation || operation!=self.commandGeneration || ![vin isEqual:self.currentVIN]) return;
        finished=YES;self.commandRunning=NO;[self setControlsEnabled];[self setMessage:[NSString stringWithFormat:@"%@：%@",command,status] busy:NO];if(result>=0) MCHapticResult(result==1);else MCHapticSelect();
    });};
    void (^ok)(NSString *)=^(NSString *status){
        NSString *s=status.lowercaseString;
        if([s containsString:@"inprogress"] || [s containsString:@"in_progress"] || [s containsString:@"pending"] || [s containsString:@"queued"]) {dispatch_async(dispatch_get_main_queue(),^{if(!finished) [self setMessage:[NSString stringWithFormat:@"%@请求处理中…",command] busy:YES];});return;}
        if([s containsString:@"fail"] || [s containsString:@"error"] || [s containsString:@"reject"]) finish(0,@"车辆服务返回未完成，请刷新状态后确认");
        else if([s containsString:@"success"] || [s containsString:@"succeed"]) finish(1,@"车辆服务已确认完成");
        else finish(-1,@"已收到回执，请刷新车况确认结果");
    };
    void (^fail)(NSString *)=^(NSString *s){finish(0,s);};MCSDK *sdk=MCSDK.shared;
    NSDictionary<NSString *,void (^)(void)> *commands=@{
        @"锁车":^{[sdk lockVehicle:ok error:fail];},@"解锁":^{[sdk unlockVehicle:ok error:fail];},@"闪灯":^{[sdk flashLights:ok error:fail];},@"鸣笛并闪灯":^{[sdk honkAndFlash:ok error:fail];},@"车窗通风":^{[sdk windowVenting:ok error:fail];},@"车窗全开":^{[sdk windowOpen:ok error:fail];},@"车窗全关":^{[sdk windowClose:ok error:fail];},@"开启空调 · 22℃":^{[sdk climateStart:22 onStatus:ok error:fail];},@"关闭空调":^{[sdk climateStop:ok error:fail];},@"开启辅助加热":^{[sdk auxHeatStart:ok error:fail];},@"关闭辅助加热":^{[sdk auxHeatStop:ok error:fail];},@"启动发动机":^{[sdk engineStartWithSpin:spin onStatus:ok error:fail];},@"停止发动机":^{[sdk engineStop:ok error:fail];}
    };
    sdk.spinCode=spin;
    void (^run)(void)=commands[command];if(run) run();else finish(NO,@"当前操作不可用");
    sdk.spinCode=nil;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,135*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(!finished) finish(NO,@"未取得最终结果，请先查看车辆状态再重试");});
}
@end
