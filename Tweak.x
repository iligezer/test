#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>

// ========== ТВОИ RVA (ИЗ ТВОЕГО СКРИНШОТА) ==========
#define RVA_Camera_get_main         0x10871faf8
#define RVA_Camera_WorldToScreen    0x10871ed5c
#define RVA_Transform_get_position   0x108792ed0
#define RVA_Player_IsMine            0x10716cbe4
#define RVA_Player_IsDead            0x107166230
#define RVA_Player_IsAlly            0x10715fe28
#define RVA_Player_GetHealth         0x10717f44
#define RVA_Player_GetTransform      0x10716cc10

// ========== БАЗОВЫЙ АДРЕС ==========
#define BASE_ADDR 0x1042c4000

// ========== ТИПЫ ФУНКЦИЙ ==========
typedef void *(*t_get_main_camera)();
typedef void *(*t_world_to_screen)(void *camera, void *worldPos);
typedef void *(*t_get_position)(void *transform);
typedef bool (*t_is_mine)(void *player);
typedef bool (*t_is_dead)(void *player);
typedef bool (*t_is_ally)(void *player);
typedef float (*t_get_health)(void *player);
typedef void *(*t_get_transform)(void *player);

// ========== ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ ==========
static t_get_main_camera Camera_main = NULL;
static t_world_to_screen Camera_WorldToScreen = NULL;
static t_get_position Transform_get_position = NULL;
static t_is_mine Player_IsMine = NULL;
static t_is_dead Player_IsDead = NULL;
static t_is_ally Player_IsAlly = NULL;
static t_get_health Player_GetHealth = NULL;
static t_get_transform Player_GetTransform = NULL;

static BOOL espEnabled = NO;
static NSMutableString *logText = nil;
static UIWindow *overlayWindow = nil;
static UIWindow *logWindow = nil;

// ========== ПОЛУЧЕНИЕ АДРЕСОВ ==========
void* getRealPtr(uint64_t addr) {
    return (void*)addr; // Используем абсолютные адреса
}

// ========== ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ==========
UIWindow* getMainWindow() {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *windowScene = (UIWindowScene*)scene;
            for (UIWindow *window in windowScene.windows) {
                if (window.isKeyWindow) return window;
            }
        }
    }
    return nil;
}

UIViewController* getTopViewController() {
    UIWindow *window = getMainWindow();
    if (!window) return nil;
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController) {
        vc = vc.presentedViewController;
    }
    return vc;
}

// ========== ЛОГИРОВАНИЕ ==========
void addLog(NSString *text) {
    if (!logText) logText = [[NSMutableString alloc] init];
    [logText appendFormat:@"%@\n", text];
    NSLog(@"%@", text);
}

void showLogWindow() {
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
    [copyBtn addTarget:self action:@selector(copyLog) forControlEvents:UIControlEventTouchUpInside];
    [logWindow addSubview:copyBtn];
    
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(logWindow.bounds.size.width-120, logWindow.bounds.size.height-80, 100, 40);
    closeBtn.backgroundColor = [UIColor systemRedColor];
    closeBtn.layer.cornerRadius = 10;
    [closeBtn setTitle:@"❌ Закрыть" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [closeBtn addTarget:self action:@selector(closeLogWindow) forControlEvents:UIControlEventTouchUpInside];
    [logWindow addSubview:closeBtn];
    
    [logWindow makeKeyAndVisible];
}

void copyLog() {
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    pasteboard.string = logText;
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"✅"
                                                                   message:@"Скопировано"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [getTopViewController() presentViewController:alert animated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [alert dismissViewControllerAnimated:YES completion:nil];
        });
    }];
}

void closeLogWindow() {
    logWindow.hidden = YES;
}

// ========== СКАНИРОВАНИЕ ==========
void scanAndShowLog() {
    [logText setString:@""];
    
    addLog(@"=== IL2CPP SCAN ===");
    addLog([NSString stringWithFormat:@"Base: 0x%llx", BASE_ADDR]);
    addLog([NSString stringWithFormat:@"Camera.main: %p", Camera_main]);
    addLog([NSString stringWithFormat:@"WorldToScreen: %p", Camera_WorldToScreen]);
    addLog([NSString stringWithFormat:@"get_position: %p", Transform_get_position]);
    addLog([NSString stringWithFormat:@"IsMine: %p", Player_IsMine]);
    addLog([NSString stringWithFormat:@"IsDead: %p", Player_IsDead]);
    addLog([NSString stringWithFormat:@"IsAlly: %p", Player_IsAlly]);
    addLog([NSString stringWithFormat:@"GetHealth: %p", Player_GetHealth]);
    addLog([NSString stringWithFormat:@"GetTransform: %p", Player_GetTransform]);
    
    if (Camera_main) {
        void *cam = Camera_main();
        addLog([NSString stringWithFormat:@"Camera instance: %p", cam]);
    }
    
    showLogWindow();
}

// ========== ESP VIEW ==========
@interface ESPView : UIView
@end

@implementation ESPView
- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    
    if (!espEnabled) return;
    if (!Camera_main || !Camera_WorldToScreen || !Transform_get_position) return;
    
    void *cam = Camera_main();
    if (!cam) return;
    
    // Тестовая отрисовка (пока просто точка)
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
        
        Camera_main = (t_get_main_camera)getRealPtr(RVA_Camera_get_main);
        Camera_WorldToScreen = (t_world_to_screen)getRealPtr(RVA_Camera_WorldToScreen);
        Transform_get_position = (t_get_position)getRealPtr(RVA_Transform_get_position);
        Player_IsMine = (t_is_mine)getRealPtr(RVA_Player_IsMine);
        Player_IsDead = (t_is_dead)getRealPtr(RVA_Player_IsDead);
        Player_IsAlly = (t_is_ally)getRealPtr(RVA_Player_IsAlly);
        Player_GetHealth = (t_get_health)getRealPtr(RVA_Player_GetHealth);
        Player_GetTransform = (t_get_transform)getRealPtr(RVA_Player_GetTransform);
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            UIWindow *mainWindow = getMainWindow();
            if (!mainWindow) return;
            
            UIButton *menuBtn = [UIButton buttonWithType:UIButtonTypeSystem];
            menuBtn.frame = CGRectMake(20, 150, 60, 60);
            menuBtn.backgroundColor = [UIColor systemBlueColor];
            menuBtn.layer.cornerRadius = 30;
            [menuBtn setTitle:@"M" forState:UIControlStateNormal];
            [menuBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            [menuBtn addTarget:self action:@selector(showMenu) forControlEvents:UIControlEventTouchUpInside];
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

// ========== МЕНЮ ==========
void showMenu() {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Aimbot Control"
                                                                   message:@""
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"ESP %@", espEnabled ? @"✅" : @"❌"]
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *a){
        espEnabled = !espEnabled;
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"🔍 Сканировать"
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *a){
        scanAndShowLog();
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"📋 Показать лог"
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *a){
        showLogWindow();
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Отмена"
                                               style:UIAlertActionStyleCancel
                                             handler:nil]];
    
    [getTopViewController() presentViewController:alert animated:YES completion:nil];
}
