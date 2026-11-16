#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "CarControlOnly.h"

static __weak UITabBarController *RootController;
static IMP RootDidAppear;
static IMP LoginDidAppear;
static IMP LoginDidDisappear;
static IMP AdvertisementDidLoad;
static IMP IntroductionDidLoad;
static IMP AgreementWillAppear;
static const void *PasswordConfigured = &PasswordConfigured;
static const void *StartupStepCompleted = &StartupStepCompleted;
static BOOL FlowScheduled;

BOOL CCOOpenOriginalRoute(NSString *route) {
    UIApplication *app = UIApplication.sharedApplication;
    id<UIApplicationDelegate> delegate = app.delegate;
    if (![delegate respondsToSelector:@selector(application:openURL:options:)]) return NO;
    BOOL accepted = [delegate application:app openURL:[NSURL URLWithString:route] options:@{}];
    NSLog(@"CCO requested route %@ return=%d", route, accepted);
    return accepted;
}

// Stored state selects the entry route. The original application validates and refreshes it.
static BOOL HasStoredSession(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSData *user = [defaults dataForKey:@"com.oneapp.coreentity.currentUser"];
    NSData *tokens = [defaults dataForKey:@"com.oneapp.coreentity.tokens"];
    return user.length > 0 && tokens.length > 0;
}

static BOOL ContainsController(UIViewController *controller, NSString *className) {
    if ([NSStringFromClass(controller.class) isEqualToString:className]) return YES;
    for (UIViewController *child in controller.childViewControllers) {
        if (ContainsController(child, className)) return YES;
    }
    return NO;
}

static void KeepVehicleTab(UITabBarController *root) {
    for (UIViewController *controller in root.viewControllers.copy) {
        // This wrapper switches to VWCarnet.CarSwitchViewController after authentication.
        if (ContainsController(controller, @"OneApp.CarController")) {
            root.selectedViewController = controller;
            root.tabBar.hidden = YES;
            NSLog(@"CCO native vehicle entry selected");
            return;
        }
    }
    NSLog(@"CCO vehicle wrapper not ready");
}

static void ScheduleCoreFlow(void) {
    if (FlowScheduled) return;
    FlowScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        FlowScheduled = NO;
        NSLog(@"CCO flow guard active=%ld root=%d window=%d presented=%@", (long)UIApplication.sharedApplication.applicationState, RootController != nil, RootController.viewIfLoaded.window != nil, NSStringFromClass(RootController.presentedViewController.class));
        UITabBarController *root = RootController;
        if (!root || !root.viewIfLoaded.window || root.presentedViewController) return;
        if (root.navigationController && root.navigationController.topViewController != root) return;
        KeepVehicleTab(root);
        if (!HasStoredSession()) {
            CCOOpenOriginalRoute(@"faw-vw://auth/login");
        }
    });
}

static void RootAppeared(UITabBarController *self, SEL selector, BOOL animated) {
    ((void (*)(id, SEL, BOOL))RootDidAppear)(self, selector, animated);
    RootController = self;
    CCOInstallVehiclePage();
    NSLog(@"CCO root appeared");
    ScheduleCoreFlow();
}

static void LoginAppeared(UIViewController *self, SEL selector, BOOL animated) {
    ((void (*)(id, SEL, BOOL))LoginDidAppear)(self, selector, animated);
    if (objc_getAssociatedObject(self, PasswordConfigured)) return;
    objc_setAssociatedObject(self, PasswordConfigured, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if ([self respondsToSelector:NSSelectorFromString(@"passwordInputContainer")] &&
        [self respondsToSelector:NSSelectorFromString(@"switchLoginByAccountTypeBtn")]) {
        UIView *password = [self valueForKey:@"passwordInputContainer"];
        UIButton *button = [self valueForKey:@"switchLoginByAccountTypeBtn"];
        if (password.hidden && [button.currentTitle containsString:@"密码"]) {
            [button sendActionsForControlEvents:UIControlEventTouchUpInside];
        }
    }
    if ([self respondsToSelector:NSSelectorFromString(@"confirmAgreementsBtn")]) {
        UIButton *agreement = [self valueForKey:@"confirmAgreementsBtn"];
        if (!agreement.selected) [agreement sendActionsForControlEvents:UIControlEventTouchUpInside];
        agreement.hidden = YES;
    }
    if ([self respondsToSelector:NSSelectorFromString(@"agreementsLabel")]) {
        UIView *label = [self valueForKey:@"agreementsLabel"];
        label.hidden = YES;
    }
    NSLog(@"CCO native login presented without agreement row");
}

static void LoginDisappeared(UIViewController *self, SEL selector, BOOL animated) {
    ((void (*)(id, SEL, BOOL))LoginDidDisappear)(self, selector, animated);
    if (!self.presentingViewController && !self.navigationController) ScheduleCoreFlow();
}

static void AdvertisementLoaded(UIViewController *self, SEL selector) {
    ((void (*)(id, SEL))AdvertisementDidLoad)(self, selector);
    // Hide before the first display and use the vendor's skip action to finish startup.
    self.view.hidden = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self respondsToSelector:NSSelectorFromString(@"skipButton")]) {
            UIButton *skip = [self valueForKey:@"skipButton"];
            [skip sendActionsForControlEvents:UIControlEventTouchUpInside];
            UIWindow *advertisementWindow = self.view.window;
            UIWindow *mainWindow = RootController.viewIfLoaded.window;
            if (advertisementWindow && mainWindow && advertisementWindow != mainWindow && advertisementWindow.rootViewController == self) {
                advertisementWindow.hidden = YES;
                [mainWindow makeKeyAndVisible];
            } else if (self.presentingViewController) {
                [self dismissViewControllerAnimated:NO completion:nil];
            }
            NSLog(@"CCO opening advertisement skipped");
            ScheduleCoreFlow();
        }
    });
}

