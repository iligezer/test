#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>
#import <objc/runtime.h>

// ========== АДРЕСА ==========
#define RVA_Camera_get_main         0x10871faf8
#define RVA_Camera_WorldToScreen    0x10871ed5c
#define RVA_Transform_get_position   0x108792ed0
#define BASE_ADDR 0x1042c4000

typedef void *(*t_get_main_camera)();
typedef void *(*t_world_to_screen)(void *camera, void *worldPos);
typedef void *(*t_get_position)(void *transform);

static t_get_main_camera Camera_main = NULL;
static t_world_to_screen Camera_WorldToScreen = NULL;
static t_get_position Transform_get_position = NULL;

static NSMutableString *logText = nil;
static UIWindow *logWindow = nil;
static UIButton *floatingButton = nil;
static NSMutableArray *foundPlayers = nil;
static NSMutableArray *safeRegions = nil;

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
+ (void)showLogWindow;
+ (void)addLog:(NSString*)text;
+ (void)resetScan;
+ (void)findSafeRegions;
+ (void)safeScanForPlayers;
+ (void)quickScan;
+ (UIWindow*)mainWindow;
+ (void)handlePan:(UIPanGestureRecognizer*)gesture;
@end

@interface FloatingButton : UIButton
@end

@implementation FloatingButton
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor systemBlueColor];
        self.layer.cornerRadius = frame.size.width/2;
        [self setTitle:@"⚡" forState:UIControlStateNormal];
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:[ButtonHandler class] action:@selector(handlePan:)];
        [self addGestureRecognizer:pan];
        [self addTarget:[ButtonHandler class] action:@selector(showMenu) forControlEvents:UIControlEventTouchUpInside];
    }
    return self;
}
@end

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
    CGFloat menuWidth = 280;
    CGFloat menuHeight = 400;
    CGFloat menuX = ([UIScreen mainScreen].bounds.size.width - menuWidth) / 2;
    CGFloat menuY = ([UIScreen mainScreen].bounds.size.height - menuHeight) / 2;
    
    UIWindow *menuWindow = [[UIWindow alloc] initWithFrame:CGRectMake(menuX, menuY, menuWidth, menuHeight)];
    menuWindow.windowLevel = UIWindowLevelAlert + 3;
    menuWindow.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.95];
    menuWindow.layer.cornerRadius = 10;
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, menuWidth, 30)];
    title.text = @"⚡ IGAMEGOD STYLE";
    title.textColor = [UIColor whiteColor];
    title.textAlignment = NSTextAlignmentCenter;
    [menuWindow addSubview:title];
    
    // Кнопка 1: СБРОС
    UIButton *resetBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    resetBtn.frame = CGRectMake(20, 50, menuWidth-40, 40);
    resetBtn.backgroundColor = [UIColor systemOrangeColor];
    [resetBtn setTitle:@"🔄 СБРОС (ПЕРЕД МАТЧЕМ)" forState:UIControlStateNormal];
    [resetBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [resetBtn addTarget:self action:@selector(resetScan) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:resetBtn];
    
    // Кнопка 2: НАЙТИ РЕГИОНЫ
    UIButton *findRegionsBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    findRegionsBtn.frame = CGRectMake(20, 100, menuWidth-40, 40);
    findRegionsBtn.backgroundColor = [UIColor systemBlueColor];
    [findRegionsBtn setTitle:@"🔍 НАЙТИ РЕГИОНЫ" forState:UIControlStateNormal];
    [findRegionsBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [findRegionsBtn addTarget:self action:@selector(findSafeRegions) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:findRegionsBtn];
    
    // Кнопка 3: БЕЗОПАСНОЕ СКАНИРОВАНИЕ
    UIButton *safeScanBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    safeScanBtn.frame = CGRectMake(20, 150, menuWidth-40, 40);
    safeScanBtn.backgroundColor = [UIColor systemPurpleColor];
    [safeScanBtn setTitle:@"🛡️ БЕЗОПАСНОЕ СКАНИРОВАНИЕ" forState:UIControlStateNormal];
    [safeScanBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [safeScanBtn addTarget:self action:@selector(safeScanForPlayers) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:safeScanBtn];
    
    // Кнопка 4: БЫСТРОЕ СКАНИРОВАНИЕ
    UIButton *quickScanBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    quickScanBtn.frame = CGRectMake(20, 200, menuWidth-40, 40);
    quickScanBtn.backgroundColor = [UIColor systemGreenColor];
    [quickScanBtn setTitle:@"⚡ БЫСТРОЕ СКАНИРОВАНИЕ" forState:UIControlStateNormal];
    [quickScanBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [quickScanBtn addTarget:self action:@selector(quickScan) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:quickScanBtn];
    
    // Кнопка 5: ПОКАЗАТЬ ЛОГ
    UIButton *logBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    logBtn.frame = CGRectMake(20, 250, menuWidth-40, 40);
    logBtn.backgroundColor = [UIColor systemGrayColor];
    [logBtn setTitle:@"📋 ПОКАЗАТЬ ЛОГ" forState:UIControlStateNormal];
    [logBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [logBtn addTarget:self action:@selector(showLogWindow) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:logBtn];
    
    // Кнопка 6: ЗАКРЫТЬ
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(20, 300, menuWidth-40, 40);
    closeBtn.backgroundColor = [UIColor systemRedColor];
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

// ========== СБРОС ==========
+ (void)resetScan {
    [safeRegions removeAllObjects];
    [foundPlayers removeAllObjects];
    [logText setString:@""];
    [self addLog:@"🔄 ПАМЯТЬ ОЧИЩЕНА"];
    [self addLog:@"1. Зайди в матч"];
    [self addLog:@"2. Нажми НАЙТИ РЕГИОНЫ"];
    [self addLog:@"3. Нажми СКАНИРОВАТЬ"];
    [self showLogWindow];
}

// ========== НАЙТИ БЕЗОПАСНЫЕ РЕГИОНЫ ==========
+ (void)findSafeRegions {
    [self addLog:@"🔍 ПОИСК БЕЗОПАСНЫХ РЕГИОНОВ..."];
    
    safeRegions = [NSMutableArray array];
    task_t task = mach_task_self();
    vm_address_t address = 0;
    vm_size_t size = 0;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object_name;
    
    int safeCount = 0;
    
    while (vm_region_64(task, &address, &size, VM_REGION_BASIC_INFO_64, 
                        (vm_region_info_t)&info, &count, &object_name) == KERN_SUCCESS) {
        
        // Только читаемые и доступные для записи
        if ((info.protection & VM_PROT_READ) && (info.protection & VM_PROT_WRITE)) {
            if (size >= 4096 && size <= 10*1024*1024) {
                safeCount++;
                [safeRegions addObject:@{
                    @"address": @(address),
                    @"size": @(size)
                }];
            }
        }
        
        address += size;
        if (safeCount % 100 == 0) usleep(1000);
    }
    
    [self addLog:[NSString stringWithFormat:@"📊 Найдено безопасных регионов: %d", safeCount]];
    [self showLogWindow];
}

// ========== БЕЗОПАСНОЕ СКАНИРОВАНИЕ (ПОБЛОЧНО) ==========
+ (void)safeScanForPlayers {
    if (!safeRegions || safeRegions.count == 0) {
        [self addLog:@"❌ Сначала найди регионы"];
        [self showLogWindow];
        return;
    }
    
    [foundPlayers removeAllObjects];
    [self addLog:@"🎯 БЕЗОПАСНОЕ СКАНИРОВАНИЕ..."];
    
    task_t task = mach_task_self();
    int totalReads = 0;
    int candidates = 0;
    
    for (NSDictionary *region in safeRegions) {
        vm_address_t addr = [region[@"address"] unsignedLongLongValue];
        vm_size_t size = [region[@"size"] unsignedLongValue];
        
        // Читаем блоками по 4KB
        for (vm_address_t offset = 0; offset < size; offset += 4096) {
            
            // Проверяем регион перед чтением
            vm_region_basic_info_data_64_t info;
            mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
            mach_port_t object_name;
            vm_address_t region_addr = addr + offset;
            vm_size_t region_size = 4096;
            
            kern_return_t kr = vm_region_64(task, &region_addr, &region_size, 
                                            VM_REGION_BASIC_INFO_64, 
                                            (vm_region_info_t)&info, &count, &object_name);
            
            if (kr == KERN_SUCCESS && (info.protection & VM_PROT_READ)) {
                
                // Читаем блок
                uint8_t buffer[4096];
                vm_size_t data_read = 0;
                kr = vm_read_overwrite(task, addr + offset, 4096, 
                                        (vm_address_t)buffer, &data_read);
                
                if (kr == KERN_SUCCESS && data_read == 4096) {
                    totalReads++;
                    
                    // Ищем float значения в блоке
                    for (int i = 0; i < 4096 - 64; i += 4) {
                        float *val = (float*)(buffer + i);
                        if (isfinite(*val) && fabs(*val) < 10000) {
                            candidates++;
                        }
                    }
                }
            }
            
            // Пауза между блоками
            if (totalReads % 10 == 0) usleep(1000);
        }
    }
    
    [self addLog:[NSString stringWithFormat:@"📊 Прочитано блоков: %d", totalReads]];
    [self addLog:[NSString stringWithFormat:@"📊 Найдено значений: %d", candidates]];
    [self showLogWindow];
}

// ========== БЫСТРОЕ СКАНИРОВАНИЕ (ТОЛЬКО ПО ИЗВЕСТНЫМ АДРЕСАМ) ==========
+ (void)quickScan {
    if (!safeRegions || safeRegions.count == 0) {
        [self addLog:@"❌ Сначала найди регионы"];
        [self showLogWindow];
        return;
    }
    
    [foundPlayers removeAllObjects];
    [self addLog:@"⚡ БЫСТРОЕ СКАНИРОВАНИЕ..."];
    
    task_t task = mach_task_self();
    int candidates = 0;
    
    // Ищем известные паттерны (здоровье ~100)
    float targetHealth = 100.0f;
    float tolerance = 5.0f;
    
    for (NSDictionary *region in safeRegions) {
        vm_address_t addr = [region[@"address"] unsignedLongLongValue];
        vm_size_t size = [region[@"size"] unsignedLongValue];
        
        // Читаем весь регион
        uint8_t *buffer = malloc(size);
        vm_size_t data_read = 0;
        
        kern_return_t kr = vm_read_overwrite(task, addr, size, (vm_address_t)buffer, &data_read);
        
        if (kr == KERN_SUCCESS && data_read == size) {
            
            for (int i = 0; i < data_read - 64; i += 4) {
                float *health = (float*)(buffer + i);
                
                // Ищем здоровье
                if (isfinite(*health) && fabs(*health - targetHealth) < tolerance) {
                    
                    // Проверяем координаты рядом
                    float *x = (float*)(buffer + i + 0x10);
                    float *y = (float*)(buffer + i + 0x14);
                    float *z = (float*)(buffer + i + 0x18);
                    
                    if (isfinite(*x) && isfinite(*y) && isfinite(*z) &&
                        fabs(*x) < 10000 && fabs(*y) < 10000 && fabs(*z) < 10000) {
                        
                        candidates++;
                        
                        PlayerData *p = [[PlayerData alloc] init];
                        p.health = *health;
                        p.x = *x;
                        p.y = *y;
                        p.z = *z;
                        p.address = addr + i;
                        
                        [foundPlayers addObject:p];
                        
                        if (candidates <= 20) {
                            [self addLog:[NSString stringWithFormat:@"🎯 Кандидат %d: (%.0f,%.0f,%.0f) HP:%.0f",
                                          candidates, p.x, p.y, p.z, p.health]];
                        }
                        
                        i += 0x80; // пропускаем структуру
                    }
                }
            }
        }
        free(buffer);
        usleep(1000);
    }
    
    [self addLog:[NSString stringWithFormat:@"\n📊 Найдено кандидатов: %d", candidates]];
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
    [copyBtn setTitle:@"📋 Копировать" forState:UIControlStateNormal];
    [copyBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [copyBtn addTarget:self action:@selector(copyLog) forControlEvents:UIControlEventTouchUpInside];
    [logWindow addSubview:copyBtn];
    
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(w-120, h-50, 100, 40);
    closeBtn.backgroundColor = [UIColor systemRedColor];
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
