#import "CarControlOnly.h"
#import <objc/runtime.h>

static id ReadValue(id object, NSString *key) {
    @try { return [object valueForKey:key]; }
    @catch (NSException *exception) { return nil; }
}

// Decode the stored model through its coding contract; Swift fields are not KVC getters.
@interface CCOVehicleRecord : NSObject <NSCoding>
@property(nonatomic, copy) NSString *vin;
@property(nonatomic, copy) NSString *operateVehicleModelName;
@property(nonatomic, copy) NSString *modelName;
@property(nonatomic, copy) NSString *seriesName;
@property(nonatomic, copy) NSString *licensePlateNumber;
@property(nonatomic) BOOL isDefaultVehicle;
@end
@implementation CCOVehicleRecord
- (instancetype)initWithCoder:(NSCoder *)coder {
    if ((self = [super init])) {
        for (NSString *key in @[@"vin", @"operateVehicleModelName", @"modelName", @"seriesName", @"licensePlateNumber"]) {
            id value = [coder decodeObjectForKey:key];
            if ([value isKindOfClass:NSString.class]) [self setValue:value forKey:key];
        }
        self.isDefaultVehicle = [[coder decodeObjectForKey:@"isDefaultVehicle"] boolValue];
    }
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder {}
@end

static NSArray *AccountVehicles(void) {
    NSData *data = [NSUserDefaults.standardUserDefaults dataForKey:@"com.oneapp.coreentity.vehicles"];
    if (!data) return @[];
    static NSData *cachedData;
    static NSArray *cachedVehicles;
    if ([cachedData isEqualToData:data]) return cachedVehicles ?: @[];
    @try {
        NSKeyedUnarchiver *reader = [[NSKeyedUnarchiver alloc] initForReadingFromData:data error:nil];
        reader.requiresSecureCoding = NO;
        [reader setClass:CCOVehicleRecord.class forClassName:@"FVVehicle"];
        id result = [reader decodeObjectForKey:NSKeyedArchiveRootObjectKey];
        [reader finishDecoding];
        cachedData = data;
        cachedVehicles = [result isKindOfClass:NSArray.class] ? result : @[];
        return cachedVehicles;
    } @catch (NSException *exception) { return @[]; }
}

static NSString *VehicleVIN(id vehicle) {
    id value = ReadValue(vehicle, @"vin");
    return [value isKindOfClass:NSString.class] ? value : @"";
}

static NSString *VehicleName(id vehicle) {
    NSString *model = ReadValue(vehicle, @"operateVehicleModelName");
    if (!model.length) model = ReadValue(vehicle, @"modelName");
    NSString *series = ReadValue(vehicle, @"seriesName");
    if (series.length && model.length && ![model containsString:series]) return [NSString stringWithFormat:@"%@ %@", series, model];
    if (model.length) return model;
    if (series.length) return series;
    NSString *vin = VehicleVIN(vehicle);
    return vin.length >= 6 ? [@"车辆 · " stringByAppendingString:[vin substringFromIndex:vin.length-6]] : @"车辆信息未就绪";
}

static NSString *DefaultVIN(void) {
    for (id vehicle in AccountVehicles()) {
        if ([ReadValue(vehicle, @"isDefaultVehicle") boolValue]) return VehicleVIN(vehicle);
    }
    return @"";
}

static void VisitViews(UIView *view, void (^visit)(UIView *)) {
    visit(view);
    for (UIView *child in view.subviews.copy) VisitViews(child, visit);
}

static NSString *ViewText(UIView *view);
static BOOL IsDefaultActionTitle(NSString *title) {
    return [@[@"设为默认", @"设为默认车", @"设为默认车辆", @"设置默认车辆"] containsObject:title ?: @""];
}

static NSString *VINShownInView(UIView *view) {
    __block NSString *result = @"";
    NSArray *vehicles = AccountVehicles();
    VisitViews(view, ^(UIView *child) {
        NSString *text = ViewText(child);
        for (id vehicle in vehicles) {
            NSString *vin = VehicleVIN(vehicle);
            if (vin.length && [text containsString:vin]) result = vin;
        }
    });
    return result;
}

static BOOL DefaultActionInRow(UITableViewCell *row, BOOL perform) {
    __block UIButton *button = nil;
    VisitViews(row, ^(UIView *view) {
        if ([view isKindOfClass:UIButton.class] && IsDefaultActionTitle(((UIButton *)view).currentTitle)) button = (UIButton *)view;
    });
    if (button) {
        if (perform) [button sendActionsForControlEvents:UIControlEventTouchUpInside];
        return YES;
    }
    id tools = ReadValue(row, @"editToolsBar");
    if (![tools isKindOfClass:UICollectionView.class]) return NO;
    UICollectionView *collection = tools;
    collection.hidden = NO;
    NSLayoutConstraint *height = ReadValue(row, @"editToolsBarHeightConstraint");
    if ([height isKindOfClass:NSLayoutConstraint.class] && height.constant < 44) height.constant = 44;
    [row setNeedsLayout];
    [row layoutIfNeeded];
    id<UICollectionViewDataSource> source = collection.dataSource;
    NSInteger sections = [source respondsToSelector:@selector(numberOfSectionsInCollectionView:)] ? [source numberOfSectionsInCollectionView:collection] : 1;
    for (NSInteger section = 0; section < sections; section++) {
        NSInteger count = [source collectionView:collection numberOfItemsInSection:section];
        for (NSInteger item = 0; item < count; item++) {
            NSIndexPath *path = [NSIndexPath indexPathForItem:item inSection:section];
            [collection scrollToItemAtIndexPath:path atScrollPosition:UICollectionViewScrollPositionCenteredHorizontally animated:NO];
            [collection layoutIfNeeded];
            UICollectionViewCell *cell = [collection cellForItemAtIndexPath:path];
            __block BOOL matches = NO;
            VisitViews(cell, ^(UIView *child) { if (IsDefaultActionTitle(ViewText(child))) matches = YES; });
            if (matches) {
                if (perform && [collection.delegate respondsToSelector:@selector(collectionView:didSelectItemAtIndexPath:)]) {
                    [collection.delegate collectionView:collection didSelectItemAtIndexPath:path];
                }
                return YES;
            }
        }
    }
    return NO;
}

@class CCOVehiclePicker;
static __weak CCOVehiclePicker *PendingPicker;
static IMP NavigationPush;
static IMP FVNavigationPush;
static IMP FVTransitionPush;

@interface CCOVehiclePicker : UIViewController
@property(nonatomic, strong) UIViewController *nativeController;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *nativeLocations;
@property(nonatomic, copy) NSString *pendingVIN;
@property(nonatomic) NSUInteger pollCount;
@property(nonatomic, copy) void (^changed)(void);
- (void)acceptNativeController:(UIViewController *)controller;
- (void)loadNativeVehicles;
- (void)chooseVIN:(NSString *)vin;
@end

@implementation CCOVehiclePicker
- (instancetype)init {
    if ((self = [super init])) self.nativeLocations = [NSMutableDictionary dictionary];
    return self;
}
- (void)loadNativeVehicles {
    if (self.pendingVIN || PendingPicker || !self.parentViewController.view.window) return;
    self.pollCount = 0;
    if (!self.nativeController) {
        PendingPicker = self;
        CCOOpenOriginalRoute(@"faw-vw://vehicle/list");
    } else [self collectNativeRows];
}
- (void)acceptNativeController:(UIViewController *)controller {
    PendingPicker = nil;
    self.nativeController = controller;
    [self addChildViewController:controller];
    controller.view.frame = CGRectMake(0, 0, self.parentViewController.view.bounds.size.width, 900);
    [self.view addSubview:controller.view];
    [controller didMoveToParentViewController:self];
    NSLog(@"CCO original configured vehicle controller captured");
    [self collectNativeRows];
}
- (void)collectNativeRows {
    [self.nativeController.view setNeedsLayout];
    [self.nativeController.view layoutIfNeeded];
    VisitViews(self.nativeController.view, ^(UIView *view) {
        if (![view isKindOfClass:UITableView.class]) return;
        UITableView *table = (UITableView *)view;
        for (NSInteger section = 0; section < table.numberOfSections; section++) {
            for (NSInteger item = 0; item < [table numberOfRowsInSection:section]; item++) {
                NSIndexPath *path = [NSIndexPath indexPathForRow:item inSection:section];
                [table scrollToRowAtIndexPath:path atScrollPosition:UITableViewScrollPositionTop animated:NO];
                [table layoutIfNeeded];
                UITableViewCell *cell = [table cellForRowAtIndexPath:path];
                NSString *vin = VINShownInView(cell);
                BOOL hasAction = vin.length && DefaultActionInRow(cell, NO);
                if (self.pollCount == 0) NSLog(@"CCO native row class=%@ VINMatched=%d action=%d", NSStringFromClass(cell.class), vin.length > 0, hasAction);
                if (hasAction) self.nativeLocations[vin] = @{@"table": table, @"path": path};
            }
        }
    });
    if (self.changed) self.changed();
    NSLog(@"CCO dropdown records=%lu nativeActions=%lu defaultMatched=%d", (unsigned long)AccountVehicles().count, (unsigned long)self.nativeLocations.count, DefaultVIN().length > 0);
    if (++self.pollCount < 12 && self.nativeLocations.count < MAX((NSInteger)AccountVehicles().count - 1, 0) && self.view.window) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{ [self collectNativeRows]; });
    }
}
- (void)chooseVIN:(NSString *)vin {
    if (!vin.length || [vin isEqualToString:DefaultVIN()] || self.pendingVIN) return;
    NSDictionary *location = self.nativeLocations[vin];
    if (!location) { [self loadNativeVehicles]; return; }
    UITableView *table = location[@"table"];
    NSIndexPath *rowPath = location[@"path"];
    [table scrollToRowAtIndexPath:rowPath atScrollPosition:UITableViewScrollPositionTop animated:NO];
    [table layoutIfNeeded];
    UITableViewCell *row = [table cellForRowAtIndexPath:rowPath];
    if (![VINShownInView(row) isEqualToString:vin] || !DefaultActionInRow(row, NO)) {
        [self showError:@"车辆列表已更新，请稍后重新选择"]; return;
    }
    self.pendingVIN = vin;
    self.pollCount = 0;
    if (self.changed) self.changed();
    DefaultActionInRow(row, YES);
    [self pollSwitch];
}
- (void)pollSwitch {
    if (!self.pendingVIN) return;
    if ([DefaultVIN() isEqualToString:self.pendingVIN]) {
        self.pendingVIN = nil;
        [self.nativeLocations removeAllObjects];
        NSLog(@"CCO native default vehicle switch confirmed");
        if (self.changed) self.changed();
        CCOOpenOriginalRoute(@"faw-vw://carnet/carHome");
        [self.parentViewController beginAppearanceTransition:YES animated:NO];
        [self.parentViewController endAppearanceTransition];
        return;
    }
    if (++self.pollCount >= 40) {
        self.pendingVIN = nil;
        if (self.changed) self.changed();
        [self showError:@"切换未完成，请检查网络后重试"]; return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{ [self pollSwitch]; });
}
- (void)showError:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"切换车辆" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self.parentViewController presentViewController:alert animated:YES completion:nil];
}
@end

