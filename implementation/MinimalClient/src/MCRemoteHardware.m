#import "MCRemoteHardware.h"
static void Gradient(CGContextRef ctx,NSArray<UIColor *> *colors,CGPoint start,CGPoint end) {
    NSMutableArray *cg=[NSMutableArray array];for(UIColor *c in colors) [cg addObject:(id)c.CGColor];
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();CGGradientRef gradient=CGGradientCreateWithColors(space,(__bridge CFArrayRef)cg,NULL);
    CGContextDrawLinearGradient(ctx,gradient,start,end,0);CGGradientRelease(gradient);CGColorSpaceRelease(space);
}
static UIColor *Gray(CGFloat v) {return [UIColor colorWithWhite:v alpha:1];}
static UIBezierPath *Housing(CGRect rect) {
    CGFloat x=rect.origin.x,y=rect.origin.y,w=rect.size.width,h=rect.size.height;
    UIBezierPath *p=[UIBezierPath bezierPath];[p moveToPoint:CGPointMake(x+68,y)];
    [p addLineToPoint:CGPointMake(x+w-68,y)];[p addCurveToPoint:CGPointMake(x+w,y+84) controlPoint1:CGPointMake(x+w-8,y) controlPoint2:CGPointMake(x+w,y+30)];
    [p addCurveToPoint:CGPointMake(x+w-17,y+h-86) controlPoint1:CGPointMake(x+w,y+h*.57) controlPoint2:CGPointMake(x+w-6,y+h-150)];
    [p addCurveToPoint:CGPointMake(x+w-70,y+h) controlPoint1:CGPointMake(x+w-23,y+h-27) controlPoint2:CGPointMake(x+w-35,y+h)];
    [p addLineToPoint:CGPointMake(x+70,y+h)];[p addCurveToPoint:CGPointMake(x+17,y+h-86) controlPoint1:CGPointMake(x+35,y+h) controlPoint2:CGPointMake(x+23,y+h-27)];
    [p addCurveToPoint:CGPointMake(x,y+84) controlPoint1:CGPointMake(x+6,y+h-150) controlPoint2:CGPointMake(x,y+h*.57)];
    [p addCurveToPoint:CGPointMake(x+68,y) controlPoint1:CGPointMake(x,y+30) controlPoint2:CGPointMake(x+8,y)];[p closePath];return p;
}
@implementation MCRemoteHousing
- (instancetype)init {if((self=[super init])) {self.backgroundColor=UIColor.clearColor;self.opaque=NO;self.layer.shadowColor=UIColor.blackColor.CGColor;self.layer.shadowOpacity=.30;self.layer.shadowRadius=16;self.layer.shadowOffset=CGSizeMake(0,15);}return self;}
- (void)layoutSubviews {[super layoutSubviews];self.layer.shadowPath=Housing(CGRectInset(self.bounds,2,2)).CGPath;[self setNeedsDisplay];}
- (void)drawRect:(CGRect)rect {
    CGContextRef ctx=UIGraphicsGetCurrentContext();CGRect b=CGRectInset(self.bounds,2,2);UIBezierPath *outer=Housing(b);
    CGContextSaveGState(ctx);[outer addClip];Gradient(ctx,@[Gray(.73),Gray(.24),Gray(.56),Gray(.16)],CGPointZero,CGPointMake(b.size.width,b.size.height));CGContextRestoreGState(ctx);
    [Gray(.08) setStroke];outer.lineWidth=1;[outer stroke];
    UIBezierPath *inner=Housing(CGRectInset(b,6,6));CGContextSaveGState(ctx);[inner addClip];Gradient(ctx,@[Gray(.23),Gray(.105),Gray(.16)],CGPointZero,CGPointMake(0,b.size.height));
    // 微小颗粒是本地绘制的机身材质，保持触摸区域和文字清晰。
    for(int i=0;i<1500;i++) {CGFloat x=(i*127%997)/997.0*b.size.width,y=(i*337%991)/991.0*b.size.height;[[UIColor colorWithWhite:i%2 alpha:.025] setFill];CGContextFillRect(ctx,CGRectMake(x,y,.7,.7));}
    CGContextRestoreGState(ctx);[[UIColor colorWithWhite:1 alpha:.14] setStroke];inner.lineWidth=1;[inner stroke];
    // 底部金属挂绳槽。
    CGRect slot=CGRectMake(CGRectGetMidX(b)-36,CGRectGetMaxY(b)-39,72,13);UIBezierPath *ring=[UIBezierPath bezierPathWithRoundedRect:slot cornerRadius:6.5];[Gray(.04) setFill];[ring fill];[[UIColor colorWithWhite:.55 alpha:1] setStroke];ring.lineWidth=1.5;[ring stroke];
    for(NSNumber *side in @[@0,@1]) {CGFloat x=side.boolValue?self.bounds.size.width-15:15;CGRect screw=CGRectMake(x-3,59,6,6);UIBezierPath *p=[UIBezierPath bezierPathWithOvalInRect:screw];[Gray(.45) setFill];[p fill];[Gray(.07) setStroke];p.lineWidth=1;[p stroke];CGContextMoveToPoint(ctx,x-1.7,62);CGContextAddLineToPoint(ctx,x+1.7,62);CGContextStrokePath(ctx);}
}
@end
@implementation MCLCDPanel
- (instancetype)init {if((self=[super init])) {self.backgroundColor=UIColor.clearColor;self.opaque=NO;}return self;}
- (void)drawRect:(CGRect)rect {
    CGContextRef ctx=UIGraphicsGetCurrentContext();CGRect b=self.bounds;
    UIBezierPath *bezel=[UIBezierPath bezierPathWithRoundedRect:b cornerRadius:24];CGContextSaveGState(ctx);[bezel addClip];Gradient(ctx,@[Gray(.025),Gray(.30)],CGPointZero,CGPointMake(0,b.size.height));CGContextRestoreGState(ctx);
    CGRect inner=CGRectInset(b,7,7);UIBezierPath *glass=[UIBezierPath bezierPathWithRoundedRect:inner cornerRadius:18];CGContextSaveGState(ctx);[glass addClip];
    Gradient(ctx,@[[UIColor colorWithRed:.58 green:.65 blue:.48 alpha:1],[UIColor colorWithRed:.76 green:.82 blue:.65 alpha:1],[UIColor colorWithRed:.66 green:.73 blue:.55 alpha:1]],CGPointZero,CGPointMake(0,b.size.height));
    CGContextSetStrokeColorWithColor(ctx,[UIColor colorWithWhite:.05 alpha:.035].CGColor);CGContextSetLineWidth(ctx,.35);for(CGFloat y=9;y<b.size.height;y+=2) {CGContextMoveToPoint(ctx,7,y);CGContextAddLineToPoint(ctx,b.size.width-7,y);}CGContextStrokePath(ctx);
    UIBezierPath *shine=[UIBezierPath bezierPath];[shine moveToPoint:CGPointMake(0,0)];[shine addLineToPoint:CGPointMake(b.size.width,0)];[shine addLineToPoint:CGPointMake(b.size.width,b.size.height*.17)];[shine addLineToPoint:CGPointMake(0,b.size.height*.55)];[shine closePath];[[UIColor colorWithWhite:1 alpha:.08] setFill];[shine fill];CGContextRestoreGState(ctx);
    [[UIColor colorWithWhite:0 alpha:.65] setStroke];glass.lineWidth=2;[glass stroke];
}
@end
@interface MCRemoteKey ()
@property(nonatomic,strong) CAGradientLayer *rim,*cap;
@property(nonatomic,strong) UILabel *caption,*hint;
@property(nonatomic,strong) UIImageView *glyph;
@end
@implementation MCRemoteKey
- (instancetype)initWithFrame:(CGRect)frame {if((self=[super initWithFrame:frame])) {[self prepareLayers];}return self;}
- (void)prepareLayers {
    self.rim=[CAGradientLayer layer];self.cap=[CAGradientLayer layer];self.rim.zPosition=-2;self.cap.zPosition=-1;[self.layer insertSublayer:self.rim atIndex:0];[self.layer insertSublayer:self.cap atIndex:1];
    self.layer.shadowColor=UIColor.blackColor.CGColor;self.layer.shadowRadius=4;self.layer.shadowOpacity=.9;self.layer.shadowOffset=CGSizeMake(0,5);[self updateColors];
}
- (void)configureTitle:(NSString *)title icon:(NSString *)icon large:(BOOL)large {
    self.configuration=nil;
    self.glyph=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:icon]];self.glyph.contentMode=UIViewContentModeScaleAspectFit;
    [self.glyph.heightAnchor constraintEqualToConstant:large?27:21].active=YES;
    self.caption=[UILabel new];self.caption.text=title;self.caption.font=[UIFont systemFontOfSize:large?15:13 weight:UIFontWeightSemibold];self.caption.textAlignment=NSTextAlignmentCenter;
    self.caption.adjustsFontForContentSizeCategory=YES;self.caption.numberOfLines=1;self.caption.adjustsFontSizeToFitWidth=YES;self.caption.minimumScaleFactor=.8;
    self.hint=[UILabel new];self.hint.text=@"更多 ⌄";self.hint.font=[UIFont systemFontOfSize:9 weight:UIFontWeightMedium];self.hint.textAlignment=NSTextAlignmentCenter;self.hint.hidden=YES;
    UIStackView *content=[[UIStackView alloc] initWithArrangedSubviews:@[self.glyph,self.caption,self.hint]];content.axis=UILayoutConstraintAxisVertical;content.spacing=4;content.alignment=UIStackViewAlignmentFill;content.userInteractionEnabled=NO;content.translatesAutoresizingMaskIntoConstraints=NO;content.layer.zPosition=3;[self addSubview:content];
    [NSLayoutConstraint activateConstraints:@[[content.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],[content.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:7],[content.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-7]]];
    self.accessibilityLabel=title;[self updateColors];
}
- (void)setShowsDisclosure:(BOOL)showsDisclosure {_showsDisclosure=showsDisclosure;self.hint.hidden=!showsDisclosure;}
- (void)setSilver:(BOOL)silver {_silver=silver;[self updateColors];}
- (void)updateColors {
    self.rim.colors=@[(id)Gray(.02).CGColor,(id)Gray(.33).CGColor];
    self.cap.colors=self.silver?@[(id)Gray(.94).CGColor,(id)Gray(.69).CGColor]:@[(id)Gray(.32).CGColor,(id)Gray(.14).CGColor];
    self.caption.textColor=self.silver?Gray(.12):Gray(.96);self.glyph.tintColor=self.caption.textColor;self.hint.textColor=self.silver?Gray(.3):Gray(.7);
    self.cap.borderWidth=1;self.cap.borderColor=[UIColor colorWithWhite:1 alpha:self.silver?.5:.15].CGColor;
}
- (void)layoutSubviews {
    [super layoutSubviews];if(!self.rim) [self prepareLayers];
    [CATransaction begin];[CATransaction setDisableActions:YES];self.rim.frame=self.bounds;self.rim.cornerRadius=MIN(self.bounds.size.width,self.bounds.size.height)/2;
    self.cap.frame=CGRectInset(self.bounds,3,3);self.cap.cornerRadius=MAX(0,self.rim.cornerRadius-3);self.layer.shadowPath=[UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:self.rim.cornerRadius].CGPath;[CATransaction commit];
}
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];self.cap.transform=CATransform3DMakeTranslation(0,highlighted?2:0,0);self.layer.shadowOpacity=highlighted?.3:.9;
    self.alpha=highlighted?.85:(self.enabled?1:.35);
}
@end

