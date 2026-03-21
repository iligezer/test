#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>

// ===== ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ =====
static UIWindow *g_logWindow = nil;
static UITextView *g_logTextView = nil;
static NSMutableString *g_logText = nil;
static BOOL g_isSearching = NO;
static FloatButton *g_floatButton = nil;

// ===== РАБОТА С ПАМЯТЬЮ =====
uintptr_t getBaseAddress() {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (strstr(name, "UnityFramework") != NULL) {
            return (uintptr_t)_dyld_get_image_header(i);
        }
    }
    return 0;
}

size_t safeRead(uintptr_t address, void *buffer, size_t size) {
    @try {
        vm_size_t bytesRead = 0;
        kern_return_t kr = vm_read_overwrite(current_task(), (vm_address_t)address, size, (vm_address_t)buffer, &bytesRead);
        return (kr == KERN_SUCCESS) ? bytesRead : 0;
    } @catch (NSException *e) {
        return 0;
    }
}

void addLog(NSString *format, ...) {
    if (!g_logText) g_logText = [[NSMutableString alloc] init];
    
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    [g_logText appendString:message];
    [g_logText appendString:@"\n"];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_logTextView) {
            g_logTextView.text = g_logText;
            NSRange bottom = NSMakeRange(g_logTextView.text.length - 1, 1);
            [g_logTextView scrollRangeToVisible:bottom];
        }
    });
}

// ===== БЫСТРЫЙ ПОИСК (БЕЗ ЗАВИСАНИЙ) =====
void quickSearch() {
    if (g_isSearching) {
        addLog(@"⚠️ Поиск уже идет...");
        return;
    }
    g_isSearching = YES;
    
    addLog(@"\n🔍 ПОИСК ROOMCONTROLLER");
    addLog(@"=================================");
    
    uintptr_t base = getBaseAddress();
    if (base == 0) {
        addLog(@"❌ UnityFramework не найден");
        g_isSearching = NO;
        return;
    }
    
    addLog(@"📍 Базовый адрес: 0x%lx", base);
    addLog(@"💡 Должен быть активный матч!");
    
    // ТОЛЬКО ДИАПАЗОН 0x100000000 - 0x180000000
    uintptr_t startAddr = 0x100000000;
    uintptr_t endAddr = 0x180000000;
    int foundPlayers = 0;
    uintptr_t playerAddrs[50] = {0};
    
    addLog(@"📊 Сканирую диапазон...");
    
    // Сканируем с шагом 0x1000 (быстро)
    for (uintptr_t addr = startAddr; addr < endAddr && foundPlayers < 30; addr += 0x1000) {
        for (int offset = 0; offset < 0x1000 && foundPlayers < 30; offset += 16) {
            uintptr_t ptr = 0;
            if (safeRead(addr + offset, &ptr, 8) != 8) continue;
            if (ptr < startAddr || ptr > endAddr) continue;
            
            int team = 0, id = 0;
            if (safeRead(ptr + 0x34, &team, 4) == 4 &&
                safeRead(ptr + 0x10, &id, 4) == 4) {
                if ((team == 0 || team == 1) && id > 1000000 && id < 200000000) {
                    // Проверяем, не дубликат
                    BOOL duplicate = NO;
                    for (int i = 0; i < foundPlayers; i++) {
                        if (playerAddrs[i] == ptr) { duplicate = YES; break; }
                    }
                    if (!duplicate) {
                        playerAddrs[foundPlayers++] = ptr;
                        addLog(@"   🎮 Игрок %d: 0x%lx (ID: %d, Team: %d)", foundPlayers, ptr, id, team);
                    }
                }
            }
        }
    }
    
    addLog(@"\n📊 Найдено игроков: %d", foundPlayers);
    
    if (foundPlayers == 0) {
        addLog(@"❌ Игроки не найдены!");
        addLog(@"💡 Зайди в матч и нажми снова");
        g_isSearching = NO;
        return;
    }
    
    // Ищем указатель на первого игрока (RoomController)
    addLog(@"\n🔍 Ищу RoomController...");
    
    for (int i = 0; i < foundPlayers && i < 5; i++) {
        uintptr_t targetPlayer = playerAddrs[i];
        addLog(@"\n📌 Проверяю игрока 0x%lx", targetPlayer);
        
        int ptrFound = 0;
        for (uintptr_t addr = startAddr; addr < startAddr + 0x2000000 && ptrFound < 5; addr += 8) {
            uintptr_t ptr = 0;
            if (safeRead(addr, &ptr, 8) != 8) continue;
            if (ptr == targetPlayer) {
                ptrFound++;
                addLog(@"   🔗 Указатель найден: 0x%lx", addr);
                
                // Проверяем массив по +0x140
                uintptr_t arrayPtr = 0;
                if (safeRead(addr + 0x140, &arrayPtr, 8) == 8 && arrayPtr > startAddr) {
                    addLog(@"   📦 Массив игроков по +0x140: 0x%lx", arrayPtr);
                    
                    // Считаем игроков в массиве
                    int count = 0;
                    for (int j = 0; j < 32; j++) {
                        uintptr_t p = 0;
                        if (safeRead(arrayPtr + j * 8, &p, 8) == 8 && p != 0) {
                            count++;
                        } else break;
                    }
                    addLog(@"   👥 Игроков в массиве: %d", count);
                    addLog(@"\n🎯 ROOMCONTROLLER: 0x%lx", addr);
                    addLog(@"🎯 МАССИВ ИГРОКОВ: 0x%lx", arrayPtr);
                    
                    // Выводим всех игроков
                    addLog(@"\n📋 ВСЕ ИГРОКИ:");
                    for (int j = 0; j < count; j++) {
                        uintptr_t p = 0;
                        safeRead(arrayPtr + j * 8, &p, 8);
                        int pid = 0, pteam = 0;
                        safeRead(p + 0x10, &pid, 4);
                        safeRead(p + 0x34, &pteam, 4);
                        addLog(@"   [%d] 0x%lx | ID: %d | Team: %d", j, p, pid, pteam);
                    }
                    
                    g_isSearching = NO;
                    return;
                }
            }
        }
    }
    
    addLog(@"\n❌ RoomController не найден");
    addLog(@"💡 Попробуй еще раз в активном матче");
    g_isSearching = NO;
}