static BOOL CaptureConfiguredVehicle(UIViewController *controller) {
    if (PendingPicker && [NSStringFromClass(controller.class) isEqualToString:@"OneApp_VehicleManagement.VehiclesViewController"]) {
        [PendingPicker acceptNativeController:controller];
        return YES;
    }
    return NO;
}
static void CaptureVehicleController(UINavigationController *self, SEL selector, UIViewController *controller, BOOL animated) {
    if (!CaptureConfiguredVehicle(controller)) ((void (*)(id, SEL, id, BOOL))NavigationPush)(self, selector, controller, animated);
}
static void CaptureFVVehicleController(UINavigationController *self, SEL selector, UIViewController *controller, BOOL animated) {
    if (!CaptureConfiguredVehicle(controller)) ((void (*)(id, SEL, id, BOOL))FVNavigationPush)(self, selector, controller, animated);
}
static void CaptureFVTransitionController(UINavigationController *self, SEL selector, UIViewController *controller, BOOL animated) {
    if (!CaptureConfiguredVehicle(controller)) ((void (*)(id, SEL, id, BOOL))FVTransitionPush)(self, selector, controller, animated);
}

@interface CCOVehiclePageActions : NSObject
@property(nonatomic, weak) UIViewController *page;
@property(nonatomic, strong) UIButton *button;
@property(nonatomic, weak) UILabel *nameLabel;
@property(nonatomic, strong) NSLayoutConstraint *titleWidth;
@property(nonatomic, strong) NSMutableSet<NSIndexPath *> *excludedPaths;
@property(nonatomic, copy) NSString *vehicleVIN;
@property(nonatomic, strong) CCOVehiclePicker *picker;
- (void)updateMenu;
@end

