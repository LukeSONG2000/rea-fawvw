#import <UIKit/UIKit.h>
UIColor *MCInk(void);
UIColor *MCPaper(void);
UIColor *MCAccent(void);
UIFont *MCFont(CGFloat size, UIFontWeight weight);
void MCHapticPress(void);
void MCHapticSelect(void);
void MCHapticResult(BOOL success);
NSString *MCVehicleName(NSString *name);
NSString *MCFriendlyName(NSString *key);
NSString *MCFriendlyValue(id value, NSString *key);
id MCInformationSnapshot(id value, NSUInteger depth);
