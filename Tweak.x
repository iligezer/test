#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>
#import <objc/runtime.h>

// ========== ТВОИ АДРЕСА ==========
#define RVA_Camera_get_main         0x10871faf8
#define RVA_Camera_WorldToScreen    0x10871ed5c
#define RVA_Transform_get_position   0x108792ed0
#define BASE_ADDR 0x1042c4000

// ========== ТВОЙ НИК ==========
#define MY_NICK @"giviNgGrebe"

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
static NSMutableArray *previousScan = nil; // для сравнения сканов
static PlayerData *myPlayer = nil; // найденный игрок

// ========== МОДЕЛЬ ИГРОКА ==========
@interface PlayerData : NSObject
@property (assign) float health;
@property (assign) float x, y, z;
@property (assign) unsigned long address;
@property (strong) NSString *name;
@property (assign) BOOL isMyPlayer; // свой игрок
@end

@implementation PlayerData
- (NSString *)description {
    return [NSString stringWithFormat:@"%@ HP:%.1f (%.1f,%.1f,%.1f) 0x%lx",
            self.isMyPlayer ? @"👤 СВОЙ" : @"👾 ВРАГ",
            self.health, self.x, self.y, self.z, self.address];
}
@end

// ========== ОБЪЯВЛЕНИЕ ==========
@interface ButtonHandler : NSObject
+ (void)showMenu;
+ (void)closeMenu;
+ (void)copyLog;
+ (void)showLogWindow;
+ (void)updateLogWindow;
+ (void)addLog:(NSString*)text;
+ (void)resetScan;
+ (void)findSafeRegions;
+ (void)safeScanForPlayers;
+ (void)smartScanWithMyNick;
+ (void)refineScan; // новый метод для уточнения
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
    CGFloat menuHeight = 450;
    CGFloat menuX = ([UIScreen mainScreen].bounds.size.width - menuWidth) / 2;
    CGFloat menuY = ([UIScreen mainScreen].bounds.size.height - menuHeight) / 2;
    
    UIWindow *menuWindow = [[UIWindow alloc] initWithFrame:CGRectMake(menuX, menuY, menuWidth, menuHeight)];
    menuWindow.windowLevel = UIWindowLevelAlert + 3;
    menuWindow.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.95];
    menuWindow.layer.cornerRadius = 10;
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, menuWidth, 30)];
    title.text = @"⚡ SMART SCANNER";
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
    
    // Кнопка 3: ПОИСК ПО НИКУ
    UIButton *nickScanBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    nickScanBtn.frame = CGRectMake(20, 150, menuWidth-40, 40);
    nickScanBtn.backgroundColor = [UIColor systemPurpleColor];
    [nickScanBtn setTitle:@"🎯 ПОИСК ПО МОЕМУ НИКУ" forState:UIControlStateNormal];
    [nickScanBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [nickScanBtn addTarget:self action:@selector(smartScanWithMyNick) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:nickScanBtn];
    
    // Кнопка 4: УТОЧНИТЬ ПОИСК
    UIButton *refineBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    refineBtn.frame = CGRectMake(20, 200, menuWidth-40, 40);
    refineBtn.backgroundColor = [UIColor systemGreenColor];
    [refineBtn setTitle:@"🔬 УТОЧНИТЬ ПОИСК" forState:UIControlStateNormal];
    [refineBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [refineBtn addTarget:self action:@selector(refineScan) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:refineBtn];
    
    // Кнопка 5: БЕЗОПАСНОЕ СКАНИРОВАНИЕ
    UIButton *safeScanBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    safeScanBtn.frame = CGRectMake(20, 250, menuWidth-40, 40);
    safeScanBtn.backgroundColor = [UIColor systemGrayColor];
    [safeScanBtn setTitle:@"🛡️ БЕЗОПАСНОЕ СКАНИРОВАНИЕ" forState:UIControlStateNormal];
    [safeScanBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [safeScanBtn addTarget:self action:@selector(safeScanForPlayers) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:safeScanBtn];
    
    // Кнопка 6: ПОКАЗАТЬ ЛОГ
    UIButton *logBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    logBtn.frame = CGRectMake(20, 300, menuWidth-40, 40);
    logBtn.backgroundColor = [UIColor systemIndigoColor];
    [logBtn setTitle:@"📋 ПОКАЗАТЬ ЛОГ" forState:UIControlStateNormal];
    [logBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [logBtn addTarget:self action:@selector(showLogWindow) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:logBtn];
    
    // Кнопка 7: ЗАКРЫТЬ
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(20, 350, menuWidth-40, 40);
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
    [previousScan removeAllObjects];
    myPlayer = nil;
    [logText setString:@""];
    [self addLog:@"🔄 ПАМЯТЬ ОЧИЩЕНА"];
    [self addLog:@"1. Зайди в матч"];
    [self addLog:@"2. Нажми НАЙТИ РЕГИОНЫ"];
    [self addLog:@"3. Нажми ПОИСК ПО МОЕМУ НИКУ"];
    [self updateLogWindow];
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
    [self updateLogWindow];
}

// ========== ПОИСК ПО МОЕМУ НИКУ ==========
+ (void)smartScanWithMyNick {
    if (!safeRegions || safeRegions.count == 0) {
        [self addLog:@"❌ Сначала найди регионы"];
        [self updateLogWindow];
        return;
    }
    
    previousScan = [foundPlayers mutableCopy];
    [foundPlayers removeAllObjects];
    myPlayer = nil;
    
    [self addLog:@"\n🎯 ПОИСК ПО МОЕМУ НИКУ"];
    [self addLog:@"================================="];
    
    task_t task = mach_task_self();
    int candidates = 0;
    int nameMatches = 0;
    int totalScanned = 0;
    int regionCount = 0;
    int totalRegions = (int)safeRegions.count;
    
    // Ищем мой ник
    const char *myNickC = [MY_NICK UTF8String];
    NSUInteger myNickLen = strlen(myNickC);
    
    for (NSDictionary *region in safeRegions) {
        regionCount++;
        
        vm_address_t addr = [region[@"address"] unsignedLongLongValue];
        vm_size_t size = [region[@"size"] unsignedLongValue];
        
        uint8_t *buffer = malloc(size);
        vm_size_t data_read = 0;
        
        kern_return_t kr = vm_read_overwrite(task, addr, size, (vm_address_t)buffer, &data_read);
        
        if (kr == KERN_SUCCESS && data_read == size) {
            
            for (int i = 0; i < data_read - 256; i += 2) { // шаг 2 для UTF-16
                totalScanned++;
                
                // Ищем мой ник в UTF-16
                uint16_t *chars = (uint16_t*)(buffer + i);
                
                // Проверяем, совпадает ли с моим ником
                BOOL match = YES;
                for (int j = 0; j < myNickLen; j++) {
                    if (chars[j] != myNickC[j]) {
                        match = NO;
                        break;
                    }
                }
                
                if (match) {
                    nameMatches++;
                    
                    // Нашли ник — ищем здоровье рядом
                    float health = 0;
                    float x = 0, y = 0, z = 0;
                    
                    for (int off = -0x80; off < 0x80; off += 4) {
                        float *h = (float*)(buffer + i + off);
                        if (isfinite(*h) && *h > 0 && *h < 200) {
                            health = *h;
                            
                            // Ищем координаты рядом со здоровьем
                            float *px = (float*)(buffer + i + off + 0x10);
                            float *py = (float*)(buffer + i + off + 0x14);
                            float *pz = (float*)(buffer + i + off + 0x18);
                            
                            if (isfinite(*px) && isfinite(*py) && isfinite(*pz) &&
                                fabs(*px) < 10000 && fabs(*py) < 10000 && fabs(*pz) < 10000) {
                                x = *px;
                                y = *py;
                                z = *pz;
                            }
                            break;
                        }
                    }
                    
                    PlayerData *p = [[PlayerData alloc] init];
                    p.health = health;
                    p.x = x;
                    p.y = y;
                    p.z = z;
                    p.address = addr + i;
                    p.name = MY_NICK;
                    p.isMyPlayer = YES;
                    
                    [foundPlayers addObject:p];
                    myPlayer = p;
                    
                    candidates++;
                    
                    [self addLog:[NSString stringWithFormat:@"\n✅ НАЙДЕН СВОЙ ИГРОК #%d:", candidates]];
                    [self addLog:[NSString stringWithFormat:@"   Адрес ника: 0x%lx", addr + i]];
                    [self addLog:[NSString stringWithFormat:@"   Здоровье: %.1f по адресу 0x%lx", health, addr + i + (health ? 0 : 0)]];
                    [self addLog:[NSString stringWithFormat:@"   Позиция: (%.1f, %.1f, %.1f)", x, y, z]];
                    
                    i += 0x100; // пропускаем структуру
                }
            }
        }
        free(buffer);
        
        if (regionCount % 500 == 0) {
            [self addLog:[NSString stringWithFormat:@"📊 Прогресс: %d/%d регионов, найдено ников: %d", 
                          regionCount, totalRegions, nameMatches]];
            [self updateLogWindow];
        }
        usleep(1000);
    }
    
    [self addLog:@"\n📊 СТАТИСТИКА:"];
    [self addLog:[NSString stringWithFormat:@"📁 Регионов: %d", totalRegions]];
    [self addLog:[NSString stringWithFormat:@"🔍 Проверено адресов: %d", totalScanned]];
    [self addLog:[NSString stringWithFormat:@"📛 Найдено совпадений с ником: %d", nameMatches]];
    [self addLog:[NSString stringWithFormat:@"✅ Найдено структур игрока: %d", candidates]];
    
    if (myPlayer) {
        [self addLog:@"\n🎯 МОЙ ИГРОК НАЙДЕН!"];
        [self addLog:[NSString stringWithFormat:@"   Текущие координаты: (%.1f, %.1f, %.1f)", 
                      myPlayer.x, myPlayer.y, myPlayer.z]];
    } else {
        [self addLog:@"\n❌ Мой ник не найден. Попробуй:"];
        [self addLog:@"   - Убедись, что ты в матче"];
        [self addLog:@"   - Проверь написание ника (giviNgGrebe)"];
        [self addLog:@"   - Нажми УТОЧНИТЬ ПОИСК"];
    }
    
    [self updateLogWindow];
}

// ========== УТОЧНИТЬ ПОИСК (искать рядом с моим игроком) ==========
+ (void)refineScan {
    if (!myPlayer) {
        [self addLog:@"❌ Сначала найди своего игрока (ПОИСК ПО МОЕМУ НИКУ)"];
        [self updateLogWindow];
        return;
    }
    
    [self addLog:@"\n🔬 УТОЧНЕНИЕ ПОИСКА (рядом с моим игроком)"];
    [self addLog:@"========================================="];
    
    previousScan = [foundPlayers mutableCopy];
    [foundPlayers removeAllObjects];
    [foundPlayers addObject:myPlayer]; // сохраняем себя
    
    task_t task = mach_task_self();
    int enemies = 0;
    float searchRadius = 500.0f; // ищем врагов в радиусе 500
    
    for (NSDictionary *region in safeRegions) {
        vm_address_t addr = [region[@"address"] unsignedLongLongValue];
        vm_size_t size = [region[@"size"] unsignedLongValue];
        
        uint8_t *buffer = malloc(size);
        vm_size_t data_read = 0;
        
        kern_return_t kr = vm_read_overwrite(task, addr, size, (vm_address_t)buffer, &data_read);
        
        if (kr == KERN_SUCCESS && data_read == size) {
            
            for (int i = 0; i < data_read - 128; i += 4) {
                float *health = (float*)(buffer + i);
                
                if (isfinite(*health) && *health > 0 && *health < 200) {
                    
                    float *x = (float*)(buffer + i + 0x10);
                    float *y = (float*)(buffer + i + 0x14);
                    float *z = (float*)(buffer + i + 0x18);
                    
                    if (isfinite(*x) && isfinite(*y) && isfinite(*z) &&
                        fabs(*x) < 10000 && fabs(*y) < 10000 && fabs(*z) < 10000) {
                        
                        // Проверяем расстояние до моего игрока
                        float dx = *x - myPlayer.x;
                        float dy = *y - myPlayer.y;
                        float dz = *z - myPlayer.z;
                        float dist = sqrt(dx*dx + dy*dy + dz*dz);
                        
                        if (dist < searchRadius) {
                            enemies++;
                            
                            PlayerData *p = [[PlayerData alloc] init];
                            p.health = *health;
                            p.x = *x;
                            p.y = *y;
                            p.z = *z;
                            p.address = addr + i;
                            p.isMyPlayer = NO;
                            
                            // Ищем имя рядом
                            for (int off = -0x80; off < 0x80; off += 2) {
                                uint16_t *chars = (uint16_t*)(buffer + i + off);
                                
                                int validChars = 0;
                                for (int j = 0; j < 16; j++) {
                                    if (chars[j] > 0x20 && chars[j] < 0x7F) {
                                        validChars++;
                                    } else if (chars[j] >= 0x0400 && chars[j] <= 0x04FF) {
                                        validChars++;
                                    } else if (chars[j] == 0) {
                                        break;
                                    } else {
                                        validChars = 0;
                                        break;
                                    }
                                }
                                
                                if (validChars > 2 && validChars < 16) {
                                    p.name = [[NSString alloc] initWithCharacters:chars length:validChars];
                                    break;
                                }
                            }
                            
                            [foundPlayers addObject:p];
                            
                            if (enemies <= 20) {
                                [self addLog:[NSString stringWithFormat:@"👾 Враг #%d: (%.1f,%.1f,%.1f) HP:%.0f Дист:%.0f %@",
                                              enemies, p.x, p.y, p.z, p.health, dist, p.name ?: @""]];
                            }
                            
                            i += 0x80;
                        }
                    }
                }
            }
        }
        free(buffer);
        usleep(1000);
    }
    
    [self addLog:[NSString stringWithFormat:@"\n📊 Найдено врагов рядом: %d", enemies]];
    [self addLog:[NSString stringWithFormat:@"📊 Всего игроков (я + враги): %lu", 
                  (unsigned long)foundPlayers.count]];
    
    [self updateLogWindow];
}

// ========== БЕЗОПАСНОЕ СКАНИРОВАНИЕ ==========
+ (void)safeScanForPlayers {
    if (!safeRegions || safeRegions.count == 0) {
        [self addLog:@"❌ Сначала найди регионы"];
        [self updateLogWindow];
        return;
    }
    
    [self addLog:@"🛡️ БЕЗОПАСНОЕ СКАНИРОВАНИЕ..."];
    [self addLog:@"================================="];
    
    task_t task = mach_task_self();
    int totalReads = 0;
    int totalValues = 0;
    int regionCount = 0;
    int totalRegions = (int)safeRegions.count;
    
    for (NSDictionary *region in safeRegions) {
        regionCount++;
        
        vm_address_t addr = [region[@"address"] unsignedLongLongValue];
        vm_size_t size = [region[@"size"] unsignedLongValue];
        
        for (vm_address_t offset = 0; offset < size; offset += 4096) {
            
            vm_region_basic_info_data_64_t info;
            mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
            mach_port_t object_name;
            vm_address_t region_addr = addr + offset;
            vm_size_t region_size = 4096;
            
            kern_return_t kr = vm_region_64(task, &region_addr, &region_size, 
                                            VM_REGION_BASIC_INFO_64, 
                                            (vm_region_info_t)&info, &count, &object_name);
            
            if (kr == KERN_SUCCESS && (info.protection & VM_PROT_READ)) {
                
                uint8_t buffer[4096];
                vm_size_t data_read = 0;
                kr = vm_read_overwrite(task, addr + offset, 4096, 
                                        (vm_address_t)buffer, &data_read);
                
                if (kr == KERN_SUCCESS && data_read == 4096) {
                    totalReads++;
                    
                    for (int i = 0; i < 4096 - 64; i += 4) {
                        float *val = (float*)(buffer + i);
                        if (isfinite(*val) && fabs(*val) < 10000) {
                            totalValues++;
                        }
                    }
                }
            }
            
            if (totalReads % 10 == 0) usleep(1000);
        }
        
        if (regionCount % 500 == 0) {
            [self addLog:[NSString stringWithFormat:@"📊 Прогресс: %d/%d регионов", 
                          regionCount, totalRegions]];
            [self updateLogWindow];
        }
    }
    
    [self addLog:@"\n📊 СТАТИСТИКА:"];
    [self addLog:[NSString stringWithFormat:@"📁 Регионов: %d", totalRegions]];
    [self addLog:[NSString stringWithFormat:@"📦 Прочитано блоков: %d", totalReads]];
    [self addLog:[NSString stringWithFormat:@"🔢 Найдено значений: %d", totalValues]];
    
    [self updateLogWindow];
}

// ========== ЛОГ ==========
+ (void)addLog:(NSString *)text {
    if (!logText) logText = [[NSMutableString alloc] init];
    [logText appendFormat:@"%@\n", text];
    NSLog(@"%@", text);
}

+ (void)updateLogWindow {
    if (logWindow) {
        // Обновляем существующее окно
        for (UIView *view in logWindow.subviews) {
            if ([view isKindOfClass:[UITextView class]]) {
                UITextView *tv = (UITextView *)view;
                tv.text = logText;
                // Скроллим вниз чтобы видеть новые записи
                if (tv.text.length > 0) {
                    NSRange bottom = NSMakeRange(tv.text.length - 1, 1);
                    [tv scrollRangeToVisible:bottom];
                }
                break;
            }
        }
    } else {
        [self showLogWindow];
    }
}

+ (void)showLogWindow {
    if (logWindow) {
        logWindow.hidden = NO;
        [self updateLogWindow];
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
