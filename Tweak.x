#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach/mach.h>

// ============================================
// ПРОТОТИПЫ
// ============================================
void showAlert(NSString *title, NSString *message);
void scanClasses(void);

// ============================================
// ВСПЛЫВАЮЩЕЕ ОКНО (alert)
// ============================================
void showAlert(NSString *title, NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        
        // Пытаемся найти активное окно для показа
        UIWindow *keyWindow = nil;
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *ws = (UIWindowScene *)scene;
                for (UIWindow *w in ws.windows) {
                    if (w.isKeyWindow) {
                        keyWindow = w;
                        break;
                    }
                }
            }
            if (keyWindow) break;
        }
        [keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
    });
}

// ============================================
// СКАНИРОВАНИЕ КЛАССОВ
// ============================================
void scanClasses() {
    NSLog(@"[Aimbot] Сканирование начато");
    
    NSArray *classNames = @[
        @"GameManager", @"PlayerManager", @"EnemyManager",
        @"PlayerController", @"EnemyController", @"WeaponController",
        @"CameraController", @"UnityEngine_GameObject"
    ];
    
    NSMutableString *result = [NSMutableString stringWithString:@"Результаты сканирования:\n"];
    int found = 0;
    
    for (NSString *name in classNames) {
        Class cls = objc_getClass([name UTF8String]);
        if (cls) {
            [result appendFormat:@"✅ %@\n", name];
            found++;
        } else {
            [result appendFormat:@"❌ %@\n", name];
        }
    }
    
    [result appendFormat:@"\n📊 Найдено: %d из %lu", found, (unsigned long)classNames.count];
    
    // Показываем результат на экране
    showAlert(@"Aimbot Scan", result);
}

// ============================================
// ПЛАВАЮЩАЯ КНОПКА
// ============================================
@interface FloatButton : UIImageView
@property (nonatomic, copy) void (^actionBlock)(void);
@end

@implementation FloatButton

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(20, 100, 50, 50)];
    if (self) {
        self.backgroundColor = [UIColor systemBlueColor];
        self.layer.cornerRadius = 25;
        self.userInteractionEnabled = YES;
        
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap)];
        [self addGestureRecognizer:tap];
    }
    return self;
}

- (void)handleTap {
    if (self.actionBlock) self.actionBlock();
}

- (void)setAction:(void (^)(void))block {
    self.actionBlock = block;
}

@end

// ============================================
// ПРОЗРАЧНОЕ ОКНО
// ============================================
@interface PassthroughWindow : UIWindow
@property (nonatomic, weak) FloatButton *floatButton;
@property (nonatomic, weak) UIView *menuView;
@end

@implementation PassthroughWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.floatButton && !self.floatButton.hidden) {
        CGPoint buttonPoint = [self convertPoint:point toView:self.floatButton];
        if ([self.floatButton pointInside:buttonPoint withEvent:event]) {
            return self.floatButton;
        }
    }
    if (self.menuView && !self.menuView.hidden) {
        CGPoint menuPoint = [self convertPoint:point toView:self.menuView];
        if ([self.menuView pointInside:menuPoint withEvent:event]) {
            return [self.menuView hitTest:menuPoint withEvent:event];
        }
    }
    return nil;
}

@end

// ============================================
// ОСНОВНОЙ КЛАСС
// ============================================
@interface AimbotUI : NSObject
@property (nonatomic, strong) PassthroughWindow *window;
@property (nonatomic, strong) FloatButton *floatButton;
@property (nonatomic, strong) UIView *menuView;
@property (nonatomic, assign) BOOL menuVisible;
@end

@implementation AimbotUI

- (instancetype)init {
    self = [super init];
    if (self) [self setupUI];
    return self;
}

