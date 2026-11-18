// 仅 --ui-review 开发构建包含；遍历查询页并截图，绝不触发控制按键。
#import <UIKit/UIKit.h>
#import <objc/message.h>
static NSString *ReviewDirectory(void) {
    NSString *p=[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/ui-review"];
    [NSFileManager.defaultManager createDirectoryAtPath:p withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];return p;
}
static void Capture(UIViewController *vc,NSString *name) {
    UIWindow *w=vc.view.window;if(!w) return;
    UIGraphicsImageRenderer *r=[[UIGraphicsImageRenderer alloc] initWithSize:w.bounds.size];
    UIImage *image=[r imageWithActions:^(UIGraphicsImageRendererContext *ctx){[w drawViewHierarchyInRect:w.bounds afterScreenUpdates:YES];}];
    [UIImagePNGRepresentation(image) writeToFile:[ReviewDirectory() stringByAppendingPathComponent:[name stringByAppendingString:@".png"]] options:NSDataWritingAtomic|NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:nil];
}
static void Row(UINavigationController *nav,NSInteger index) {
    UITableViewController *vc=(id)nav.topViewController;
    if(![vc isKindOfClass:UITableViewController.class] || [vc.tableView numberOfRowsInSection:0]<=index) return;
    [vc.tableView.delegate tableView:vc.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:index inSection:0]];
}
static void Later(NSTimeInterval seconds,dispatch_block_t action) {dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(seconds*NSEC_PER_SEC)),dispatch_get_main_queue(),action);}
static void Review(UINavigationController *nav,NSUInteger retry) {
    UIViewController *home=nav.viewControllers.firstObject;
    if(!home.navigationItem.rightBarButtonItem.enabled) {if(retry<90) Later(1,^{Review(nav,retry+1);});return;}
    Capture(home,@"01-home");
    UIMenu *menu=home.navigationItem.leftBarButtonItem.menu;UIMenu *cars=(id)menu.children.firstObject;
    NSInteger checked=0;for(UIMenuElement *e in cars.children) if([e isKindOfClass:UIAction.class] && [(UIAction *)e state]==UIMenuElementStateOn) checked++;
    NSMutableDictionary *report=[@{@"selectedVehicleCount":@(checked),@"vehicleMenuCount":@(cars.children.count),@"physicalCommandsSent":@NO,@"scope":@"current vehicle only"} mutableCopy];
    ((void(*)(id,SEL))objc_msgSend)(home,NSSelectorFromString(@"openInformation"));
    UIViewController *information=nav.topViewController;
    Later(1,^{
        if(![nav.viewControllers containsObject:information]) return;
        Capture(nav.topViewController,@"02-information");
        UITableViewController *root=(id)nav.topViewController;report[@"informationCategoryCount"]=@([root.tableView numberOfRowsInSection:0]);
        Row(nav,2);Later(.6,^{Row(nav,0);});
    });
    Later(8,^{if(![nav.viewControllers containsObject:information]) return;Capture(nav.topViewController,@"03-trips");UITableViewController *vc=(id)nav.topViewController;report[@"tripRows"]=@([vc.tableView numberOfRowsInSection:0]);[nav popToViewController:information animated:NO];Row(nav,3);Later(.5,^{Row(nav,0);});});
    Later(15,^{if(![nav.viewControllers containsObject:information]) return;Capture(nav.topViewController,@"04-maintenance-groups");Row(nav,0);});
    Later(17,^{if(![nav.viewControllers containsObject:information]) return;Capture(nav.topViewController,@"05-maintenance");[nav popToViewController:information animated:NO];Row(nav,6);Later(.5,^{Row(nav,1);});});
    Later(25,^{if(![nav.viewControllers containsObject:information]) return;Capture(nav.topViewController,@"06-profile");[nav popToViewController:information animated:NO];Row(nav,0);Later(.5,^{Row(nav,0);});});
    Later(32,^{
        if(![nav.viewControllers containsObject:information]) return;
        Capture(nav.topViewController,@"07-status");
        NSData *d=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil];[d writeToFile:[ReviewDirectory() stringByAppendingPathComponent:@"report.json"] options:NSDataWritingAtomic|NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:nil];
        [nav popToRootViewControllerAnimated:NO];
    });
}
__attribute__((constructor)) static void StartReview(void) {
    if(![NSProcessInfo.processInfo.environment[@"MC_UI_REVIEW"] isEqual:@"1"]) return;
    Later(2,^{
        for(UIWindowScene *scene in UIApplication.sharedApplication.connectedScenes) if([scene isKindOfClass:UIWindowScene.class]) for(UIWindow *window in scene.windows) if([window.rootViewController isKindOfClass:UINavigationController.class]) {Review((id)window.rootViewController,0);return;}
    });
}