@implementation CCOVehiclePageActions
- (void)updateMenu {
    NSMutableArray *items = [NSMutableArray array];
    NSString *currentVIN = DefaultVIN();
    __weak CCOVehiclePicker *picker = self.picker;
    for (id vehicle in AccountVehicles()) {
        NSString *vin = VehicleVIN(vehicle);
        if (!vin.length) continue;
        UIAction *item = [UIAction actionWithTitle:VehicleName(vehicle) image:nil identifier:vin handler:^(__kindof UIAction *action) { [picker chooseVIN:vin]; }];
        item.state = currentVIN.length && [vin isEqualToString:currentVIN] ? UIMenuElementStateOn : UIMenuElementStateOff;
        item.subtitle = [vin isEqualToString:currentVIN] ? @"当前车辆" : (self.picker.pendingVIN ? @"正在切换…" : @"切换到此车辆");
        if (self.picker.pendingVIN || !self.picker.nativeLocations[vin]) item.attributes = UIMenuElementAttributesDisabled;
        [items addObject:item];
    }
    self.button.menu = [UIMenu menuWithTitle:@"切换车辆" image:nil identifier:nil options:UIMenuOptionsSingleSelection children:items];
}
- (void)prepareVehicles {
    [self.picker loadNativeVehicles];
}
@end

