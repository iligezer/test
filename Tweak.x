#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>
#import <objc/runtime.h>

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
static NSMutableArray *foundPlayers = nil; // Для хранения найденных игроков

// ========== ОБЪЯВЛЕНИЕ КЛАССА ==========
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
+ (void)toggleESP;
+ (void)closeMenu:(UIButton*)sender;
@end

// ========== СТРУКТУРА ИГРОКА ==========
@interface PlayerData : NSObject
@property (assign) float health;
@property (assign) float x, y, z;
@property (assign) unsigned long address;
@end

@implementation PlayerData
@end

// ========== ESP VIEW ==========
@interface ESPView : UIView
@end

@implementation ESPView
- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    
    if (!espEnabled || !foundPlayers.count) return;
    if (!Camera_main || !Camera_WorldToScreen || !Transform_get_position) return;
    
    void *cam = Camera_main();
    if (!cam) return;
    
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    
    for (PlayerData *player in foundPlayers) {
        // Создаем вектор позиции (упрощенно)
        float position[3] = {player.x, player.y, player.z};
        
        // Конвертируем в экранные координаты
        void *screenPos = Camera_WorldToScreen(cam, position);
        
        if (screenPos) {
            float *screen = (float*)screenPos;
            float screenX = screen[0] * rect.size.width;
            float screenY = screen[1] * rect.size.height;
            
            // Рисуем врага
            CGContextSetFillColorWithColor(ctx, [UIColor redColor].CGColor);
            CGContextFillEllipseInRect(ctx, CGRectMake(screenX - 5, screenY - 5, 10, 10));
            
            // Рисуем здоровье
            NSString *healthText = [NSString stringWithFormat:@"%.0f", player.health];
            [healthText drawAtPoint:CGPointMake(screenX + 10, screenY - 10) withAttributes:@{
                NSFontAttributeName: [UIFont systemFontOfSize:12],
                NSForegroundColorAttributeName: [UIColor whiteColor]
            }];
        }
    }
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

// ========== РЕАЛИЗАЦИЯ ButtonHandler ==========
@implementation ButtonHandler

