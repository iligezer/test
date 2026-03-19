#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach/mach.h>

// ============================================
// НАСТРОЙКИ
// ============================================
#define LOG_FILE_PATH @"/var/mobile/Documents/modern/aimbot_log.txt"
#define SCAN_INTERVAL 2.0 // сканировать каждые 2 секунды

// ============================================
// ЛОГИРОВАНИЕ
// ============================================
void writeLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    NSLog(@"[Aimbot] %@", message);
    
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    NSString *timestamp = [formatter stringFromDate:[NSDate date]];
    NSString *logEntry = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dirPath = [LOG_FILE_PATH stringByDeletingLastPathComponent];
    if (![fm fileExistsAtPath:dirPath]) {
        [fm createDirectoryAtPath:dirPath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
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
// СКАНИРОВАНИЕ КЛАССОВ
// ============================================
void scanAllClasses() {
    writeLog(@"\n=== СКАНИРОВАНИЕ КЛАССОВ ===");
    
    NSArray *classNames = @[
        @"GameManager", @"PlayerManager", @"EnemyManager",
        @"PlayerController", @"EnemyController", @"AIController",
        @"WeaponController", @"WeaponManager", @"CameraController",
        @"UnityEngine_GameObject", @"UnityEngine_Transform",
        @"UnityEngine_Camera", @"UnityEngine_Component",
        @"ViewController", @"GameViewController"
    ];
    
    int found = 0;
    for (NSString *name in classNames) {
        Class cls = objc_getClass([name UTF8String]);
        if (cls) {
            writeLog([NSString stringWithFormat:@"✅ %@", name]);
            found++;
            
            // Получаем методы класса
            unsigned int methodCount = 0;
            Method *methods = class_copyMethodList(cls, &methodCount);
            if (methodCount > 0) {
                writeLog([NSString stringWithFormat:@"   📌 методов: %d", methodCount]);
                free(methods);
            }
        }
    }
    
    writeLog([NSString stringWithFormat:@"\n📊 Найдено классов: %d из %lu", found, (unsigned long)classNames.count]);
}

// ============================================
// ПОИСК ИГРОКОВ ЧЕРЕЗ RUNTIME
// ============================================
void findPlayers() {
    writeLog(@"\n=== ПОИСК ИГРОКОВ ===");
    
    // Пробуем GameManager
    Class gameManagerClass = objc_getClass("GameManager");
    if (gameManagerClass) {
        writeLog(@"✅ GameManager найден");
        
        // Пробуем sharedInstance
        SEL sharedSel = NSSelectorFromString(@"sharedInstance");
        if ([gameManagerClass respondsToSelector:sharedSel]) {
            id (*safe_msgSend)(id, SEL) = (void *)objc_msgSend;
            id gameManager = safe_msgSend(gameManagerClass, sharedSel);
            
            if (gameManager) {
                writeLog(@"✅ sharedInstance получен");
                
                // Пробуем getAllPlayers
                SEL getAllSel = NSSelectorFromString(@"getAllPlayers");
                if ([gameManager respondsToSelector:getAllSel]) {
                    NSArray *(*getAllMsg)(id, SEL) = (void *)objc_msgSend;
                    NSArray *players = getAllMsg(gameManager, getAllSel);
                    writeLog([NSString stringWithFormat:@"✅ getAllPlayers: %lu игроков", (unsigned long)players.count]);
                }
                
                // Пробуем getEnemies
                SEL getEnemiesSel = NSSelectorFromString(@"getEnemies");
                if ([gameManager respondsToSelector:getEnemiesSel]) {
                    NSArray *(*getEnemiesMsg)(id, SEL) = (void *)objc_msgSend;
                    NSArray *enemies = getEnemiesMsg(gameManager, getEnemiesSel);
                    writeLog([NSString stringWithFormat:@"✅ getEnemies: %lu врагов", (unsigned long)enemies.count]);
                }
            }
        }
    }
    
    // Пробуем PlayerManager
    Class playerManagerClass = objc_getClass("PlayerManager");
    if (playerManagerClass) {
        writeLog(@"✅ PlayerManager найден");
    }
    
    // Пробуем найти PlayerController
    Class playerClass = objc_getClass("PlayerController");
    if (playerClass) {
        writeLog(@"✅ PlayerController найден");
    }
}

// ============================================
// ПЛАВАЮЩАЯ КНОПКА
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
        
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap)];
        [self addGestureRecognizer:tap];
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self addGestureRecognizer:pan];
    }
    return self;
}

- (void)handleTap {
    writeLog(@"\n🔵 Кнопка нажата - запуск анализа");
    scanAllClasses();
    findPlayers();
    writeLog(@"✅ Анализ завершен");
}

- (void)handlePan:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.superview];
    self.center = CGPointMake(self.center.x + t.x, self.center.y + t.y);
    [g setTranslation:CGPointZero inView:self.superview];
}

- (void)setAction:(void (^)(void))block {
    self.actionBlock = block;
}

@end

// ============================================
// КНОПКА МЕНЮ
// ============================================
@interface MenuButton : UIButton
@end

@implementation MenuButton

