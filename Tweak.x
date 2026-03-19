// Tweak.x

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <Foundation/Foundation.h>

#define LOG_PATH @"/var/mobile/Documents/modernstrike/aimbot.log"

#define LOG(fmt, ...) do { \
    NSString *msg = [NSString stringWithFormat:fmt, ##__VA_ARGS__]; \
    NSString *timestamp = [NSDate date].description; \
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", timestamp, msg]; \
    NSLog(@"[Aimbot] %@", msg); \
    [self appendLog:line]; \
} while(0)

// ────────────────────────────────────────────────
// Категория для удобной записи в файл
@interface NSString (AppendToFile)
- (void)appendToFile:(NSString *)path encoding:(NSStringEncoding)enc;
@end

@implementation NSString (AppendToFile)
- (void)appendToFile:(NSString *)path encoding:(NSStringEncoding)enc {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = [path stringByDeletingLastPathComponent];
    [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    
    NSData *data = [self dataUsingEncoding:enc];
    if (!data) return;
    
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (handle) {
        [handle seekToEndOfFile];
        [handle writeData:data];
        [handle closeFile];
    } else {
        [data writeToFile:path atomically:YES];
    }
}
@end

// ────────────────────────────────────────────────
// Обработчик всех действий
@interface AimbotHandler : NSObject
+ (instancetype)shared;
- (void)toggleMenu;
- (void)testAction;
- (void)dragButton:(UIPanGestureRecognizer *)gesture;
@end

@implementation AimbotHandler

+ (instancetype)shared {
    static AimbotHandler *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (void)toggleMenu {
    static BOOL g_menuVisible = NO;
    static UIView *g_menuView = nil;
    
    // получаем текущие глобальные (чтобы не дублировать в файле)
    extern UIButton *g_floatButton;
    extern UIView *g_menuView_local;
    
    if (!g_menuView_local) {
        UIWindow *win = [self currentKeyWindow];
        if (!win) return;
        
        g_menuView_local = [[UIView alloc] initWithFrame:CGRectMake(100, 140, 260, 240)];
        g_menuView_local.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.95];
        g_menuView_local.layer.cornerRadius = 18;
        g_menuView_local.layer.borderWidth = 1;
        g_menuView_local.layer.borderColor = [UIColor colorWithWhite:0.7 alpha:1].CGColor;
        g_menuView_local.hidden = YES;
        [win addSubview:g_menuView_local];
        
        // Заголовок
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 14, 260, 40)];
        title.text = @"Aimbot Menu";
        title.textColor = [UIColor whiteColor];
        title.font = [UIFont boldSystemFontOfSize:22];
        title.textAlignment = NSTextAlignmentCenter;
        [g_menuView_local addSubview:title];
        
        // Test
        UIButton *test = [UIButton buttonWithType:UIButtonTypeSystem];
        test.frame = CGRectMake(40, 70, 180, 50);
        [test setTitle:@"Тест классов" forState:UIControlStateNormal];
        test.backgroundColor = [UIColor systemGray5Color];
        test.layer.cornerRadius = 12;
        [test addTarget:self action:@selector(testAction) forControlEvents:UIControlEventTouchUpInside];
        [g_menuView_local addSubview:test];
        
        // Close
        UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
        close.frame = CGRectMake(40, 140, 180, 50);
        [close setTitle:@"Закрыть" forState:UIControlStateNormal];
        close.backgroundColor = [UIColor systemRedColor];
        [close setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        close.layer.cornerRadius = 12;
        [close addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
        [g_menuView_local addSubview:close];
    }
    
    g_menuVisible = !g_menuVisible;
    g_menuView_local.hidden = !g_menuVisible;
    
    LOG(@"Меню %@", g_menuVisible ? @"открыто" : @"закрыто");
}

- (void)testAction {
    LOG(@"Запущен тест поиска классов");
    
    NSArray *classes = @[
        @"GameManager",
        @"PlayerController",
        @"Weapon",
        @"Player",
        @"MatchManager",
        @"LocalPlayer",
        @"AimbotManager"   // можно добавлять свои догадки
    ];
    
    for (NSString *name in classes) {
        Class cls = objc_getClass(name.UTF8String);
        LOG(cls ? @"✅ Найден: %@" : @"❌ Не найден: %@", name);
    }
}

- (void)dragButton:(UIPanGestureRecognizer *)gesture {
    UIView *v = gesture.view;
    CGPoint trans = [gesture translationInView:v.superview];
    v.center = CGPointMake(v.center.x + trans.x, v.center.y + trans.y);
    [gesture setTranslation:CGPointZero inView:v.superview];
}

- (UIWindow *)currentKeyWindow {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive) continue;
        UIWindowScene *ws = (UIWindowScene *)scene;
        for (UIWindow *win in ws.windows) {
            if (win.isKeyWindow) return win;
        }
    }
    return UIApplication.sharedApplication.keyWindow;
}

@end

// ────────────────────────────────────────────────
// Глобальные (теперь только кнопка, остальное внутри handler)
static UIButton *g_floatButton = nil;

// ────────────────────────────────────────────────
static void createFloatingButton() {
    UIWindow *keyWindow = [AimbotHandler.shared currentKeyWindow];
    if (!keyWindow) {
        LOG(@"Не удалось найти активное окно");
        return;
    }
    
    g_floatButton = [UIButton buttonWithType:UIButtonTypeCustom];
    g_floatButton.frame = CGRectMake(30, 120, 64, 64);
    g_floatButton.backgroundColor = [UIColor systemBlueColor];
    g_floatButton.layer.cornerRadius = 32;
    g_floatButton.layer.borderWidth = 3;
    g_floatButton.layer.borderColor = [UIColor whiteColor].CGColor;
    g_floatButton.layer.shadowColor = [UIColor blackColor].CGColor;
    g_floatButton.layer.shadowOpacity = 0.4;
    g_floatButton.layer.shadowOffset = CGSizeMake(0, 2);
    g_floatButton.layer.shadowRadius = 6;
    
    [g_floatButton setTitle:@"🎯" forState:UIControlStateNormal];
    g_floatButton.titleLabel.font = [UIFont systemFontOfSize:36];
    
    AimbotHandler *h = AimbotHandler.shared;
    
    [g_floatButton addTarget:h action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:h action:@selector(dragButton:)];
    [g_floatButton addGestureRecognizer:pan];
    
    [keyWindow addSubview:g_floatButton];
    
    LOG(@"Плавающая кнопка создана в позиции (%.0f, %.0f)", g_floatButton.frame.origin.x, g_floatButton.frame.origin.y);
}

// ────────────────────────────────────────────────
__attribute__((constructor))
static void init() {
    LOG(@"Твик Aimbot загружен (версия 1.0)");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        LOG(@"Запускаем создание интерфейса...");
        createFloatingButton();
    });
}
