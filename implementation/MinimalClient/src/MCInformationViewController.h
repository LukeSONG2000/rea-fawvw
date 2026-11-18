#import <UIKit/UIKit.h>
#import "MCSDK.h"
@interface MCInformationViewController : UITableViewController
- (instancetype)initWithVehicle:(MCVehicleInfo *)vehicle currentVIN:(NSString *(^)(void))currentVIN;
@end
