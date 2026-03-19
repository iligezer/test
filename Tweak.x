#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>

// ========== ТВОИ АДРЕСА ==========
#define RVA_Camera_get_main         0x10871faf8
#define RVA_Camera_WorldToScreen    0x10871ed5c
#define RVA_Transform_get_position   0x108792ed0
#define RVA_Player_IsMine            0x10716cbe4
#define RVA_Player_IsDead            0x107166230
#define RVA_Player_IsAlly            0x10715fe28
#define RVA_Player_GetHealth         0x10717f44
#define RVA_Player_GetTransform      0x10716cc10
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
static UIButton *floatingButton = nil;

// ========== СКАНИРОВАНИЕ ПАМЯТИ ==========
+ (void)scanMemory {
    [self addLog:@"🔍 СКАНИРОВАНИЕ ПАМЯТИ..."];
    
    // Получаем базовый адрес игры
    uint64_t base = BASE_ADDR;
    [self addLog:[NSString stringWithFormat:@"Базовый адрес: 0x%llx", base]];
    
    // Получаем размер памяти
    task_t task = mach_task_self();
    vm_address_t address = 0;
    vm_size_t size = 0;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object_name;
    
    int playerCount = 0;
    
    // Сканируем все регионы памяти
    while (vm_region_64(task, &address, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &count, &object_name) == KERN_SUCCESS) {
        
        // Ищем регионы с данными
        if (size > 1000) { // Не сканируем слишком маленькие регионы
            // Читаем память
            uint8_t *buffer = malloc(size);
            vm_size_t data_read;
            
            if (vm_read_overwrite(task, address, size, (vm_address_t)buffer, &data_read) == KERN_SUCCESS) {
                
                // Ищем паттерны игроков (здоровье часто 100.0)
                float healthPattern = 100.0f;
                
                for (int i = 0; i < data_read - 8; i++) {
                    // Ищем float со значением 100.0
                    float *health = (float*)(buffer + i);
                    if (*health > 99.0f && *health < 101.0f) {
                        
                        // Проверяем, есть ли рядом координаты
                        float *x = (float*)(buffer + i + 0x10);
                        float *y = (float*)(buffer + i + 0x14);
                        float *z = (float*)(buffer + i + 0x18);
                        
                        // Координаты должны быть в разумных пределах
                        if (*x > -10000 && *x < 10000 && *y > -10000 && *y < 10000 && *z > -10000 && *z < 10000) {
                            
                            playerCount++;
                            [self addLog:[NSString stringWithFormat:@"\n🎯 ИГРОК #%d:", playerCount]];
                            [self addLog:[NSString stringWithFormat:@"   Адрес структуры: 0x%llx", address + i - 0x10]];
                            [self addLog:[NSString stringWithFormat:@"   Здоровье: %.1f", *health]];
                            [self addLog:[NSString stringWithFormat:@"   Позиция: (%.1f, %.1f, %.1f)", *x, *y, *z]];
                            
                            // Пропускаем остаток этой структуры
                            i += 0x80;
                        }
                    }
                }
            }
            free(buffer);
        }
        
        address += size;
        address = (address + PAGE_SIZE - 1) & ~(PAGE_SIZE - 1);
    }
    
    [self addLog:[NSString stringWithFormat:@"\n📊 Найдено игроков: %d", playerCount]];
    [self addLog:@"✅ Сканирование завершено"];
}

// ========== КЛАСС-ОБРАБОТЧИК (ПОЛНАЯ ВЕРСИЯ) ==========
@interface ButtonHandler : NSObject
+ (void)showMenu;
+ (void)copyLog;
+ (void)closeLogWindow;
+ (void)checkAddresses;
+ (void)scanMemory;
+ (void)showLogWindow;
+ (UIViewController*)topViewController;
+ (UIWindow*)mainWindow;
+ (void)handlePan:(UIPanGestureRecognizer*)gesture;
+ (void)addLog:(NSString*)text;
@end

@implementation ButtonHandler

