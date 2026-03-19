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
+ (void)findSafeRegions;
+ (void)scanForPlayers;
+ (void)resetScan;
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
    CGFloat menuHeight = 350;
    CGFloat menuX = ([UIScreen mainScreen].bounds.size.width - menuWidth) / 2;
    CGFloat menuY = ([UIScreen mainScreen].bounds.size.height - menuHeight) / 2;
    
    UIWindow *menuWindow = [[UIWindow alloc] initWithFrame:CGRectMake(menuX, menuY, menuWidth, menuHeight)];
    menuWindow.windowLevel = UIWindowLevelAlert + 3;
    menuWindow.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.95];
    menuWindow.layer.cornerRadius = 10;
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, menuWidth, 30)];
    title.text = @"⚡ PLAYER SCANNER";
    title.textColor = [UIColor whiteColor];
    title.textAlignment = NSTextAlignmentCenter;
    [menuWindow addSubview:title];
    
    // Кнопка 1: СБРОС (нажать в меню перед матчем)
    UIButton *resetBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    resetBtn.frame = CGRectMake(20, 50, menuWidth-40, 40);
    resetBtn.backgroundColor = [UIColor systemOrangeColor];
    [resetBtn setTitle:@"🔄 СБРОС (ПЕРЕД МАТЧЕМ)" forState:UIControlStateNormal];
    [resetBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [resetBtn addTarget:self action:@selector(resetScan) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:resetBtn];
    
    // Кнопка 2: НАЙТИ РЕГИОНЫ (после загрузки карты)
    UIButton *findRegionsBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    findRegionsBtn.frame = CGRectMake(20, 100, menuWidth-40, 40);
    findRegionsBtn.backgroundColor = [UIColor systemBlueColor];
    [findRegionsBtn setTitle:@"🔍 НАЙТИ РЕГИОНЫ" forState:UIControlStateNormal];
    [findRegionsBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [findRegionsBtn addTarget:self action:@selector(findSafeRegions) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:findRegionsBtn];
    
    // Кнопка 3: ИСКАТЬ ИГРОКОВ (после регионов)
    UIButton *scanPlayersBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    scanPlayersBtn.frame = CGRectMake(20, 150, menuWidth-40, 40);
    scanPlayersBtn.backgroundColor = [UIColor systemPurpleColor];
    [scanPlayersBtn setTitle:@"🎯 ИСКАТЬ ИГРОКОВ" forState:UIControlStateNormal];
    [scanPlayersBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [scanPlayersBtn addTarget:self action:@selector(scanForPlayers) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:scanPlayersBtn];
    
    // Кнопка 4: ПОКАЗАТЬ ЛОГ
    UIButton *logBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    logBtn.frame = CGRectMake(20, 200, menuWidth-40, 40);
    logBtn.backgroundColor = [UIColor systemGrayColor];
    [logBtn setTitle:@"📋 ПОКАЗАТЬ ЛОГ" forState:UIControlStateNormal];
    [logBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [logBtn addTarget:self action:@selector(showLogWindow) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:logBtn];
    
    // Кнопка 5: ЗАКРЫТЬ
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(20, 250, menuWidth-40, 40);
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

// ========== СБРОС (нажать В МЕНЮ перед матчем) ==========
+ (void)resetScan {
    [safeRegions removeAllObjects];
    [foundPlayers removeAllObjects];
    [logText setString:@""];
    [self addLog:@"🔄 ПАМЯТЬ ОЧИЩЕНА"];
    [self addLog:@"1. Зайди в матч"];
    [self addLog:@"2. Нажми НАЙТИ РЕГИОНЫ"];
    [self addLog:@"3. Нажми ИСКАТЬ ИГРОКОВ"];
    [self showLogWindow];
}

// ========== ШАГ 1: НАЙТИ БЕЗОПАСНЫЕ РЕГИОНЫ (в матче) ==========
+ (void)findSafeRegions {
    [logText setString:@""];
    [self addLog:@"🔍 ПОИСК БЕЗОПАСНЫХ РЕГИОНОВ..."];
    
    safeRegions = [NSMutableArray array];
    
    task_t task = mach_task_self();
    vm_address_t address = 0;
    vm_size_t size = 0;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object_name;
    
    int regionCount = 0;
    int safeCount = 0;
    
    while (vm_region_64(task, &address, &size, VM_REGION_BASIC_INFO_64, 
                        (vm_region_info_t)&info, &count, &object_name) == KERN_SUCCESS) {
        
        regionCount++;
        
        // Только читаемые регионы
        if (info.protection & VM_PROT_READ) {
            if (size >= 4096 && size <= 20*1024*1024) {
                
                // Проверяем, читается ли
                uint32_t test = 0;
                vm_size_t test_read = 0;
                kern_return_t kr = vm_read_overwrite(task, address, 4, (vm_address_t)&test, &test_read);
                
                if (kr == KERN_SUCCESS) {
                    safeCount++;
                    [safeRegions addObject:@{
                        @"address": @(address),
                        @"size": @(size)
                    }];
                }
            }
        }
        
        address += size;
        if (regionCount % 100 == 0) usleep(1000);
    }
    
    [self addLog:[NSString stringWithFormat:@"📊 Найдено безопасных регионов: %d", safeCount]];
    [self addLog:@"✅ Теперь можно искать игроков"];
    [self showLogWindow];
}

// ========== ШАГ 2: ИСКАТЬ ИГРОКОВ (только в безопасных регионах) ==========
+ (void)scanForPlayers {
    if (!safeRegions || safeRegions.count == 0) {
        [self addLog:@"❌ Сначала найди регионы (кнопка НАЙТИ РЕГИОНЫ)"];
        [self showLogWindow];
        return;
    }
    
    [self addLog:@"🎯 ПОИСК ИГРОКОВ..."];
    foundPlayers = [NSMutableArray array];
    task_t task = mach_task_self();
    int candidates = 0;
    
    for (NSDictionary *region in safeRegions) {
        vm_address_t addr = [region[@"address"] unsignedLongLongValue];
        vm_size_t size = [region[@"size"] unsignedLongValue];
        
        uint8_t *buffer = malloc(size);
        vm_size_t data_read = 0;
        
        kern_return_t kr = vm_read_overwrite(task, addr, size, (vm_address_t)buffer, &data_read);
        
        if (kr == KERN_SUCCESS && data_read == size) {
            
            for (int i = 0; i < data_read - 64; i += 4) {
                
                float *x = (float*)(buffer + i);
                float *y = (float*)(buffer + i + 4);
                float *z = (float*)(buffer + i + 8);
                
                if (isfinite(*x) && isfinite(*y) && isfinite(*z) &&
                    fabs(*x) < 10000 && fabs(*y) < 10000 && fabs(*z) < 10000) {
                    
                    float health = 0;
                    for (int off = -0x40; off < 0x40; off += 4) {
                        float *h = (float*)(buffer + i + off);
                        if (isfinite(*h) && *h > 0 && *h < 200) {
                            health = *h;
                            break;
                        }
                    }
                    
                    if (health > 0) {
                        candidates++;
                        
                        // Ищем имя (UTF-16)
                        NSString *name = nil;
                        for (int off = -0x80; off < 0x80; off += 2) {
                            uint16_t *chars = (uint16_t*)(buffer + i + off);
                            
                            int validChars = 0;
                            for (int j = 0; j < 16; j++) {
                                if ((chars[j] > 0x20 && chars[j] < 0x7F) || // английские
                                    (chars[j] >= 0x0400 && chars[j] <= 0x04FF)) { // русские
                                    validChars++;
                                } else if (chars[j] == 0) {
                                    break;
                                } else {
                                    validChars = 0;
                                    break;
                                }
                            }
                            
                            if (validChars > 2 && validChars < 20) {
                                name = [[NSString alloc] initWithCharacters:chars length:validChars];
                                break;
                            }
                        }
                        
                        PlayerData *p = [[PlayerData alloc] init];
                        p.health = health;
                        p.x = *x;
                        p.y = *y;
                        p.z = *z;
                        p.name = name;
                        
                        [foundPlayers addObject:p];
                        
                        [self addLog:[NSString stringWithFormat:@"🎯 Игрок %d: (%.0f,%.0f,%.0f) HP:%.0f %@",
                                      candidates, p.x, p.y, p.z, p.health, p.name ?: @""]];
                        
                        i += 0x80; // пропускаем структуру
                    }
                }
            }
        }
        free(buffer);
        usleep(1000);
    }
    
    [self addLog:[NSString stringWithFormat:@"\n📊 Найдено игроков: %d", candidates]];
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
            [ButtonHandler addLog:@"⚡ Нажми СБРОС перед матчем"];
        });
    }
}
