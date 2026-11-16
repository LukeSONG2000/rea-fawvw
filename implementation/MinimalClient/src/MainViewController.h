// MainViewController.h
#import <UIKit/UIKit.h>

@interface MainViewController : UIViewController
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, strong) UITextField *userField, *passField;
@property (nonatomic, strong) UILabel *vehicleLabel;
@property (nonatomic, copy) NSArray<NSString *> *vins;
@end