static void IntroductionLoaded(UIViewController *self, SEL selector) {
    ((void (*)(id, SEL))IntroductionDidLoad)(self, selector);
    self.view.hidden = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self respondsToSelector:NSSelectorFromString(@"skipButton")]) {
            UIButton *skip = [self valueForKey:@"skipButton"];
            [skip sendActionsForControlEvents:UIControlEventTouchUpInside];
            NSLog(@"CCO first-install introduction skipped");
            ScheduleCoreFlow();
        }
    });
}

static void AgreementAppearing(UIViewController *self, SEL selector, BOOL animated) {
    ((void (*)(id, SEL, BOOL))AgreementWillAppear)(self, selector, animated);
    self.view.hidden = YES;
    if (objc_getAssociatedObject(self, StartupStepCompleted)) return;
    objc_setAssociatedObject(self, StartupStepCompleted, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIApplication.sharedApplication sendAction:NSSelectorFromString(@"authorizedBtnAction:") to:self from:nil forEvent:nil];
        NSLog(@"CCO standalone agreement continued");
        ScheduleCoreFlow();
    });
}

void CCOReplaceMethod(Class cls, SEL selector, IMP replacement, IMP *original) {
    if (!cls) return;
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return;
    *original = method_getImplementation(method);
    if (!class_addMethod(cls, selector, replacement, method_getTypeEncoding(method))) {
        method_setImplementation(class_getInstanceMethod(cls, selector), replacement);
    }
}

static NSDictionary *EmptyTrackingProperties(id self, SEL selector) {
    return @{};
}

static void EnableOriginalProxySetting(void) {
    Class cls = NSClassFromString(@"FV_CoreEntity.AppSetting");
    if (!cls) cls = NSClassFromString(@"_TtC13FV_CoreEntity10AppSetting");
    SEL shared = NSSelectorFromString(@"shared");
    if (![cls respondsToSelector:shared]) return;
    id settings = ((id (*)(id, SEL))objc_msgSend)(cls, shared);
    if (![[settings valueForKey:@"isProxyAllow"] boolValue]) {
        [settings setValue:@YES forKey:@"isProxyAllow"];
    }
    NSLog(@"CCO original proxy allowance=%d", [[settings valueForKey:@"isProxyAllow"] boolValue]);
}

__attribute__((constructor)) static void InstallCoreFlow(void) {
    EnableOriginalProxySetting();
    CCOInstallVehiclePage();
    // The vendor analytics getter synchronously waits during cold startup after restore.
    Class analytics = NSClassFromString(@"QTMobClick");
    Method tracking = class_getClassMethod(analytics, NSSelectorFromString(@"getGlobalProperties"));
    if (tracking) method_setImplementation(tracking, (IMP)EmptyTrackingProperties);

    CCOReplaceMethod(NSClassFromString(@"OneApp.RootViewController"), @selector(viewDidAppear:), (IMP)RootAppeared, &RootDidAppear);
    CCOReplaceMethod(NSClassFromString(@"OneApp_GeneralModules.AdViewController"), @selector(viewDidLoad), (IMP)AdvertisementLoaded, &AdvertisementDidLoad);
    CCOReplaceMethod(NSClassFromString(@"OneApp_GeneralModules.IntroduceViewController"), @selector(viewDidLoad), (IMP)IntroductionLoaded, &IntroductionDidLoad);
    CCOReplaceMethod(NSClassFromString(@"OneApp_Agreement.APPAgreementPopViewController"), @selector(viewWillAppear:), (IMP)AgreementAppearing, &AgreementWillAppear);
    Class login = NSClassFromString(@"OneApp_Account.AccountLoginViewController");
    CCOReplaceMethod(login, @selector(viewDidAppear:), (IMP)LoginAppeared, &LoginDidAppear);
    CCOReplaceMethod(login, @selector(viewDidDisappear:), (IMP)LoginDisappeared, &LoginDidDisappear);
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            CCOInstallVehiclePage();
            ScheduleCoreFlow();
        }];
        [[NSNotificationCenter defaultCenter] addObserverForName:NSUserDefaultsDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            static BOOL hadSession;
            BOOL hasSession = HasStoredSession();
            if (hadSession != hasSession) {
                hadSession = hasSession;
                ScheduleCoreFlow();
            }
        }];
    });
}