+ (void)showMenu {
    // Центрируем меню
    CGFloat menuWidth = 280;
    CGFloat menuHeight = 400;
    CGFloat menuX = ([UIScreen mainScreen].bounds.size.width - menuWidth) / 2;
    CGFloat menuY = ([UIScreen mainScreen].bounds.size.height - menuHeight) / 2;
    
    UIWindow *menuWindow = [[UIWindow alloc] initWithFrame:CGRectMake(menuX, menuY, menuWidth, menuHeight)];
    menuWindow.windowLevel = UIWindowLevelAlert + 3;
    menuWindow.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
    menuWindow.layer.cornerRadius = 15;
    menuWindow.layer.borderWidth = 2;
    menuWindow.layer.borderColor = [UIColor systemBlueColor].CGColor;
    
    // Заголовок
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, menuWidth, 40)];
    titleLabel.text = @"⚡ AIMBOT CONTROL";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [menuWindow addSubview:titleLabel];
    
    // Кнопка ESP
    UIButton *espBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    espBtn.frame = CGRectMake(20, 60, menuWidth-40, 45);
    espBtn.backgroundColor = espEnabled ? [UIColor systemGreenColor] : [UIColor systemGrayColor];
    espBtn.layer.cornerRadius = 10;
    [espBtn setTitle:[NSString stringWithFormat:@"🎯 ESP %@", espEnabled ? @"ON" : @"OFF"] forState:UIControlStateNormal];
    [espBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [espBtn addTarget:self action:@selector(toggleESP) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:espBtn];
    
    // Кнопка сканирования
    UIButton *scanBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    scanBtn.frame = CGRectMake(20, 115, menuWidth-40, 45);
    scanBtn.backgroundColor = [UIColor systemBlueColor];
    scanBtn.layer.cornerRadius = 10;
    [scanBtn setTitle:@"🔍 СКАНИРОВАТЬ ПАМЯТЬ" forState:UIControlStateNormal];
    [scanBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [scanBtn addTarget:self action:@selector(scanMemory) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:scanBtn];
    
    // Кнопка проверки адресов
    UIButton *checkBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    checkBtn.frame = CGRectMake(20, 170, menuWidth-40, 45);
    checkBtn.backgroundColor = [UIColor systemOrangeColor];
    checkBtn.layer.cornerRadius = 10;
    [checkBtn setTitle:@"🔎 ПРОВЕРИТЬ АДРЕСА" forState:UIControlStateNormal];
    [checkBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [checkBtn addTarget:self action:@selector(checkAddresses) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:checkBtn];
    
    // Кнопка лога
    UIButton *logBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    logBtn.frame = CGRectMake(20, 225, menuWidth-40, 45);
    logBtn.backgroundColor = [UIColor systemPurpleColor];
    logBtn.layer.cornerRadius = 10;
    [logBtn setTitle:@"📋 ПОКАЗАТЬ ЛОГ" forState:UIControlStateNormal];
    [logBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [logBtn addTarget:self action:@selector(showLogWindow) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:logBtn];
    
    // Кнопка закрыть
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(20, 280, menuWidth-40, 45);
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
    [self showMenu];
}

+ (void)closeMenu:(UIButton*)sender {
    UIWindow *menuWindow = (UIWindow*)sender.superview;
    if ([menuWindow isKindOfClass:[UIWindow class]]) {
        menuWindow.hidden = YES;
        [menuWindow resignKeyWindow];
    }
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
        [logWindow makeKeyAndVisible];
        return;
    }
    
    CGFloat logWidth = [UIScreen mainScreen].bounds.size.width - 40;
    CGFloat logHeight = [UIScreen mainScreen].bounds.size.height - 100;
    CGFloat logX = 20;
    CGFloat logY = 50;
    
    logWindow = [[UIWindow alloc] initWithFrame:CGRectMake(logX, logY, logWidth, logHeight)];
    logWindow.windowLevel = UIWindowLevelAlert + 2;
    logWindow.backgroundColor = [UIColor colorWithWhite:0 alpha:0.95];
    logWindow.layer.cornerRadius = 15;
    logWindow.layer.borderWidth = 2;
    logWindow.layer.borderColor = [UIColor greenColor].CGColor;
    
    UITextView *textView = [[UITextView alloc] initWithFrame:CGRectMake(10, 10, logWidth-20, logHeight-80)];
    textView.backgroundColor = [UIColor blackColor];
    textView.textColor = [UIColor greenColor];
    textView.font = [UIFont fontWithName:@"Courier" size:12];
    textView.text = logText;
    textView.editable = NO;
    textView.layer.cornerRadius = 10;
    [logWindow addSubview:textView];
    
    UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    copyBtn.frame = CGRectMake(20, logHeight-60, 100, 40);
    copyBtn.backgroundColor = [UIColor systemBlueColor];
    copyBtn.layer.cornerRadius = 10;
    [copyBtn setTitle:@"📋 Копировать" forState:UIControlStateNormal];
    [copyBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [copyBtn addTarget:self action:@selector(copyLog) forControlEvents:UIControlEventTouchUpInside];
    [logWindow addSubview:copyBtn];
    
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(logWidth-120, logHeight-60, 100, 40);
    closeBtn.backgroundColor = [UIColor systemRedColor];
    closeBtn.layer.cornerRadius = 10;
    [closeBtn setTitle:@"❌ Закрыть" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [closeBtn addTarget:self action:@selector(closeLogWindow) forControlEvents:UIControlEventTouchUpInside];
    [logWindow addSubview:closeBtn];
    
    [logWindow makeKeyAndVisible];
}

+ (void)checkAddresses {
    [logText setString:@""];
    [self addLog:@"🔍 ПРОВЕРКА АДРЕСОВ"];
    [self addLog:@"==================="];
    [self addLog:[NSString stringWithFormat:@"Camera.main: %p", Camera_main]];
    [self addLog:[NSString stringWithFormat:@"WorldToScreen: %p", Camera_WorldToScreen]];
    [self addLog:[NSString stringWithFormat:@"get_position: %p", Transform_get_position]];
    [self addLog:[NSString stringWithFormat:@"IsMine: %p", Player_IsMine]];
    [self addLog:[NSString stringWithFormat:@"IsDead: %p", Player_IsDead]];
    [self addLog:[NSString stringWithFormat:@"IsAlly: %p", Player_IsAlly]];
    [self addLog:[NSString stringWithFormat:@"GetHealth: %p", Player_GetHealth]];
    [self addLog:@"✅ Все адреса загружены"];
    [self showLogWindow];
}

+ (void)scanMemory {
    [logText setString:@""];
    [self addLog:@"🔍 СКАНИРОВАНИЕ ПАМЯТИ..."];
    [self addLog:@"⚠️ Поиск структур игроков..."];
    
    foundPlayers = [NSMutableArray array];
    
    uint64_t base = BASE_ADDR;
    [self addLog:[NSString stringWithFormat:@"Базовый адрес: 0x%llx", base]];
    
    task_t task = mach_task_self();
    vm_address_t address = 0;
    vm_size_t size = 0;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object_name;
    int regionCount = 0;
    
    while (vm_region_64(task, &address, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &count, &object_name) == KERN_SUCCESS) {
        regionCount++;
        
        if (size > 1000 && size < 1024*1024) {
            uint8_t *buffer = malloc(size);
            vm_size_t data_read;
            
            if (vm_read_overwrite(task, address, size, (vm_address_t)buffer, &data_read) == KERN_SUCCESS) {
                
                for (int i = 0; i < data_read - 32; i += 4) {
                    float *health = (float*)(buffer + i);
                    if (*health > 99.0f && *health < 101.0f) {
                        
                        float *x = (float*)(buffer + i + 0x10);
                        float *y = (float*)(buffer + i + 0x14);
                        float *z = (float*)(buffer + i + 0x18);
                        
                        if (*x > -10000 && *x < 10000 && *y > -10000 && *y < 10000 && *z > -10000 && *z < 10000) {
                            
                            PlayerData *player = [[PlayerData alloc] init];
                            player.health = *health;
                            player.x = *x;
                            player.y = *y;
                            player.z = *z;
                            player.address = (unsigned long)(address + i);
                            [foundPlayers addObject:player];
                            
                            [self addLog:[NSString stringWithFormat:@"\n🎯 ИГРОК #%lu:", (unsigned long)foundPlayers.count]];
                            [self addLog:[NSString stringWithFormat:@"   Адрес: 0x%lx", player.address]];
                            [self addLog:[NSString stringWithFormat:@"   Здоровье: %.1f", player.health]];
                            [self addLog:[NSString stringWithFormat:@"   Позиция: (%.1f, %.1f, %.1f)", player.x, player.y, player.z]];
                            
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
    
    [self addLog:[NSString stringWithFormat:@"\n📊 Просканировано регионов: %d", regionCount]];
    [self addLog:[NSString stringWithFormat:@"📊 Найдено игроков: %lu", (unsigned long)foundPlayers.count]];
    
    if (foundPlayers.count == 0) {
        [self addLog:@"❌ Игроки не найдены. Возможно неверный паттерн поиска."];
    }
    
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
