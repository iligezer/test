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

// ========== МОДЕЛЬ ИГРОКА ==========
@interface PlayerData : NSObject
@property (assign) float health;
@property (assign) float x, y, z;
@property (assign) unsigned long address;
@property (strong) NSString *name;
@property (assign) BOOL isMyPlayer;
@end

@implementation PlayerData
- (NSString *)description {
    return [NSString stringWithFormat:@"%@ HP:%.1f (%.1f,%.1f,%.1f) 0x%lx",
            self.isMyPlayer ? @"👤 СВОЙ" : @"👾 ВРАГ",
            self.health, self.x, self.y, self.z, self.address];
}
@end

// ========== ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ ==========
static t_get_main_camera Camera_main = NULL;
static t_world_to_screen Camera_WorldToScreen = NULL;
static t_get_position Transform_get_position = NULL;

static NSMutableString *logText = nil;
static UIWindow *logWindow = nil;
static UIButton *floatingButton = nil;
static NSMutableArray *foundPlayers = nil;
static NSMutableArray *safeRegions = nil;
static PlayerData *myPlayer = nil;

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
+ (void)scanRealPlayers;
+ (void)refineScanAroundMyPlayer;
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
    title.text = @"⚡ REAL PLAYER SCANNER";
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
    
    // Кнопка 3: СКАНИРОВАТЬ РЕАЛЬНЫХ ИГРОКОВ
    UIButton *realScanBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    realScanBtn.frame = CGRectMake(20, 150, menuWidth-40, 40);
    realScanBtn.backgroundColor = [UIColor systemPurpleColor];
    [realScanBtn setTitle:@"🎯 СКАНИРОВАТЬ РЕАЛЬНЫХ ИГРОКОВ" forState:UIControlStateNormal];
    [realScanBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [realScanBtn addTarget:self action:@selector(scanRealPlayers) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:realScanBtn];
    
    // Кнопка 4: УТОЧНИТЬ ВОКРУГ СЕБЯ
    UIButton *refineBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    refineBtn.frame = CGRectMake(20, 200, menuWidth-40, 40);
    refineBtn.backgroundColor = [UIColor systemGreenColor];
    [refineBtn setTitle:@"🎯 УТОЧНИТЬ ВОКРУГ СЕБЯ" forState:UIControlStateNormal];
    [refineBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [refineBtn addTarget:self action:@selector(refineScanAroundMyPlayer) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:refineBtn];
    
    // Кнопка 5: ПОКАЗАТЬ ЛОГ
    UIButton *logBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    logBtn.frame = CGRectMake(20, 250, menuWidth-40, 40);
    logBtn.backgroundColor = [UIColor systemIndigoColor];
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
    myPlayer = nil;
    [logText setString:@""];
    [self addLog:@"🔄 ПАМЯТЬ ОЧИЩЕНА"];
    [self addLog:@"1. Зайди в матч"];
    [self addLog:@"2. Нажми НАЙТИ РЕГИОНЫ"];
    [self addLog:@"3. Нажми СКАНИРОВАТЬ РЕАЛЬНЫХ ИГРОКОВ"];
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

// ========== СКАНИРОВАНИЕ РЕАЛЬНЫХ ИГРОКОВ (С ЖЕСТКИМИ ФИЛЬТРАМИ) ==========
+ (void)scanRealPlayers {
    if (!safeRegions || safeRegions.count == 0) {
        [self addLog:@"❌ Сначала найди регионы"];
        [self updateLogWindow];
        return;
    }
    
    [foundPlayers removeAllObjects];
    myPlayer = nil;
    
    [self addLog:@"\n🎯 СКАНИРОВАНИЕ РЕАЛЬНЫХ ИГРОКОВ"];
    [self addLog:@"================================="];
    
    task_t task = mach_task_self();
    int realPlayers = 0;
    int candidates = 0;
    int regionCount = 0;
    int totalRegions = (int)safeRegions.count;
    
    for (NSDictionary *region in safeRegions) {
        regionCount++;
        
        vm_address_t addr = [region[@"address"] unsignedLongLongValue];
        vm_size_t size = [region[@"size"] unsignedLongValue];
        
        uint8_t *buffer = malloc(size);
        vm_size_t data_read = 0;
        
        kern_return_t kr = vm_read_overwrite(task, addr, size, (vm_address_t)buffer, &data_read);
        
        if (kr == KERN_SUCCESS && data_read == size) {
            
            // Проходим с шагом 4 байта
            for (int i = 0; i < data_read - 256; i += 4) {
                
                // Сначала ищем здоровье (главный признак)
                float *healthPtr = (float*)(buffer + i);
                
                // Здоровье должно быть от 10 до 200
                if (isfinite(*healthPtr) && *healthPtr >= 10 && *healthPtr <= 200) {
                    
                    // Ищем координаты рядом (обычно через 0x10-0x20 байт)
                    for (int offset = 0x10; offset < 0x40; offset += 4) {
                        float *x = (float*)(buffer + i + offset);
                        float *y = (float*)(buffer + i + offset + 4);
                        float *z = (float*)(buffer + i + offset + 8);
                        
                        // Проверяем координаты
                        if (isfinite(*x) && isfinite(*y) && isfinite(*z) &&
                            fabs(*x) > 1.0 && fabs(*y) > 1.0 && fabs(*z) > 1.0 && // не около нуля
                            fabs(*x) < 5000 && fabs(*y) < 5000 && fabs(*z) < 5000) { // разумные пределы
                            
                            candidates++;
                            
                            PlayerData *p = [[PlayerData alloc] init];
                            p.health = *healthPtr;
                            p.x = *x;
                            p.y = *y;
                            p.z = *z;
                            p.address = addr + i;
                            
                            // Ищем имя рядом (UTF-16)
                            for (int nameOff = -0x80; nameOff < 0x80; nameOff += 2) {
                                uint16_t *chars = (uint16_t*)(buffer + i + nameOff);
                                
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
                            
                            // Проверяем, не мой ли это ник
                            if (p.name && [p.name isEqualToString:MY_NICK]) {
                                p.isMyPlayer = YES;
                                myPlayer = p;
                                realPlayers++;
                                [self addLog:[NSString stringWithFormat:@"\n✅ НАЙДЕН СВОЙ ИГРОК #%d:", realPlayers]];
                                [self addLog:[NSString stringWithFormat:@"   Адрес здоровья: 0x%lx", p.address]];
                                [self addLog:[NSString stringWithFormat:@"   Координаты: (%.1f, %.1f, %.1f)", p.x, p.y, p.z]];
                                [self addLog:[NSString stringWithFormat:@"   Здоровье: %.1f", p.health]];
                                [self addLog:[NSString stringWithFormat:@"   Имя: %@", p.name]];
                            } else {
                                // Показываем только реальных игроков (не кандидатов)
                                realPlayers++;
                                [self addLog:[NSString stringWithFormat:@"\n👾 РЕАЛЬНЫЙ ИГРОК #%d: (%.1f,%.1f,%.1f) HP:%.0f %@",
                                              realPlayers, p.x, p.y, p.z, p.health, p.name ?: @"?"]];
                            }
                            
                            [foundPlayers addObject:p];
                            
                            // Пропускаем структуру
                            i += 0x80;
                            break;
                        }
                    }
                }
            }
        }
        free(buffer);
        
        if (regionCount % 500 == 0) {
            [self addLog:[NSString stringWithFormat:@"📊 Прогресс: %d/%d регионов, найдено игроков: %d", 
                          regionCount, totalRegions, realPlayers]];
            [self updateLogWindow];
        }
        usleep(1000);
    }
    
    [self addLog:@"\n📊 СТАТИСТИКА:"];
    [self addLog:[NSString stringWithFormat:@"📁 Регионов: %d", totalRegions]];
    [self addLog:[NSString stringWithFormat:@"🎯 Найдено реальных игроков: %d", realPlayers]];
    
    if (myPlayer) {
        [self addLog:@"\n✅ СВОЙ ИГРОК УСПЕШНО ИДЕНТИФИЦИРОВАН"];
    } else {
        [self addLog:@"\n❌ Свой игрок не найден. Попробуй УТОЧНИТЬ ВОКРУГ СЕБЯ"];
        [self addLog:@"   Возможно твой ник не giviNgGrebe?"];
    }
    
    [self updateLogWindow];
}

// ========== УТОЧНЕНИЕ ВОКРУГ СВОЕГО ИГРОКА ==========
+ (void)refineScanAroundMyPlayer {
    if (!myPlayer) {
        [self addLog:@"❌ Сначала найди своего игрока"];
        [self updateLogWindow];
        return;
    }
    
    [self addLog:@"\n🎯 УТОЧНЕНИЕ ВОКРУГ СВОЕГО ИГРОКА"];
    [self addLog:@"================================="];
    
    task_t task = mach_task_self();
    int enemies = 0;
    float searchRadius = 500.0f;
    
    [self addLog:[NSString stringWithFormat:@"📍 Мои координаты: (%.1f, %.1f, %.1f)", 
                  myPlayer.x, myPlayer.y, myPlayer.z]];
    [self addLog:[NSString stringWithFormat:@"🔍 Поиск врагов в радиусе %.0f", searchRadius]];
    
    for (PlayerData *p in foundPlayers) {
        if (p.isMyPlayer) continue;
        
        float dx = p.x - myPlayer.x;
        float dy = p.y - myPlayer.y;
        float dz = p.z - myPlayer.z;
        float dist = sqrt(dx*dx + dy*dy + dz*dz);
        
        if (dist < searchRadius) {
            enemies++;
            [self addLog:[NSString stringWithFormat:@"👾 Враг #%d: (%.1f,%.1f,%.1f) HP:%.0f Дист:%.0f %@",
                          enemies, p.x, p.y, p.z, p.health, dist, p.name ?: @""]];
        }
    }
    
    [self addLog:[NSString stringWithFormat:@"\n📊 Найдено врагов рядом: %d", enemies]];
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
        for (UIView *view in logWindow.subviews) {
            if ([view isKindOfClass:[UITextView class]]) {
                UITextView *tv = (UITextView *)view;
                tv.text = logText;
                if (tv.text.length > 0) {
                    NSRange bottom = NSMakeRange(tv.text.length - 1, 1);
                    [tv scrollRangeToVisible:bottom];
                }
                break;
            }
        }
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
