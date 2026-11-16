// MCConfiguration.m
#import "MCConfiguration.h"

NSString *const MCMbbAuthServerURL   = @"https://mbboauth-1d.prd.cn.vwg-connect.cn";
NSString *const MCMbbFalServerURL    = @"https://fal-3a.prd.cn.dp.vwg-connect.cn";
NSString *const MCMbbMalServerURL    = @"https://mal-3a.prd.cn.dp.vwg-connect.cn";
NSString *const MCMbbScope           = @"openid profile mbb";

// 运行时取证前的占位值；取证后回填并改标注为 EVIDENCE-RUNTIME。
NSString *const MCMbbBrand           = @"fawvw";   // TODO-RUNTIME 0x109ee5710
NSString *const MCMbbCountry         = @"CN";      // TODO-RUNTIME 0x109ee58b0

NSString *const MCAppInfoName        = @"OneApp";        // TODO-RUNTIME 0x109ee5690
NSString *const MCAppInfoVersion     = @"444";           // TODO-RUNTIME 0x109ee56b0
NSString *const MCAppInfoId          = @"TODO-RUNTIME";  // TODO-RUNTIME 0x109ee56d0
NSString *const MCAppInfoClientName  = @"fawvw";         // TODO-RUNTIME 0x109ee56f0
NSString *const MCAppInfoClientBrand = @"fawvw";         // TODO-RUNTIME 0x109ee5710

double const MCPollJobTimeout   = 123.0;
double const MCPollRequestDelay = 2.0;

NSString *const MCHostGatewayBaseURL     = @"https://oneapp-api.faw-vw.com";
NSString *const MCHostLoginPasswordPath  = @"account/login/loginByPassword/v1";
