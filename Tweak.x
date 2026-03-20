#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>
#import <objc/runtime.h>

// ========== НАСТРОЙКИ ==========
static NSMutableString *logText = nil;
static UIWindow *logWindow = nil;
static UIButton *floatingButton = nil;
static NSMutableArray *addresses = nil;
static NSMutableArray *values = nil;

// ========== ОБЪЯВЛЕНИЕ ==========
@interface ButtonHandler : NSObject
+ (void)showMenu;
+ (void)closeMenu;
+ (void)copyLog;
+ (void)showLog;
+ (void)addLog:(NSString*)text;
+ (UIWindow*)mainWindow;
@end

@interface FloatingButton : UIButton @end

@implementation FloatingButton
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    self.backgroundColor = [UIColor systemBlueColor];
    self.layer.cornerRadius = frame.size.width/2;
    [self setTitle:@"⚡" forState:UIControlStateNormal];
    [self addTarget:[ButtonHandler class] action:@selector(showMenu) forControlEvents:UIControlEventTouchUpInside];
    return self;
}
@end

@implementation ButtonHandler

+ (UIWindow*)mainWindow {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class]) {
            for (UIWindow *w in ((UIWindowScene*)scene).windows)
                if (w.isKeyWindow) return w;
        }
    }
    return nil;
}

+ (void)showMenu {
    CGFloat w = 250, h = 200;
    UIWindow *menu = [[UIWindow alloc] initWithFrame:CGRectMake((UIScreen.mainScreen.bounds.size.width-w)/2, (UIScreen.mainScreen.bounds.size.height-h)/2, w, h)];
    menu.windowLevel = UIWindowLevelAlert + 3;
    menu.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.95];
    menu.layer.cornerRadius = 10;
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, w, 30)];
    title.text = @"⚡ ТЕСТ";
    title.textColor = UIColor.whiteColor;
    title.textAlignment = NSTextAlignmentCenter;
    [menu addSubview:title];
    
    UIButton *testBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    testBtn.frame = CGRectMake(20, 50, w-40, 40);
    testBtn.backgroundColor = UIColor.systemBlueColor;
    testBtn.layer.cornerRadius = 8;
    [testBtn setTitle:@"ТЕСТ" forState:UIControlStateNormal];
    [testBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [testBtn addTarget:self action:@selector(testFunc) forControlEvents:UIControlEventTouchUpInside];
    [menu addSubview:testBtn];
    
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(20, 100, w-40, 40);
    closeBtn.backgroundColor = UIColor.systemRedColor;
    closeBtn.layer.cornerRadius = 8;
    [closeBtn setTitle:@"ЗАКРЫТЬ" forState:UIControlStateNormal];
    [closeBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [closeBtn addTarget:self action:@selector(closeMenu) forControlEvents:UIControlEventTouchUpInside];
    [menu addSubview:closeBtn];
    
    [menu makeKeyAndVisible];
    objc_setAssociatedObject(self, @selector(closeMenu), menu, OBJC_ASSOCIATION_RETAIN);
}

+ (void)closeMenu {
    UIWindow *menu = objc_getAssociatedObject(self, @selector(closeMenu));
    menu.hidden = YES;
}

+ (void)testFunc {
    [self addLog:@"✅ ТЕСТ РАБОТАЕТ"];
    [self showLog];
}

+ (void)addLog:(NSString*)t {
    if (!logText) logText = [NSMutableString new];
    [logText appendFormat:@"%@\n", t];
}

+ (void)showLog {
    if (!logWindow) {
        logWindow = [[UIWindow alloc] initWithFrame:CGRectMake(20, 70, UIScreen.mainScreen.bounds.size.width-40, 300)];
        logWindow.windowLevel = UIWindowLevelAlert + 2;
        logWindow.backgroundColor = [UIColor colorWithWhite:0 alpha:0.95];
        
        UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(5, 5, logWindow.bounds.size.width-10, 240)];
        tv.backgroundColor = UIColor.blackColor;
        tv.textColor = UIColor.greenColor;
        tv.font = [UIFont fontWithName:@"Courier" size:12];
        tv.editable = NO;
        [logWindow addSubview:tv];
        
        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        closeBtn.frame = CGRectMake(logWindow.bounds.size.width-60, 250, 50, 30);
        [closeBtn setTitle:@"X" forState:UIControlStateNormal];
        [closeBtn addTarget:self action:@selector(hideLog) forControlEvents:UIControlEventTouchUpInside];
        [logWindow addSubview:closeBtn];
        
        UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        copyBtn.frame = CGRectMake(20, 250, 80, 30);
        [copyBtn setTitle:@"Копировать" forState:UIControlStateNormal];
        [copyBtn addTarget:self action:@selector(copyLog) forControlEvents:UIControlEventTouchUpInside];
        [logWindow addSubview:copyBtn];
    }
    
    UITextView *tv = logWindow.subviews.firstObject;
    tv.text = logText;
    [logWindow makeKeyAndVisible];
}

+ (void)hideLog { logWindow.hidden = YES; }
+ (void)copyLog { UIPasteboard.generalPasteboard.string = logText; }

@end

__attribute__((constructor)) static void init() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        UIWindow *w = [ButtonHandler mainWindow];
        if (w) {
            floatingButton = [[FloatingButton alloc] initWithFrame:CGRectMake(20, 150, 50, 50)];
            [w addSubview:floatingButton];
        }
    });
}
