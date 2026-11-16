// Configuration captured from the running original host on 2026-11-16.
// MCConfiguration.m
#import "MCConfiguration.h"

NSString *const MCMbbAuthServerURL   = @"https://mbboauth-1d.prd.cn.vwg-connect.cn";
NSString *const MCMbbFalServerURL    = @"https://msg.audi-connect.cn/fs-car";
NSString *const MCMbbMalServerURL    = @"https://mal-1a.prd.cn.vwg-connect.cn/api";
NSString *const MCMbbScope           = @"t2_fawvw:fal";

NSString *const MCMbbBrand           = @"VW";
NSString *const MCMbbCountry         = @"CN";

NSString *const MCAppInfoName        = @"BootstrapApp";
NSString *const MCAppInfoVersion     = @"1.0";
NSString *const MCAppInfoId          = @"com.tima.aftermarket";
NSString *const MCAppInfoClientName  = @"Maton";
NSString *const MCAppInfoClientBrand = @"VW";

double const MCPollJobTimeout   = 123.0;
double const MCPollRequestDelay = 2.0;



NSString *const MCHostGatewayBaseURL     = @"https://oneapp-api.faw-vw.com";
NSString *const MCHostLoginPasswordPath  = @"account/login/loginByPassword/v1";