- (instancetype)initWithFrame:(CGRect)frame title:(NSString *)title {
    self = [super initWithFrame:frame];
    if (self) {
        [self setTitle:title forState:UIControlStateNormal];
        [self setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
        self.backgroundColor = [UIColor lightGrayColor];
        self.layer.cornerRadius = 5;
        self.layer.borderWidth = 1;
        self.layer.borderColor = [UIColor whiteColor].CGColor;
    }
    return self;
}

@end

// ============================================
// ПРОЗРАЧНОЕ ОКНО (ПРОПУСКАЕТ НАЖАТИЯ)
// ============================================
@interface PassthroughWindow : UIWindow
@property (nonatomic, weak) FloatButton *floatButton;
@property (nonatomic, weak) UIView *menuView;
@end

@implementation PassthroughWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    
    // Если нажали на плавающую кнопку или меню - обрабатываем
    if (self.floatButton && (hitView == self.floatButton || [self.floatButton isDescendantOfView:hitView])) {
        return hitView;
    }
    if (self.menuView && (hitView == self.menuView || [self.menuView isDescendantOfView:hitView])) {
        return hitView;
    }
    
    // Иначе пропускаем в игру
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
@property (nonatomic, strong) NSTimer *scanTimer;
@end

@implementation AimbotUI

- (instancetype)init {
    self = [super init];
    if (self) {
        [self setupUI];
        
        // Запускаем автоматическое сканирование
        self.scanTimer = [NSTimer scheduledTimerWithTimeInterval:SCAN_INTERVAL 
                                                           target:self 
                                                         selector:@selector(autoScan) 
                                                         userInfo:nil 
                                                          repeats:YES];
    }
    return self;
}

- (void)setupUI {
    writeLog(@"Создание интерфейса...");
    
    // Создаем прозрачное окно
    self.window = [[PassthroughWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.windowLevel = UIWindowLevelAlert + 1;
    self.window.backgroundColor = [UIColor clearColor];
    self.window.hidden = NO;
    
    // Создаем плавающую кнопку
    self.floatButton = [[FloatButton alloc] init];
    self.window.floatButton = self.floatButton;
    [self.window addSubview:self.floatButton];
    
    // Действие для плавающей кнопки
    __weak typeof(self) weakSelf = self;
    [self.floatButton setAction:^{
        [weakSelf toggleMenu];
    }];
    
    // Создаем меню (изначально скрыто)
    self.menuView = [[UIView alloc] initWithFrame:CGRectMake(80, 160, 240, 200)];
    self.menuView.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.9];
    self.menuView.layer.cornerRadius = 10;
    self.menuView.layer.borderWidth = 2;
    self.menuView.layer.borderColor = [UIColor whiteColor].CGColor;
    self.menuView.hidden = YES;
    self.window.menuView = self.menuView;
    
    // Заголовок
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, 240, 30)];
    titleLabel.text = @"Aimbot Control";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.menuView addSubview:titleLabel];
    
    // Кнопка "Полное сканирование"
    UIButton *fullScanBtn = [MenuButton buttonWithType:UIButtonTypeSystem];
    fullScanBtn.frame = CGRectMake(20, 50, 200, 40);
    [fullScanBtn setTitle:@"🔍 Полное сканирование" forState:UIControlStateNormal];
    [fullScanBtn addTarget:self action:@selector(fullScan) forControlEvents:UIControlEventTouchUpInside];
    [self.menuView addSubview:fullScanBtn];
    
    // Кнопка "Поиск игроков"
    UIButton *findPlayersBtn = [MenuButton buttonWithType:UIButtonTypeSystem];
    findPlayersBtn.frame = CGRectMake(20, 100, 200, 40);
    [findPlayersBtn setTitle:@"👤 Поиск игроков" forState:UIControlStateNormal];
    [findPlayersBtn addTarget:self action:@selector(findPlayersAction) forControlEvents:UIControlEventTouchUpInside];
    [self.menuView addSubview:findPlayersBtn];
    
    // Кнопка "Закрыть"
    UIButton *closeBtn = [MenuButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(20, 150, 200, 40);
    [closeBtn setTitle:@"❌ Закрыть меню" forState:UIControlStateNormal];
    [closeBtn addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    [self.menuView addSubview:closeBtn];
    
    [self.window addSubview:self.menuView];
    
    writeLog(@"✅ Интерфейс создан");
}

- (void)toggleMenu {
    self.menuVisible = !self.menuVisible;
    self.menuView.hidden = !self.menuVisible;
    writeLog(self.menuVisible ? @"Меню открыто" : @"Меню закрыто");
}

- (void)fullScan {
    writeLog(@"\n🔍 ЗАПУСК ПОЛНОГО СКАНИРОВАНИЯ");
    scanAllClasses();
    findPlayers();
    writeLog(@"✅ Полное сканирование завершено");
}

- (void)findPlayersAction {
    writeLog(@"\n👤 ПОИСК ИГРОКОВ");
    findPlayers();
}

- (void)autoScan {
    // Автоматическое сканирование в фоне
    findPlayers();
}

@end

// ============================================
// КОНСТРУКТОР
// ============================================
static AimbotUI *g_ui = nil;

__attribute__((constructor))
static void init() {
    writeLog(@"\n=== AIMBOT TWEAK ЗАГРУЖЕН ===");
    writeLog(@"📱 iOS: %@", [UIDevice currentDevice].systemVersion);
    writeLog(@"📱 Экран: %.0fx%.0f", [UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height);
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        g_ui = [[AimbotUI alloc] init];
        writeLog(@"✅ Интерфейс загружен. Жми синюю кнопку для меню.");
    });
}
