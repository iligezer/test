#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>
#import <objc/runtime.h>

// ========== ТВОИ АДРЕСА ==========
#define RVA_Camera_get_main         0x10871faf8
#define RVA_Camera_WorldToScreen    0x10871ed5c
#define RVA_Transform_get_position   0x108792ed0
#define BASE_ADDR 0x1042c4000

// ========== ТИПЫ ФУНКЦИЙ ==========
typedef void *(*t_get_main_camera)();
typedef void *(*t_world_to_screen)(void *camera, void *worldPos);
typedef void *(*t_get_position)(void *transform);

// ========== ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ ==========
static t_get_main_camera Camera_main = NULL;
static t_world_to_screen Camera_WorldToScreen = NULL;
static t_get_position Transform_get_position = NULL;

static NSMutableString *logText = nil;
static UIWindow *logWindow = nil;
static UIButton *floatingButton = nil;
static NSMutableArray *foundPlayers = nil;

// ========== МОДЕЛЬ ИГРОКА ==========
@interface PlayerData : NSObject
@property (assign) float health;
@property (assign) float x, y, z;
@property (assign) unsigned long address;
@property (strong) NSString *name;
@end

@implementation PlayerData
- (NSString *)description {
    return [NSString stringWithFormat:@"HP:%.1f (%.1f,%.1f,%.1f) 0x%lx %@",
            self.health, self.x, self.y, self.z, self.address, self.name ?: @""];
}
@end

// ========== ОБЪЯВЛЕНИЕ ==========
@interface ButtonHandler : NSObject
+ (void)showMenu;
+ (void)closeMenu;
+ (void)copyLog;
+ (void)closeLogWindow;
+ (void)showLogWindow;
+ (void)addLog:(NSString*)text;
+ (void)scanByCoordinates;
+ (UIWindow*)mainWindow;
+ (void)handlePan:(UIPanGestureRecognizer*)gesture;
@end

@interface FloatingButton : UIButton
@end

// ========== ПЛАВАЮЩАЯ КНОПКА ==========
@implementation FloatingButton
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor systemBlueColor];
        self.layer.cornerRadius = frame.size.width / 2;
        [self setTitle:@"⚡" forState:UIControlStateNormal];
        [self setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:[ButtonHandler class] action:@selector(handlePan:)];
        [self addGestureRecognizer:pan];
        
        [self addTarget:[ButtonHandler class] action:@selector(showMenu) forControlEvents:UIControlEventTouchUpInside];
    }
    return self;
}
@end

// ========== РЕАЛИЗАЦИЯ ==========
@implementation ButtonHandler

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

+ (void)handlePan:(UIPanGestureRecognizer*)gesture {
    if (!floatingButton) return;
    CGPoint translation = [gesture translationInView:floatingButton.superview];
    CGPoint center = floatingButton.center;
    center.x += translation.x;
    center.y += translation.y;
    floatingButton.center = center;
    [gesture setTranslation:CGPointZero inView:floatingButton.superview];
}