static const void *ActionsKey = &ActionsKey;
static IMP VehicleAppeared;
static IMP VehicleLayout;
static IMP VehicleItemSize;
static BOOL TestPickerShown;

static NSString *ViewText(UIView *view) {
    if ([view isKindOfClass:UILabel.class]) return ((UILabel *)view).text;
    if ([view isKindOfClass:UIButton.class]) return ((UIButton *)view).currentTitle;
    return nil;
}

static BOOL IsMarketingText(NSString *text) {
    return [@[@"车联权益", @"自定义", @"即刻加油", @"立即加油", @"领券", @"众惠卡"] containsObject:text ?: @""];
}

static void CleanVehiclePage(CCOVehiclePageActions *actions) {
    UIViewController *page = actions.page;
    if (!page.viewIfLoaded) return;
    NSString *vin = DefaultVIN();
    if (![actions.vehicleVIN isEqualToString:vin]) {
        actions.vehicleVIN = vin;
        [actions.excludedPaths removeAllObjects];
    }
    if (!actions.nameLabel) {
        __block UILabel *nameLabel = nil;
        NSString *name = @"";
        for (id vehicle in AccountVehicles()) if ([VehicleVIN(vehicle) isEqualToString:vin]) name = VehicleName(vehicle);
        VisitViews(page.view, ^(UIView *view) {
            if (![view isKindOfClass:UILabel.class]) return;
            UILabel *label = (UILabel *)view;
            CGRect frame = [label convertRect:label.bounds toView:page.view];
            if (label.text.length > 2 && frame.origin.y < page.view.safeAreaInsets.top + 85 && frame.origin.x < page.view.bounds.size.width / 2 &&
                ([label.text containsString:name] || [name containsString:label.text] || frame.origin.x < 48)) nameLabel = label;
        });
        if (nameLabel) {
            actions.nameLabel = nameLabel;
            UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
            actions.button = button;
            button.translatesAutoresizingMaskIntoConstraints = NO;
            button.accessibilityLabel = @"切换车辆";
            [button setImage:[UIImage systemImageNamed:@"chevron.down" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:10 weight:UIImageSymbolWeightSemibold]] forState:UIControlStateNormal];
            button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentRight;
            button.tintColor = nameLabel.textColor;
            button.showsMenuAsPrimaryAction = YES;
            [button addTarget:actions action:@selector(prepareVehicles) forControlEvents:UIControlEventMenuActionTriggered];
            [nameLabel.superview addSubview:button];
            [NSLayoutConstraint activateConstraints:@[
                [button.leadingAnchor constraintEqualToAnchor:nameLabel.leadingAnchor constant:-4],
                (actions.titleWidth = [button.widthAnchor constraintEqualToConstant:100]),
                [button.centerYAnchor constraintEqualToAnchor:nameLabel.centerYAnchor],
                [button.heightAnchor constraintGreaterThanOrEqualToConstant:44]
            ]];
            [actions updateMenu];
            NSLog(@"CCO vehicle name dropdown installed");
        }
    }
    if (actions.nameLabel) {
        actions.button.accessibilityValue = actions.nameLabel.text;
        actions.titleWidth.constant = MIN(actions.nameLabel.intrinsicContentSize.width + 24, page.view.bounds.size.width - 132);
    }
    VisitViews(page.view, ^(UIView *view) {
        if (!IsMarketingText(ViewText(view))) return;
        UIView *ancestor = view;
        UICollectionViewCell *cell = nil;
        while (ancestor && ancestor != page.view) {
            if ([ancestor isKindOfClass:UICollectionViewCell.class]) { cell = (UICollectionViewCell *)ancestor; break; }
            ancestor = ancestor.superview;
        }
        if (cell) {
            __block BOOL hasControl = NO;
            VisitViews(cell, ^(UIView *child) {
                if ([@[@"启动引擎", @"开锁", @"上锁", @"车辆状态", @"闪灯", @"鸣笛", @"在线寻车", @"车窗", @"空调", @"充电"] containsObject:ViewText(child) ?: @""]) hasControl = YES;
            });
            if (!hasControl) {
                UIView *parent = cell.superview;
                while (parent && ![parent isKindOfClass:UICollectionView.class]) parent = parent.superview;
                UICollectionView *collection = (UICollectionView *)parent;
                NSIndexPath *path = [collection indexPathForCell:cell];
                cell.hidden = YES;
                if (path && ![actions.excludedPaths containsObject:path]) {
                    [actions.excludedPaths addObject:path];
                    dispatch_async(dispatch_get_main_queue(), ^{ [collection.collectionViewLayout invalidateLayout]; });
                }
                return;
            }
        }
        // For mixed rows, suppress only the individual feature container.
        UIView *container = view;
        if (!cell) {
            for (UIView *parent = view.superview; parent && parent != page.view; parent = parent.superview) {
                if ([parent isKindOfClass:UIControl.class]) { container = parent; break; }
                if (parent.bounds.size.height > 70) break;
                container = parent;
            }
        } else {
            while (container.superview && container.superview != cell.contentView) {
                UIView *parent = container.superview;
                __block BOOL containsControl = NO;
                VisitViews(parent, ^(UIView *child) {
                    if ([@[@"启动引擎", @"开锁", @"上锁", @"车辆状态", @"闪灯", @"鸣笛", @"在线寻车", @"车窗", @"空调", @"充电"] containsObject:ViewText(child) ?: @""]) containsControl = YES;
                });
                if (containsControl || [parent isKindOfClass:UIStackView.class]) break;
                container = parent;
            }
        }
        container.hidden = YES;
    });
}