// ===== СОЗДАНИЕ ОКНА (ФИКСИРОВАННОЕ ПОЛОЖЕНИЕ) =====
void createLogWindow() {
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
    
    if (!keyWindow) return;
    
    // ФИКСИРОВАННОЕ ПОЛОЖЕНИЕ — не зависит от ориентации
    CGFloat width = 320;
    CGFloat height = 460;
    CGFloat x = (keyWindow.frame.size.width - width) / 2;
    CGFloat y = (keyWindow.frame.size.height - height) / 2;
    
    if (g_logWindow) {
        g_logWindow.hidden = YES;
        g_logWindow = nil;
    }
    
    g_logWindow = [[UIWindow alloc] initWithFrame:CGRectMake(x, y, width, height)];
    g_logWindow.windowLevel = UIWindowLevelAlert + 2;
    g_logWindow.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.98];
    g_logWindow.layer.cornerRadius = 20;
    g_logWindow.layer.borderWidth = 2;
    g_logWindow.layer.borderColor = [UIColor systemBlueColor].CGColor;
    g_logWindow.hidden = NO;
    
    // Заголовок
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 12, width, 30)];
    title.text = @"🎯 ESP SCANNER";
    title.textColor = [UIColor systemBlueColor];
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:18];
    [g_logWindow addSubview:title];
    
    // Текст
    g_logTextView = [[UITextView alloc] initWithFrame:CGRectMake(10, 50, width - 20, 320)];
    g_logTextView.backgroundColor = [UIColor blackColor];
    g_logTextView.textColor = [UIColor greenColor];
    g_logTextView.font = [UIFont fontWithName:@"Courier" size:11];
    g_logTextView.editable = NO;
    g_logTextView.selectable = YES;
    g_logTextView.layer.cornerRadius = 10;
    [g_logWindow addSubview:g_logTextView];
    
    // Кнопка поиска
    UIButton *searchBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    searchBtn.frame = CGRectMake(15, 380, (width - 45) / 2, 42);
    [searchBtn setTitle:@"🔍 НАЙТИ" forState:UIControlStateNormal];
    searchBtn.backgroundColor = [UIColor systemBlueColor];
    [searchBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    searchBtn.layer.cornerRadius = 12;
    searchBtn.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [searchBtn addTarget:nil action:@selector(startQuickSearch) forControlEvents:UIControlEventTouchUpInside];
    [g_logWindow addSubview:searchBtn];
    
    // Кнопка копирования
    UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    copyBtn.frame = CGRectMake(25 + (width - 45) / 2, 380, (width - 45) / 2, 42);
    [copyBtn setTitle:@"📋 КОПИ" forState:UIControlStateNormal];
    copyBtn.backgroundColor = [UIColor systemGreenColor];
    [copyBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    copyBtn.layer.cornerRadius = 12;
    copyBtn.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [copyBtn addTarget:nil action:@selector(copyLogs) forControlEvents:UIControlEventTouchUpInside];
    [g_logWindow addSubview:copyBtn];
    
    // Кнопка закрытия
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(width/2 - 50, 432, 100, 32);
    [closeBtn setTitle:@"ЗАКРЫТЬ" forState:UIControlStateNormal];
    closeBtn.backgroundColor = [UIColor systemRedColor];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeBtn.layer.cornerRadius = 8;
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [closeBtn addTarget:g_logWindow action:@selector(setHidden:) forControlEvents:UIControlEventTouchUpInside];
    [g_logWindow addSubview:closeBtn];
    
    [g_logWindow makeKeyAndVisible];
}

void startQuickSearch() {
    if (g_isSearching) {
        addLog(@"⚠️ Подожди, поиск уже идет...");
        return;
    }
    addLog(@"\n🔍 НАЧИНАЮ ПОИСК...");
    addLog(@"⏳ Жди 10-20 секунд");
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        quickSearch();
    });
}

