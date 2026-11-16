// AppDelegate.m
#import <UIKit/UIKit.h>
#import "SceneDelegate.h"

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@end

@implementation AppDelegate

- (UISceneConfiguration *)application:(UIApplication *)application
configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession
                              options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *cfg =
        [UISceneConfiguration configurationWithName:@"Default"
                                         sessionRole:connectingSceneSession.role];
    cfg.delegateClass = [SceneDelegate class];
    return cfg;
}

@end