- (void)setupUI {
    self.window = [[PassthroughWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.windowLevel = UIWindowLevelAlert + 1;
    self.window.backgroundColor = [UIColor clearColor];
    self.window.hidden = NO;
    
    self.floatButton = [[FloatButton alloc] init];
    self.window.floatButton = self.floatButton;
    [self.window addSubview:self.floatButton];
    
    __weak typeof(self) weakSelf = self;
    [self.floatButton setAction:^{
        [weakSelf toggleMenu];
    }];
    
    [self buildMenu];
}

- (void)buildMenu {
    self.menuView = [[UIView alloc] initWithFrame:CGRectMake(80, 160, 240, 200)];
    self.menuView.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.9];
    self.menuView.layer.cornerRadius = 10;
    self.menuView.layer.borderWidth = 2;
    self.menuView.layer.borderColor = [UIColor whiteColor].CGColor;
    self.menuView.hidden = YES;
    self.window.menuView = self.menuView;
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, 240, 30)];
    title.text = @"Aimbot Menu";
    title.textColor = [UIColor whiteColor];
    title.textAlignment = NSTextAlignmentCenter;
    [self.menuView addSubview:title];
    
    UIButton *scanBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    scanBtn.frame = CGRectMake(20, 50, 200, 40);
    [scanBtn setTitle:@"🔍 Scan Classes" forState:UIControlStateNormal];
    scanBtn.backgroundColor = [UIColor lightGrayColor];
    [scanBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    scanBtn.layer.cornerRadius = 5;
    [scanBtn addTarget:self action:@selector(scanAction) forControlEvents:UIControlEventTouchUpInside];
    [self.menuView addSubview:scanBtn];
    
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(20, 100, 200, 40);
    [closeBtn setTitle:@"❌ Close" forState:UIControlStateNormal];
    closeBtn.backgroundColor = [UIColor lightGrayColor];
    [closeBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    closeBtn.layer.cornerRadius = 5;
    [closeBtn addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    [self.menuView addSubview:closeBtn];
    
    [self.window addSubview:self.menuView];
}

- (void)toggleMenu {
    self.menuVisible = !self.menuVisible;
    self.menuView.hidden = !self.menuVisible;
}

- (void)scanAction {
    // Показываем уведомление о начале
    showAlert(@"Aimbot", @"Сканирование запущено...");
    
    // Запускаем сканирование с небольшой задержкой
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        scanClasses();
    });
}

@end

// ============================================
// КОНСТРУКТОР
// ============================================
static AimbotUI *g_ui = nil;

__attribute__((constructor))
static void init() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        g_ui = [[AimbotUI alloc] init];
    });
}    }
    
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:LOG_FILE_PATH];
    if (fh) {
        [fh seekToEndOfFile];
        [fh writeData:[logEntry dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    } else {
        [logEntry writeToFile:LOG_FILE_PATH atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

// ============================================
// СКАНИРОВАНИЕ КЛАССОВ (реальная логика)
// ============================================
void scanClasses() {
    writeLog(@"\n=== СКАНИРОВАНИЕ КЛАССОВ ===");
    
    NSArray *classNames = @[
        @"GameManager", @"PlayerManager", @"EnemyManager",
        @"PlayerController", @"EnemyController", @"WeaponController",
        @"CameraController", @"UnityEngine_GameObject", @"UnityEngine_Transform"
    ];
    
    int found = 0;
    for (NSString *name in classNames) {
        Class cls = objc_getClass([name UTF8String]);
        if (cls) {
            writeLog([NSString stringWithFormat:@"✅ %@", name]);
            found++;
        } else {
            writeLog([NSString stringWithFormat:@"❌ %@", name]);
        }
    }
    
    writeLog([NSString stringWithFormat:@"📊 Найдено классов: %d из %lu", found, (unsigned long)classNames.count]);
}

// ============================================
// ПЛАВАЮЩАЯ КНОПКА (обрабатывает нажатия)
// ============================================
@interface FloatButton : UIImageView
@property (nonatomic, copy) void (^actionBlock)(void);
- (void)setAction:(void (^)(void))block;
@end

@implementation FloatButton

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(20, 100, 50, 50)];
    if (self) {
        self.backgroundColor = [UIColor systemBlueColor];
        self.layer.cornerRadius = 25;
        self.layer.borderWidth = 2;
        self.layer.borderColor = [UIColor whiteColor].CGColor;
        self.userInteractionEnabled = YES;
        
        // Только тап (без перетаскивания для надёжности)
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap)];
        [self addGestureRecognizer:tap];
    }
    return self;
}

- (void)handleTap {
    writeLog(@"🔵 Кнопка нажата (жест)");
    if (self.actionBlock) {
        self.actionBlock();
    }
}

- (void)setAction:(void (^)(void))block {
    self.actionBlock = block;
}

@end

// ============================================
// ПРОЗРАЧНОЕ ОКНО (пропускает касания в игру, кроме кнопки и меню)
// ============================================
@interface PassthroughWindow : UIWindow
@property (nonatomic, weak) FloatButton *floatButton;
@property (nonatomic, weak) UIView *menuView;
@end