+ (void)showMenu {
    CGFloat menuWidth = 260;
    CGFloat menuHeight = 250;
    CGFloat menuX = ([UIScreen mainScreen].bounds.size.width - menuWidth) / 2;
    CGFloat menuY = ([UIScreen mainScreen].bounds.size.height - menuHeight) / 2;
    
    UIWindow *menuWindow = [[UIWindow alloc] initWithFrame:CGRectMake(menuX, menuY, menuWidth, menuHeight)];
    menuWindow.windowLevel = UIWindowLevelAlert + 3;
    menuWindow.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.95];
    menuWindow.layer.cornerRadius = 10;
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, menuWidth, 30)];
    title.text = @"⚡ SCANNER";
    title.textColor = [UIColor whiteColor];
    title.textAlignment = NSTextAlignmentCenter;
    [menuWindow addSubview:title];
    
    UIButton *scanBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    scanBtn.frame = CGRectMake(20, 60, menuWidth-40, 45);
    scanBtn.backgroundColor = [UIColor systemBlueColor];
    scanBtn.layer.cornerRadius = 8;
    [scanBtn setTitle:@"🔍 СКАНИРОВАТЬ" forState:UIControlStateNormal];
    [scanBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [scanBtn addTarget:self action:@selector(scanByCoordinates) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:scanBtn];
    
    UIButton *logBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    logBtn.frame = CGRectMake(20, 120, menuWidth-40, 45);
    logBtn.backgroundColor = [UIColor systemGrayColor];
    logBtn.layer.cornerRadius = 8;
    [logBtn setTitle:@"📋 ПОКАЗАТЬ ЛОГ" forState:UIControlStateNormal];
    [logBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [logBtn addTarget:self action:@selector(showLogWindow) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:logBtn];
    
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(20, 180, menuWidth-40, 45);
    closeBtn.backgroundColor = [UIColor systemRedColor];
    closeBtn.layer.cornerRadius = 8;
    [closeBtn setTitle:@"✖️ ЗАКРЫТЬ" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [closeBtn addTarget:self action:@selector(closeMenu) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:closeBtn];
    
    [menuWindow makeKeyAndVisible];
    objc_setAssociatedObject(self, @selector(closeMenu), menuWindow, OBJC_ASSOCIATION_RETAIN);
}

+ (void)closeMenu {
    UIWindow *menuWindow = objc_getAssociatedObject(self, @selector(closeMenu));
    menuWindow.hidden = YES;
    [menuWindow resignKeyWindow];
}

// ========== ПОИСК ПО КООРДИНАТАМ ==========
+ (void)scanByCoordinates {
    [logText setString:@""];
    [self addLog:@"🔍 ПОИСК ПО КООРДИНАТАМ..."];
    
    foundPlayers = [NSMutableArray array];
    
    task_t task = mach_task_self();
    vm_address_t address = 0;
    vm_size_t size = 0;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object_name;
    
    int regionCount = 0;
    int coordFound = 0;
    
    while (vm_region_64(task, &address, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &count, &object_name) == KERN_SUCCESS) {
        
        regionCount++;
        
        // Пропускаем слишком маленькие или огромные регионы
        if (size < 4096 || size > 20 * 1024 * 1024) {
            address += size;
            continue;
        }
        
        // Читаем регион
        uint8_t *buffer = malloc(size);
        vm_size_t data_read;
        
        if (vm_read_overwrite(task, address, size, (vm_address_t)buffer, &data_read) == KERN_SUCCESS) {
            
            // Ищем координаты (три float подряд)
            for (int i = 0; i < data_read - 64; i += 4) {
                
                float *x = (float*)(buffer + i);
                float *y = (float*)(buffer + i + 4);
                float *z = (float*)(buffer + i + 8);
                
                // Проверяем, похоже ли на координаты
                if (*x > -10000 && *x < 10000 &&
                    *y > -10000 && *y < 10000 &&
                    *z > -10000 && *z < 10000) {
                    
                    coordFound++;
                    
                    // Нашли координаты - теперь ищем здоровье рядом
                    float health = 0;
                    unsigned long healthAddr = 0;
                    NSString *name = nil;
                    
                    // Ищем здоровье в пределах -0x50..+0x50
                    for (int offset = -0x50; offset < 0x50; offset += 4) {
                        float *val = (float*)(buffer + i + offset);
                        if (*val > 1 && *val < 200) {
                            health = *val;
                            healthAddr = address + i + offset;
                            break;
                        }
                    }
                    
                    // Если нашли здоровье - ищем имя
                    if (health > 0) {
                        for (int offset = -0x80; offset < 0x80; offset += 2) { // шаг 2 для UTF-16
                            uint16_t *chars = (uint16_t*)(buffer + i + offset);
                            
                            // Проверяем, похоже ли на строку (русские/английские буквы)
                            int validChars = 0;
                            for (int j = 0; j < 16; j++) {
                                if (chars[j] > 0x20 && chars[j] < 0x7F) { // английские
                                    validChars++;
                                } else if (chars[j] >= 0x0400 && chars[j] <= 0x04FF) { // русские
                                    validChars++;
                                } else {
                                    break;
                                }
                            }
                            
                            if (validChars > 2 && validChars < 20) {
                                // Конвертируем UTF-16 в NSString
                                name = [[NSString alloc] initWithCharacters:chars length:validChars];
                                break;
                            }
                        }
                        
                        // Сохраняем кандидата
                        PlayerData *p = [[PlayerData alloc] init];
                        p.health = health;
                        p.x = *x;
                        p.y = *y;
                        p.z = *z;
                        p.address = healthAddr;
                        p.name = name;
                        
                        [foundPlayers addObject:p];
                        
                        [self addLog:[NSString stringWithFormat:@"\n🎯 КАНДИДАТ #%lu:", (unsigned long)foundPlayers.count]];
                        [self addLog:[NSString stringWithFormat:@"   Координаты: (%.1f, %.1f, %.1f)", p.x, p.y, p.z]];
                        [self addLog:[NSString stringWithFormat:@"   Здоровье: %.1f по адресу 0x%lx", p.health, p.address]];
                        if (p.name) [self addLog:[NSString stringWithFormat:@"   Имя: %@", p.name]];
                        
                        // Пропускаем структуру
                        i += 0x80;
                    }
                }
            }
        }
        free(buffer);
        
        address += size;
        address = (address + PAGE_SIZE - 1) & ~(PAGE_SIZE - 1);
        
        // Даем игре подышать
        if (regionCount % 10 == 0) {
            usleep(1000); // 1ms пауза
        }
    }
    
    [self addLog:[NSString stringWithFormat:@"\n📊 Регионов: %d", regionCount]];
    [self addLog:[NSString stringWithFormat:@"📊 Найдено координат: %d", coordFound]];
    [self addLog:[NSString stringWithFormat:@"📊 Кандидатов в игроки: %lu", (unsigned long)foundPlayers.count]];
    
    [self showLogWindow];
}

// ========== ЛОГ ==========
+ (void)addLog:(NSString *)text {
    if (!logText) logText = [[NSMutableString alloc] init];
    [logText appendFormat:@"%@\n", text];
    NSLog(@"%@", text);
}

+ (void)showLogWindow {
    if (logWindow) {
        logWindow.hidden = NO;
        return;
    }
    
    CGFloat w = [UIScreen mainScreen].bounds.size.width - 40;
    CGFloat h = [UIScreen mainScreen].bounds.size.height - 150;
    CGFloat x = 20;
    CGFloat y = 70;
    
    logWindow = [[UIWindow alloc] initWithFrame:CGRectMake(x, y, w, h)];
    logWindow.windowLevel = UIWindowLevelAlert + 2;
    logWindow.backgroundColor = [UIColor colorWithWhite:0 alpha:0.95];
    logWindow.layer.cornerRadius = 10;
    
    UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(5, 5, w-10, h-60)];
    tv.backgroundColor = [UIColor blackColor];
    tv.textColor = [UIColor greenColor];
    tv.font = [UIFont fontWithName:@"Courier" size:10];
    tv.text = logText;
    tv.editable = NO;
    [logWindow addSubview:tv];
    
    UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    copyBtn.frame = CGRectMake(20, h-50, 100, 40);
    copyBtn.backgroundColor = [UIColor systemBlueColor];
    copyBtn.layer.cornerRadius = 8;
    [copyBtn setTitle:@"📋 Копировать" forState:UIControlStateNormal];
    [copyBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [copyBtn addTarget:self action:@selector(copyLog) forControlEvents:UIControlEventTouchUpInside];
    [logWindow addSubview:copyBtn];
    
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(w-120, h-50, 100, 40);
    closeBtn.backgroundColor = [UIColor systemRedColor];
    closeBtn.layer.cornerRadius = 8;
    [closeBtn setTitle:@"❌ Закрыть" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [closeBtn addTarget:self action:@selector(closeLogWindow) forControlEvents:UIControlEventTouchUpInside];
    [logWindow addSubview:closeBtn];
    
    [logWindow makeKeyAndVisible];
}

+ (void)closeLogWindow {
    logWindow.hidden = YES;
}

+ (void)copyLog {
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    pasteboard.string = logText;
    
    UILabel *toast = [[UILabel alloc] initWithFrame:CGRectMake(120, 300, 120, 40)];
    toast.backgroundColor = [UIColor blackColor];
    toast.textColor = [UIColor whiteColor];
    toast.text = @"✅ Скопировано";
    toast.textAlignment = NSTextAlignmentCenter;
    toast.layer.cornerRadius = 8;
    toast.layer.masksToBounds = YES;
    [[self mainWindow] addSubview:toast];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [toast removeFromSuperview];
    });
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
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            UIWindow *mainWindow = [ButtonHandler mainWindow];
            if (!mainWindow) return;
            
            floatingButton = [[FloatingButton alloc] initWithFrame:CGRectMake(20, 150, 50, 50)];
            [mainWindow addSubview:floatingButton];
            
            [ButtonHandler addLog:@"✅ Твик загружен"];
        });
    }
}