@implementation MCSevenSegmentLabel
- (void)drawTextInRect:(CGRect)rect {
    NSString *text=self.text?:@"—";CGFloat h=MIN(58,rect.size.height),w=h*.54,gap=h*.12,t=h*.075;
    CGFloat width=text.length*(w+gap)-gap;if(width>rect.size.width) {CGFloat scale=rect.size.width/width;h*=scale;w*=scale;gap*=scale;t*=scale;}
    CGFloat y=(rect.size.height-h)/2;
    int masks[10]={0x3f,0x06,0x5b,0x4f,0x66,0x6d,0x7d,0x07,0x7f,0x6f};
    for(NSUInteger i=0;i<text.length;i++) {
        unichar c=[text characterAtIndex:i];int mask=c>='0' && c<='9'?masks[c-'0']:0x40;CGFloat x=i*(w+gap);
        CGRect segments[]={CGRectMake(x+t,y,w-2*t,t),CGRectMake(x+w-t,y+t,t,h/2-1.5*t),CGRectMake(x+w-t,y+h/2+t/2,t,h/2-1.5*t),CGRectMake(x+t,y+h-t,w-2*t,t),CGRectMake(x,y+h/2+t/2,t,h/2-1.5*t),CGRectMake(x,y+t,t,h/2-1.5*t),CGRectMake(x+t,y+h/2-t/2,w-2*t,t)};
        for(int j=0;j<7;j++) {[(mask&(1<<j))?self.textColor:[self.textColor colorWithAlphaComponent:.055] setFill];[[UIBezierPath bezierPathWithRoundedRect:segments[j] cornerRadius:t*.28] fill];}
    }
}
@end