@implementation PassthroughWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    // 1. Проверяем кнопку
    if (self.floatButton && !self.floatButton.hidden && self.floatButton.alpha > 0) {
        CGPoint buttonPoint = [self convertPoint:point toView:self.floatButton];
        if ([self.floatButton pointInside:buttonPoint withEvent:event]) {
            return self.floatButton;
        }
    }
    // 2. Проверяем меню (если видимо)
    if (self.menuView && !self.menuView.hidden && self.menuView.alpha > 0) {
        CGPoint menuPoint = [self convertPoint:point toView:self.menuView];
        if ([self.menuView pointInside:menuPoint withEvent:event]) {
            // Отдаём тому элементу в меню, который реально получил касание
            return [self.menuView hitTest:menuPoint withEvent:event];
        }
    }
    // 3. Всё остальное – в игру (возвращаем nil)
    return nil;
}

@end

// ============================================
// ОСНОВНОЙ КЛАСС УПРАВЛЕНИЯ
// ============================================
@interface AimbotUI : NSObject
@property (nonatomic, strong) PassthroughWindow *window;
@property (nonatomic, strong) FloatButton *floatButton;
@property (nonatomic, strong) UIView *menuView;
@property (nonatomic, assign) BOOL menuVisible;
@end

@implementation AimbotUI

- (instancetype)init {
    self = [super init];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    writeLog(@"Создание интерфейса...");
    
    // Создаём прозрачное окно
    self.window = [[PassthroughWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.windowLevel = UIWindowLevelAlert + 1; // выше игры, но ниже алертов
    self.window.backgroundColor = [UIColor clearColor];
    self.window.hidden = NO;
    
    // Кнопка
    self.floatButton = [[FloatButton alloc] init];
    self.window.floatButton = self.floatButton;
    [self.window addSubview:self.floatButton];
    
    __weak typeof(self) weakSelf = self;
    [self.floatButton setAction:^{
        [weakSelf toggleMenu];
    }];
    
    // Создаём меню (изначально скрыто)
    [self buildMenu];
    
    writeLog(@"✅ Интерфейс создан");
}

- (void)buildMenu {
    // Меню – серая полупрозрачная панель
    self.menuView = [[UIView alloc] initWithFrame:CGRectMake(80, 160, 240, 200)];
    self.menuView.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.9];
    self.menuView.layer.cornerRadius = 10;
    self.menuView.layer.borderWidth = 2;
    self.menuView.layer.borderColor = [UIColor whiteColor].CGColor;
    self.menuView.hidden = YES;
    self.window.menuView = self.menuView;
    
    // Заголовок
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, 240, 30)];
    title.text = @"Aimbot Menu";
    title.textColor = [UIColor whiteColor];
    title.textAlignment = NSTextAlignmentCenter;
    [self.menuView addSubview:title];
    
    // Кнопка сканирования
    UIButton *scanBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    scanBtn.frame = CGRectMake(20, 50, 200, 40);
    [scanBtn setTitle:@"🔍 Scan Classes" forState:UIControlStateNormal];
    scanBtn.backgroundColor = [UIColor lightGrayColor];
    [scanBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    scanBtn.layer.cornerRadius = 5;
    [scanBtn addTarget:self action:@selector(scanAction) forControlEvents:UIControlEventTouchUpInside];
    [self.menuView addSubview:scanBtn];
    
    // Кнопка закрытия
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(20, 100, 200, 40);
    [closeBtn setTitle:@"❌ Close" forState:UIControlStateNormal];
    closeBtn.backgroundColor = [UIColor lightGrayColor];
    [closeBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    closeBtn.layer.cornerRadius = 5;
    [closeBtn addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    [self.menuView addSubview:closeBtn];
    
    [self.window addSubview:self.menuView];
}

- (void)toggleMenu {
    self.menuVisible = !self.menuVisible;
    self.menuView.hidden = !self.menuVisible;
    writeLog(self.menuVisible ? @"Меню открыто" : @"Меню закрыто");
}

- (void)scanAction {
    writeLog(@"\n🔍 Нажата кнопка сканирования");
    scanClasses();  // ← теперь компилятор знает про эту функцию
    writeLog(@"✅ Сканирование завершено");
}

@end

// ============================================
// КОНСТРУКТОР (запускается при загрузке твика)
// ============================================
static AimbotUI *g_ui = nil;

__attribute__((constructor))
static void init() {
    writeLog(@"\n=== AIMBOT TWEAK ЗАГРУЖЕН ===");
    writeLog(@"📱 iOS: %@", [UIDevice currentDevice].systemVersion);
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        g_ui = [[AimbotUI alloc] init];
    });
}