void copyLogs() {
    if (g_logTextView && g_logTextView.text.length > 0) {
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        pasteboard.string = g_logTextView.text;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"✅" message:@"Скопировано!" preferredStyle:UIAlertControllerStyleAlert];
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
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [alert dismissViewControllerAnimated:YES completion:nil];
            });
        });
    }
}

// ===== ПЛАВАЮЩАЯ КНОПКА (В ПРАВОМ НИЖНЕМ УГЛУ) =====
@interface FloatButton : UIImageView
@property (nonatomic, copy) void (^actionBlock)(void);
@property (nonatomic, assign) CGPoint lastLocation;
@end

@implementation FloatButton

- (instancetype)init {
    CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
    CGFloat screenHeight = [UIScreen mainScreen].bounds.size.height;
    
    // ФИКСИРОВАННОЕ ПОЛОЖЕНИЕ — правый нижний угол
    self = [super initWithFrame:CGRectMake(screenWidth - 75, screenHeight - 95, 60, 60)];
    if (self) {
        self.backgroundColor = [UIColor systemBlueColor];
        self.layer.cornerRadius = 30;
        self.layer.borderWidth = 2;
        self.layer.borderColor = [UIColor whiteColor].CGColor;
        self.userInteractionEnabled = YES;
        
        UILabel *label = [[UILabel alloc] initWithFrame:self.bounds];
        label.text = @"🎯";
        label.textColor = [UIColor whiteColor];
        label.textAlignment = NSTextAlignmentCenter;
        label.font = [UIFont boldSystemFontOfSize:28];
        [self addSubview:label];
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragButton:)];
        [self addGestureRecognizer:pan];
        
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap)];
        [self addGestureRecognizer:tap];
    }
    return self;
}

- (void)dragButton:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self.superview];
    
    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.lastLocation = self.center;
    }
    
    CGPoint newCenter = CGPointMake(self.lastLocation.x + translation.x, self.lastLocation.y + translation.y);
    
    // ОГРАНИЧЕНИЯ — кнопка всегда в видимой зоне
    CGFloat half = 30;
    newCenter.x = MAX(half, MIN(self.superview.bounds.size.width - half, newCenter.x));
    newCenter.y = MAX(half + 60, MIN(self.superview.bounds.size.height - half - 60, newCenter.y));
    
    self.center = newCenter;
}

- (void)handleTap {
    if (self.actionBlock) self.actionBlock();
}

- (void)setAction:(void (^)(void))block {
    self.actionBlock = block;
}

@end

// ===== ПРОПУСКАЮЩЕЕ ОКНО =====
@interface PassthroughWindow : UIWindow
@property (nonatomic, weak) FloatButton *floatButton;
@end

@implementation PassthroughWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.floatButton && !self.floatButton.hidden) {
        CGPoint buttonPoint = [self convertPoint:point toView:self.floatButton];
        if ([self.floatButton pointInside:buttonPoint withEvent:event]) {
            return self.floatButton;
        }
    }
    return nil;
}

@end

// ===== ГЛАВНЫЙ UI =====
@interface AimbotUI : NSObject
@property (nonatomic, strong) PassthroughWindow *window;
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
    
    g_floatButton = [[FloatButton alloc] init];
    self.window.floatButton = g_floatButton;
    [self.window addSubview:g_floatButton];
    
    __weak typeof(self) weakSelf = self;
    [g_floatButton setAction:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) {
            g_logText = nil;
            createLogWindow();
        }
    }];
}

@end

// ===== ТОЧКА ВХОДА =====
static AimbotUI *g_ui = nil;

__attribute__((constructor))
static void init() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        g_ui = [[AimbotUI alloc] init];
        NSLog(@"[ESP] Твик загружен!");
    });
}
