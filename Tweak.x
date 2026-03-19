#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>

// ========== ТВОИ RVA ==========
#define RVA_Camera_get_main         0x10871faf8
#define RVA_Camera_WorldToScreen    0x10871ed5c
#define BASE_ADDR 0x1042c4000

// ========== ТИПЫ ФУНКЦИЙ ==========
typedef void *(*t_get_main_camera)();
typedef void *(*t_world_to_screen)(void *camera, void *worldPos);

// ========== ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ ==========
static t_get_main_camera Camera_main = NULL;
static t_world_to_screen Camera_WorldToScreen = NULL;
static BOOL espEnabled = NO;
static NSMutableString *logText = nil;
static UIWindow *overlayWindow = nil;
static UIWindow *logWindow = nil;

// ========== КЛАСС-ОБРАБОТЧИК ==========
@interface ButtonHandler : NSObject
+ (void)showMenu;
+ (void)copyLog;
+ (void)closeLogWindow;
+ (void)verifyAddresses;
@end

@implementation ButtonHandler
+ (void)showMenu {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Aimbot Control"
                                                                   message:@""
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"ESP %@", espEnabled ? @"✅" : @"❌"]
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *a){
        espEnabled = !espEnabled;
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"🔍 Проверить адреса"
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *a){
        [ButtonHandler verifyAddresses];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"📋 Показать лог"
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *a){
        [ButtonHandler showLogWindow];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Отмена"
                                               style:UIAlertActionStyleCancel
                                             handler:nil]];
    
    [[self topViewController] presentViewController:alert animated:YES completion:nil];
}

+ (void)copyLog {
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    pasteboard.string = logText;
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"✅"
                                                                   message:@"Скопировано"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [[self topViewController] presentViewController:alert animated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [alert dismissViewControllerAnimated:YES completion:nil];
        });
    }];
}

+ (void)closeLogWindow {
    logWindow.hidden = YES;
}

+ (void)showLogWindow {
    if (logWindow) {
        logWindow.hidden = NO;
        return;
    }
    
    logWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    logWindow.windowLevel = UIWindowLevelAlert + 2;
    logWindow.backgroundColor = [UIColor colorWithWhite:0 alpha:0.9];
    
    UITextView *textView = [[UITextView alloc] initWithFrame:CGRectMake(20, 60, logWindow.bounds.size.width-40, logWindow.bounds.size.height-150)];
    textView.backgroundColor = [UIColor blackColor];
    textView.textColor = [UIColor greenColor];
    textView.font = [UIFont fontWithName:@"Courier" size:12];
    textView.text = logText;
    textView.editable = NO;
    textView.layer.cornerRadius = 10;
    [logWindow addSubview:textView];
    
    UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    copyBtn.frame = CGRectMake(20, logWindow.bounds.size.height-80, 100, 40);
    copyBtn.backgroundColor = [UIColor systemBlueColor];
    copyBtn.layer.cornerRadius = 10;
    [copyBtn setTitle:@"📋 Копировать" forState:UIControlStateNormal];
    [copyBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [copyBtn addTarget:[ButtonHandler class] action:@selector(copyLog) forControlEvents:UIControlEventTouchUpInside];
    [logWindow addSubview:copyBtn];
    
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(logWindow.bounds.size.width-120, logWindow.bounds.size.height-80, 100, 40);
    closeBtn.backgroundColor = [UIColor systemRedColor];
    closeBtn.layer.cornerRadius = 10;
    [closeBtn setTitle:@"❌ Закрыть" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [closeBtn addTarget:[ButtonHandler class] action:@selector(closeLogWindow) forControlEvents:UIControlEventTouchUpInside];
    [logWindow addSubview:closeBtn];
    
    [logWindow makeKeyAndVisible];
}

+ (void)verifyAddresses {
    if (!logText) logText = [[NSMutableString alloc] init];
    [logText setString:@""];
    
    [self addLog:@"🔍 ПРОВЕРКА АДРЕСОВ"];
    [self addLog:@"==================="];
    
    [self addLog:[NSString stringWithFormat:@"Camera.main: %p", Camera_main]];
    
    if (Camera_main) {
        void *cam = Camera_main();
        [self addLog:[NSString stringWithFormat:@"✅ Camera.main вызвана -> результат: %p", cam]];
        
        if (cam) {
            [self addLog:@"✅ Камера существует! Адрес верный"];
        } else {
            [self addLog:@"❌ Camera.main вернула nil"];
        }
    }
    
    [self showLogWindow];
}

+ (void)addLog:(NSString *)text {
    [logText appendFormat:@"%@\n", text];
    NSLog(@"%@", text);
}

+ (UIViewController*)topViewController {
    UIWindow *window = [self mainWindow];
    if (!window) return nil;
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController) {
        vc = vc.presentedViewController;
    }
    return vc;
}

+ (UIWindow*)mainWindow {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            for (UIWindow *window in ((UIWindowScene*)scene).windows) {
                if (window.isKeyWindow) return window;
            }
        }
    }
    return nil;
}
@end

// ========== ESP VIEW ==========
@interface ESPView : UIView
@end

@implementation ESPView
- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    
    if (!espEnabled) return;
    
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(ctx, [UIColor redColor].CGColor);
    CGContextFillEllipseInRect(ctx, CGRectMake(100, 100, 10, 10));
}
@end

// ========== ИНИЦИАЛИЗАЦИЯ ==========
__attribute__((constructor))
static void init() {
    @autoreleasepool {
        logText = [[NSMutableString alloc] init];
        
        Camera_main = (t_get_main_camera)(BASE_ADDR + (RVA_Camera_get_main - 0x1042c4000));
        Camera_WorldToScreen = (t_world_to_screen)(BASE_ADDR + (RVA_Camera_WorldToScreen - 0x1042c4000));
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            UIWindow *mainWindow = [ButtonHandler mainWindow];
            if (!mainWindow) return;
            
            UIButton *menuBtn = [UIButton buttonWithType:UIButtonTypeSystem];
            menuBtn.frame = CGRectMake(20, 150, 60, 60);
            menuBtn.backgroundColor = [UIColor systemBlueColor];
            menuBtn.layer.cornerRadius = 30;
            [menuBtn setTitle:@"M" forState:UIControlStateNormal];
            [menuBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            [menuBtn addTarget:[ButtonHandler class] action:@selector(showMenu) forControlEvents:UIControlEventTouchUpInside];
            [mainWindow addSubview:menuBtn];
            
            overlayWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
            overlayWindow.windowLevel = UIWindowLevelAlert + 1;
            overlayWindow.backgroundColor = [UIColor clearColor];
            overlayWindow.userInteractionEnabled = NO;
            
            ESPView *espView = [[ESPView alloc] initWithFrame:[UIScreen mainScreen].bounds];
            espView.backgroundColor = [UIColor clearColor];
            [overlayWindow addSubview:espView];
            
            [overlayWindow makeKeyAndVisible];
            
            [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *t){
                if (espEnabled) {
                    [espView setNeedsDisplay];
                }
            }];
        });
    }
}