+ (void)showMenu {
    // Создаем кастомное меню (не стандартный алерт)
    UIWindow *menuWindow = [[UIWindow alloc] initWithFrame:CGRectMake(50, 100, 280, 400)];
    menuWindow.windowLevel = UIWindowLevelAlert + 3;
    menuWindow.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
    menuWindow.layer.cornerRadius = 15;
    menuWindow.layer.borderWidth = 2;
    menuWindow.layer.borderColor = [UIColor systemBlueColor].CGColor;
    
    // Заголовок
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, 280, 40)];
    titleLabel.text = @"⚡ AIMBOT CONTROL";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [menuWindow addSubview:titleLabel];
    
    // Кнопка ESP
    UIButton *espBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    espBtn.frame = CGRectMake(20, 60, 240, 45);
    espBtn.backgroundColor = espEnabled ? [UIColor systemGreenColor] : [UIColor systemGrayColor];
    espBtn.layer.cornerRadius = 10;
    [espBtn setTitle:[NSString stringWithFormat:@"🎯 ESP %@", espEnabled ? @"ON" : @"OFF"] forState:UIControlStateNormal];
    [espBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [espBtn addTarget:self action:@selector(toggleESP) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:espBtn];
    
    // Кнопка сканирования
    UIButton *scanBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    scanBtn.frame = CGRectMake(20, 115, 240, 45);
    scanBtn.backgroundColor = [UIColor systemBlueColor];
    scanBtn.layer.cornerRadius = 10;
    [scanBtn setTitle:@"🔍 СКАНИРОВАТЬ ПАМЯТЬ" forState:UIControlStateNormal];
    [scanBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [scanBtn addTarget:self action:@selector(scanMemory) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:scanBtn];
    
    // Кнопка проверки адресов
    UIButton *checkBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    checkBtn.frame = CGRectMake(20, 170, 240, 45);
    checkBtn.backgroundColor = [UIColor systemOrangeColor];
    checkBtn.layer.cornerRadius = 10;
    [checkBtn setTitle:@"🔎 ПРОВЕРИТЬ АДРЕСА" forState:UIControlStateNormal];
    [checkBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [checkBtn addTarget:self action:@selector(checkAddresses) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:checkBtn];
    
    // Кнопка лога
    UIButton *logBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    logBtn.frame = CGRectMake(20, 225, 240, 45);
    logBtn.backgroundColor = [UIColor systemPurpleColor];
    logBtn.layer.cornerRadius = 10;
    [logBtn setTitle:@"📋 ПОКАЗАТЬ ЛОГ" forState:UIControlStateNormal];
    [logBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [logBtn addTarget:self action:@selector(showLogWindow) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:logBtn];
    
    // Кнопка закрыть
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(20, 280, 240, 45);
    closeBtn.backgroundColor = [UIColor systemRedColor];
    closeBtn.layer.cornerRadius = 10;
    [closeBtn setTitle:@"✖️ ЗАКРЫТЬ" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [closeBtn addTarget:self action:@selector(closeMenu:) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:closeBtn];
    
    [menuWindow makeKeyAndVisible];
    objc_setAssociatedObject(self, @selector(closeMenu:), menuWindow, OBJC_ASSOCIATION_RETAIN);
}

+ (void)toggleESP {
    espEnabled = !espEnabled;
    [self showMenu]; // Обновляем меню
}

+ (void)closeMenu:(UIButton*)sender {
    [sender.window resignKeyWindow];
    sender.window.hidden = YES;
}

+ (void)handlePan:(UIPanGestureRecognizer*)gesture {
    if (!floatingButton) return;
    CGPoint translation = [gesture translationInView:floatingButton.superview];
    CGPoint center = floatingButton.center;
    center.x += translation.x;
    center.y += translation.y;
    floatingButton.center = center;
    [gesture setTranslation:CGPointZero inView:floatingButton.superview];
}

+ (void)copyLog {
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    pasteboard.string = logText;
    
    // Показываем уведомление
    UILabel *toast = [[UILabel alloc] initWithFrame:CGRectMake(100, 300, 120, 40)];
    toast.backgroundColor = [UIColor blackColor];
    toast.textColor = [UIColor whiteColor];
    toast.textAlignment = NSTextAlignmentCenter;
    toast.text = @"✅ Скопировано";
    toast.layer.cornerRadius = 10;
    toast.layer.masksToBounds = YES;
    [[self mainWindow] addSubview:toast];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [toast removeFromSuperview];
    });
}

+ (void)closeLogWindow {
    logWindow.hidden = YES;
}

+ (void)showLogWindow {
    if (logWindow) {
        logWindow.hidden = NO;
        return;
    }
    
    logWindow = [[UIWindow alloc] initWithFrame:CGRectMake(20, 50, [UIScreen mainScreen].bounds.size.width - 40, [UIScreen mainScreen].bounds.size.height - 100)];
    logWindow.windowLevel = UIWindowLevelAlert + 2;
    logWindow.backgroundColor = [UIColor colorWithWhite:0 alpha:0.95];
    logWindow.layer.cornerRadius = 15;
    logWindow.layer.borderWidth = 2;
    logWindow.layer.borderColor = [UIColor greenColor].CGColor;
    
    UITextView *textView = [[UITextView alloc] initWithFrame:CGRectMake(10, 50, logWindow.bounds.size.width-20, logWindow.bounds.size.height-120)];
    textView.backgroundColor = [UIColor blackColor];
    textView.textColor = [UIColor greenColor];
    textView.font = [UIFont fontWithName:@"Courier" size:12];
    textView.text = logText;
    textView.editable = NO;
    textView.layer.cornerRadius = 10;
    [logWindow addSubview:textView];
    
    UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    copyBtn.frame = CGRectMake(20, logWindow.bounds.size.height-60, 100, 40);
    copyBtn.backgroundColor = [UIColor systemBlueColor];
    copyBtn.layer.cornerRadius = 10;
    [copyBtn setTitle:@"📋 Копировать" forState:UIControlStateNormal];
    [copyBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [copyBtn addTarget:self action:@selector(copyLog) forControlEvents:UIControlEventTouchUpInside];
    [logWindow addSubview:copyBtn];
    
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(logWindow.bounds.size.width-120, logWindow.bounds.size.height-60, 100, 40);
    closeBtn.backgroundColor = [UIColor systemRedColor];
    closeBtn.layer.cornerRadius = 10;
    [closeBtn setTitle:@"❌ Закрыть" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [closeBtn addTarget:self action:@selector(closeLogWindow) forControlEvents:UIControlEventTouchUpInside];
    [logWindow addSubview:closeBtn];
    
    [logWindow makeKeyAndVisible];
}

+ (void)checkAddresses {
    [self addLog:@"🔍 ПРОВЕРКА АДРЕСОВ"];
    [self addLog:@"==================="];
    [self addLog:[NSString stringWithFormat:@"Camera.main: %p", Camera_main]];
    [self addLog:[NSString stringWithFormat:@"WorldToScreen: %p", Camera_WorldToScreen]];
    [self addLog:[NSString stringWithFormat:@"get_position: %p", Transform_get_position]];
    [self addLog:@"✅ Все адреса загружены"];
    [self showLogWindow];
}

+ (void)scanMemory {
    [logText setString:@""];
    [self addLog:@"🔍 СКАНИРОВАНИЕ ПАМЯТИ..."];
    
    uint64_t base = BASE_ADDR;
    [self addLog:[NSString stringWithFormat:@"Базовый адрес: 0x%llx", base]];
    
    task_t task = mach_task_self();
    vm_address_t address = 0;
    vm_size_t size = 0;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object_name;
    
    int playerCount = 0;
    
    while (vm_region_64(task, &address, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &count, &object_name) == KERN_SUCCESS) {
        
        if (size > 1000 && size < 1024*1024) { // Регионы от 1KB до 1MB
            uint8_t *buffer = malloc(size);
            vm_size_t data_read;
            
            if (vm_read_overwrite(task, address, size, (vm_address_t)buffer, &data_read) == KERN_SUCCESS) {
                
                float healthPattern = 100.0f;
                
                for (int i = 0; i < data_read - 32; i += 4) {
                    float *health = (float*)(buffer + i);
                    if (*health > 99.0f && *health < 101.0f) {
                        
                        float *x = (float*)(buffer + i + 0x10);
                        float *y = (float*)(buffer + i + 0x14);
                        float *z = (float*)(buffer + i + 0x18);
                        
                        if (*x > -10000 && *x < 10000 && *y > -10000 && *y < 10000 && *z > -10000 && *z < 10000) {
                            
                            playerCount++;
                            [self addLog:[NSString stringWithFormat:@"\n🎯 ИГРОК #%d:", playerCount]];
                            [self addLog:[NSString stringWithFormat:@"   Адрес: 0x%llx", address + i]];
                            [self addLog:[NSString stringWithFormat:@"   Здоровье: %.1f", *health]];
                            [self addLog:[NSString stringWithFormat:@"   Позиция: (%.1f, %.1f, %.1f)", *x, *y, *z]];
                            
                            i += 0x80;
                        }
                    }
                }
            }
            free(buffer);
        }
        
        address += size;
        address = (address + PAGE_SIZE - 1) & ~(PAGE_SIZE - 1);
    }
    
    [self addLog:[NSString stringWithFormat:@"\n📊 Найдено игроков: %d", playerCount]];
    [self showLogWindow];
}

+ (void)addLog:(NSString *)text {
    if (!logText) logText = [[NSMutableString alloc] init];
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

// ========== ПЛАВАЮЩАЯ КНОПКА ==========
@interface FloatingButton : UIButton
@end

@implementation FloatingButton
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor systemBlueColor];
        self.layer.cornerRadius = frame.size.width / 2;
        self.layer.masksToBounds = YES;
        [self setTitle:@"⚡" forState:UIControlStateNormal];
        [self setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.titleLabel.font = [UIFont systemFontOfSize:24];
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:[ButtonHandler class] action:@selector(handlePan:)];
        [self addGestureRecognizer:pan];
        
        [self addTarget:[ButtonHandler class] action:@selector(showMenu) forControlEvents:UIControlEventTouchUpInside];
    }
    return self;
}
@end

// ========== ИНИЦИАЛИЗАЦИЯ ==========
__attribute__((constructor))
static void init() {
    @autoreleasepool {
        logText = [[NSMutableString alloc] init];
        
        uint64_t base = BASE_ADDR;
        
        Camera_main = (t_get_main_camera)(base + (RVA_Camera_get_main - 0x1042c4000));
        Camera_WorldToScreen = (t_world_to_screen)(base + (RVA_Camera_WorldToScreen - 0x1042c4000));
        Transform_get_position = (t_get_position)(base + (RVA_Transform_get_position - 0x1042c4000));
        Player_IsMine = (t_is_mine)(base + (RVA_Player_IsMine - 0x1042c4000));
        Player_IsDead = (t_is_dead)(base + (RVA_Player_IsDead - 0x1042c4000));
        Player_IsAlly = (t_is_ally)(base + (RVA_Player_IsAlly - 0x1042c4000));
        Player_GetHealth = (t_get_health)(base + (RVA_Player_GetHealth - 0x1042c4000));
        Player_GetTransform = (t_get_transform)(base + (RVA_Player_GetTransform - 0x1042c4000));
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            UIWindow *mainWindow = [ButtonHandler mainWindow];
            if (!mainWindow) return;
            
            floatingButton = [[FloatingButton alloc] initWithFrame:CGRectMake(20, 150, 60, 60)];
            [mainWindow addSubview:floatingButton];
            
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
            
            [ButtonHandler addLog:@"✅ Твик загружен"];
        });
    }
}