static CCOVehiclePageActions *ConfigureVehiclePage(UIViewController *page) {
    CCOVehiclePageActions *actions = objc_getAssociatedObject(page, ActionsKey);
    if (actions) return actions;
    actions = [CCOVehiclePageActions new];
    actions.page = page;
    actions.excludedPaths = [NSMutableSet set];
    objc_setAssociatedObject(page, ActionsKey, actions, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    actions.picker = [CCOVehiclePicker new];
    [page addChildViewController:actions.picker];
    actions.picker.view.frame = CGRectMake(-2000, 0, page.view.bounds.size.width, 900);
    actions.picker.view.userInteractionEnabled = NO;
    [page.view addSubview:actions.picker.view];
    [actions.picker didMoveToParentViewController:page];
    __weak CCOVehiclePageActions *weakActions = actions;
    actions.picker.changed = ^{ [weakActions updateMenu]; };
    CleanVehiclePage(actions);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC * 2), dispatch_get_main_queue(), ^{ [actions.picker loadNativeVehicles]; });
    NSLog(@"CCO vehicle dropdown coordinator installed");
    return actions;
}

static void VehiclePageAppeared(UIViewController *self, SEL selector, BOOL animated) {
    ((void (*)(id, SEL, BOOL))VehicleAppeared)(self, selector, animated);
    CCOVehiclePageActions *actions = ConfigureVehiclePage(self);
    CleanVehiclePage(actions);
    if (!TestPickerShown && [NSProcessInfo.processInfo.environment[@"CCO_TEST_PICKER"] isEqualToString:@"1"]) {
        TestPickerShown = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [actions.picker loadNativeVehicles]; });
    }
}

