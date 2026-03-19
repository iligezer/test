#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach/mach.h>

// ============================================
// НАСТРОЙКИ
// ============================================
#define LOG_FILE_PATH @"/var/mobile/Documents/modern/aimbot_log.txt"
#define SCAN_INTERVAL 2.0 // сканировать каждые 2 секунды

// ============================================
// СТРУКТУРЫ ДАННЫХ
// ============================================
typedef struct {
    float x, y, z;
} Vector3;

typedef struct {
    float Pitch;
    float Yaw;
    float Roll;
} FRotator;

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
    
    // Список возможных классов из дампа
    NSArray *classNames = @[
        // Основные классы игры
        @"GameManager",
        @"PlayerManager",
        @"EnemyManager",
        @"PlayerController",
        @"EnemyController",
        @"AIController",
        @"WeaponController",
        @"WeaponManager",
        @"CameraController",
        @"CameraManager",
        
        // Unity специфичные
        @"UnityEngine_GameObject",
        @"UnityEngine_Transform",
        @"UnityEngine_Camera",
        @"UnityEngine_Component",
        @"UnityEngine_MonoBehaviour",
        @"UnityEngine_Object",
        
        // Дополнительные
        @"ViewController",
        @"GameViewController",
        @"SceneController",
        @"GameInstance",
        @"World",
        @"Level",
        @"Actor",
        @"Pawn",
        @"Character",
        @"PlayerCharacter",
        @"EnemyCharacter"
    ];
    
    int found = 0;
    for (NSString *name in classNames) {
        Class cls = objc_getClass([name UTF8String]);
        if (cls) {
            writeLog([NSString stringWithFormat:@"✅ %@", name]);
            found++;
            
            // Пытаемся получить методы класса
            unsigned int methodCount = 0;
            Method *methods = class_copyMethodList(cls, &methodCount);
            if (methodCount > 0) {
                writeLog([NSString stringWithFormat:@"   📌 методов: %d", methodCount]);
                // Показываем первые 5 методов
                for (int i = 0; i < methodCount && i < 5; i++) {
                    SEL selector = method_getName(methods[i]);
                    writeLog([NSString stringWithFormat:@"      - %s", sel_getName(selector)]);
                }
                free(methods);
            }
            
            // Пытаемся получить свойства
            unsigned int propCount = 0;
            objc_property_t *properties = class_copyPropertyList(cls, &propCount);
            if (propCount > 0) {
                writeLog([NSString stringWithFormat:@"   📌 свойств: %d", propCount]);
                free(properties);
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
    
    // Пробуем найти GameManager
    Class gameManagerClass = objc_getClass("GameManager");
    if (gameManagerClass) {
        writeLog(@"✅ GameManager найден");
        
        // Пробуем получить sharedInstance
        id gameManager = nil;
        SEL sharedInstanceSel = NSSelectorFromString(@"sharedInstance");
        if ([gameManagerClass respondsToSelector:sharedInstanceSel]) {
            gameManager = [gameManagerClass sharedInstance];
            writeLog(@"✅ sharedInstance доступен");
        }
        
        // Пробуем получить всех игроков
        SEL getAllPlayersSel = NSSelectorFromString(@"getAllPlayers");
        if (gameManager && [gameManager respondsToSelector:getAllPlayersSel]) {
            NSArray *players = [gameManager performSelector:getAllPlayersSel];
            writeLog([NSString stringWithFormat:@"✅ getAllPlayers вернул %lu игроков", (unsigned long)players.count]);
        }
        
        SEL getEnemiesSel = NSSelectorFromString(@"getEnemies");
        if (gameManager && [gameManager respondsToSelector:getEnemiesSel]) {
            NSArray *enemies = [gameManager performSelector:getEnemiesSel];
            writeLog([NSString stringWithFormat:@"✅ getEnemies вернул %lu врагов", (unsigned long)enemies.count]);
        }
    }
    
    // Пробуем PlayerManager
    Class playerManagerClass = objc_getClass("PlayerManager");
    if (playerManagerClass) {
        writeLog(@"✅ PlayerManager найден");
    }
    
    // Пробуем найти PlayerController и получить его координаты
    Class playerClass = objc_getClass("PlayerController");
    if (playerClass) {
        writeLog(@"✅ PlayerController найден");
        
        // Пробуем найти все экземпляры PlayerController
        // Это сложнее - нужно искать в памяти
        writeLog(@"   🔍 Поиск экземпляров в памяти...");
    }
}

// ============================================
// ПОИСК В ПАМЯТИ (ПРОСТЕЙШАЯ ВЕРСИЯ)
// ============================================
void scanMemoryForPlayers() {
    writeLog(@"\n=== ПОИСК В ПАМЯТИ ===");
    
    // Получаем информацию о памяти процесса
    kern_return_t kr;
    vm_address_t address = 0;
    vm_size_t size = 0;
    vm_region_submap_short_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_SUBMAP_SHORT_INFO_COUNT_64;
    natural_t depth = 0;
    
    while (1) {
        kr = vm_region_recurse_64(mach_task_self(), &address, &size, &depth, (vm_region_info_64_t)&info, &count);
        if (kr != KERN_SUCCESS) break;
        
        // Проверяем только читаемые регионы
        if (info.protection & VM_PROT_READ) {
            // Ищем значения, похожие на координаты (100-2000)
            for (vm_address_t addr = address; addr < address + size; addr += 4) {
                float val = 0;
                vm_size_t bytesRead = 0;
                kr = vm_read_overwrite(mach_task_self(), addr, sizeof(float), (vm_address_t)&val, &bytesRead);
                
                if (kr == KERN_SUCCESS && bytesRead == sizeof(float)) {
                    // Координаты обычно в диапазоне [-1000, 1000]
                    if (fabs(val) > 100 && fabs(val) < 2000) {
                        // Проверяем, есть ли рядом другие координаты
                        float yVal = 0, zVal = 0;
                        vm_read_overwrite(mach_task_self(), addr + 4, sizeof(float), (vm_address_t)&yVal, &bytesRead);
                        vm_read_overwrite(mach_task_self(), addr + 8, sizeof(float), (vm_address_t)&zVal, &bytesRead);
                        
                        if (fabs(yVal) > 100 && fabs(yVal) < 2000 && fabs(zVal) > 100 && fabs(zVal) < 2000) {
                            writeLog([NSString stringWithFormat:@"🔍 Потенциальная позиция игрока: 0x%llx = (%f, %f, %f)", 
                                      (unsigned long long)addr, val, yVal, zVal]);
                        }
                    }
                }
            }
        }
        
        address += size;
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
    writeLog(@"\n🔵 Кнопка нажата - запуск полного анализа");
    scanAllClasses();
    findPlayers();
    scanMemoryForPlayers();
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
// ПРОЗРАЧНОЕ ОКНО
// ============================================
@interface PassthroughWindow : UIWindow
@property (nonatomic, weak) FloatButton *floatButton;
@end

@implementation PassthroughWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    if (self.floatButton && (hitView == self.floatButton || [self.floatButton isDescendantOfView:hitView])) {
        return hitView;
    }
    return nil; // пропускаем все остальное в игру
}

@end

// ============================================
// ОСНОВНОЙ КЛАСС
// ============================================
@interface AimbotUI : NSObject
@property (nonatomic, strong) PassthroughWindow *window;
@property (nonatomic, strong) FloatButton *floatButton;
@property (nonatomic, strong) NSTimer *scanTimer;
@end

@implementation AimbotUI

- (instancetype)init {
    self = [super init];
    if (self) {
        [self setupUI];
        
        // Запускаем автоматическое сканирование по таймеру
        self.scanTimer = [NSTimer scheduledTimerWithTimeInterval:SCAN_INTERVAL 
                                                           target:self 
                                                         selector:@selector(autoScan) 
                                                         userInfo:nil 
                                                          repeats:YES];
    }
    return self;
}

- (void)setupUI {
    // Получаем активное окно игры
    UIWindow *gameWindow = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *ws = (UIWindowScene *)scene;
            for (UIWindow *w in ws.windows) {
                if (w.isKeyWindow) gameWindow = w;
            }
            if (!gameWindow && ws.windows.count) gameWindow = ws.windows[0];
            break;
        }
    }
    
    // Создаем свое прозрачное окно
    self.window = [[PassthroughWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.windowLevel = UIWindowLevelAlert + 1;
    self.window.backgroundColor = [UIColor clearColor];
    self.window.hidden = NO;
    
    // Создаем кнопку
    self.floatButton = [[FloatButton alloc] init];
    self.window.floatButton = self.floatButton;
    [self.window addSubview:self.floatButton];
    
    __weak typeof(self) weakSelf = self;
    [self.floatButton setAction:^{
        [weakSelf manualScan];
    }];
    
    writeLog(@"✅ Интерфейс создан");
}

- (void)manualScan {
    scanAllClasses();
    findPlayers();
    scanMemoryForPlayers();
}

- (void)autoScan {
    // Автоматическое сканирование (только в лог, без дублирования)
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
    writeLog(@"📱 Устройство: %@", [UIDevice currentDevice].model);
    writeLog(@"📱 iOS: %@", [UIDevice currentDevice].systemVersion);
    writeLog(@"📱 Экран: %.0fx%.0f", [UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height);
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        g_ui = [[AimbotUI alloc] init];
        writeLog(@"✅ Интерфейс загружен, ждем нажатия кнопки...");
    });
}
