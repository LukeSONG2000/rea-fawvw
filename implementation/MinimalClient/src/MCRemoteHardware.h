#import <UIKit/UIKit.h>
@interface MCRemoteHousing : UIView
@end
@interface MCLCDPanel : UIView
@end
@interface MCSevenSegmentLabel : UILabel
@end
@interface MCRemoteKey : UIButton
@property(nonatomic) BOOL silver;
@property(nonatomic) BOOL showsDisclosure;
- (void)configureTitle:(NSString *)title icon:(NSString *)icon large:(BOOL)large;
@end