static void VehiclePageLayout(UIViewController *self, SEL selector) {
    ((void (*)(id, SEL))VehicleLayout)(self, selector);
    CCOVehiclePageActions *actions = objc_getAssociatedObject(self, ActionsKey);
    if (actions) CleanVehiclePage(actions);
}

static CGSize VehiclePageItemSize(id self, SEL selector, UICollectionView *collection, UICollectionViewLayout *layout, NSIndexPath *path) {
    CCOVehiclePageActions *actions = objc_getAssociatedObject(self, ActionsKey);
    if ([actions.excludedPaths containsObject:path]) return CGSizeMake(0, 0);
    return ((CGSize (*)(id, SEL, id, id, id))VehicleItemSize)(self, selector, collection, layout, path);
}

void CCOInstallVehiclePage(void) {
    if (!NavigationPush) CCOReplaceMethod(UINavigationController.class, @selector(pushViewController:animated:), (IMP)CaptureVehicleController, &NavigationPush);
    if (!FVNavigationPush) CCOReplaceMethod(NSClassFromString(@"FVNavigationController"), @selector(pushViewController:animated:), (IMP)CaptureFVVehicleController, &FVNavigationPush);
    if (!FVTransitionPush) CCOReplaceMethod(NSClassFromString(@"FVNavigationTransitionController"), @selector(pushViewController:animated:), (IMP)CaptureFVTransitionController, &FVTransitionPush);
    if (VehicleAppeared) return;
    Class cls = NSClassFromString(@"VWCarnet.MoscCarNetViewController");
    if (!cls) cls = NSClassFromString(@"_TtC8VWCarnet24MoscCarNetViewController");
    if (!cls) return;
    CCOReplaceMethod(cls, @selector(viewDidAppear:), (IMP)VehiclePageAppeared, &VehicleAppeared);
    CCOReplaceMethod(cls, @selector(viewDidLayoutSubviews), (IMP)VehiclePageLayout, &VehicleLayout);
    CCOReplaceMethod(cls, @selector(collectionView:layout:sizeForItemAtIndexPath:), (IMP)VehiclePageItemSize, &VehicleItemSize);
}
