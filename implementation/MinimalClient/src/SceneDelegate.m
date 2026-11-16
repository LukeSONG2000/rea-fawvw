// SceneDelegate.m — iOS 13+ scene 生命周期（修复 NoSceneLifecycleAdoption 崩溃）
#import "SceneDelegate.h"
#import "MainViewController.h"

@implementation SceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session
      options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:[UIWindowScene class]]) return;
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController =
        [[UINavigationController alloc] initWithRootViewController:[MainViewController new]];
    [self.window makeKeyAndVisible];
}

@end
