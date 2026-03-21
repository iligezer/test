#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>

// ===== ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ =====
static UIWindow *g_logWindow = nil;
static UITextView *g_logTextView = nil;
static NSMutableString *g_logText = nil;
static uintptr_t g_foundRoomController = 0;
static uintptr_t g_foundPlayersArray = 0;
static int g_playerCount = 0;

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

// ===== ДОБАВЛЕНИЕ ЛОГА =====
void addLog(NSString *format, ...) {
    if (!g_logText) {
        g_logText = [[NSMutableString alloc] init];
    }
    
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    NSLog(@"[ESP] %@", message);
    [g_logText appendString:message];
    [g_logText appendString:@"\n"];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        g_logTextView.text = g_logText;
        if (g_logTextView.text.length > 0) {
            NSRange bottom = NSMakeRange(g_logTextView.text.length - 1, 1);
            [g_logTextView scrollRangeToVisible:bottom];
        }
    });
}

// ===== АВТОМАТИЧЕСКИЙ ПОИСК ROOMCONTROLLER =====
void autoFindRoomController() {
    addLog(@"\n🔍 АВТОПОИСК ROOMCONTROLLER");
    addLog(@"=================================");
    
    uintptr_t base = getBaseAddress();
    if (base == 0) {
        addLog(@"❌ UnityFramework не найден");
        return;
    }
    
    // Сканируем диапазон памяти
    uintptr_t startAddr = 0x100000000;
    uintptr_t endAddr = 0x200000000;
    int found = 0;
    
    addLog(@"📊 Сканирую диапазон: 0x%lx - 0x%lx", startAddr, endAddr);
    
    for (uintptr_t addr = startAddr; addr < endAddr && found < 10; addr += 8) {
        uintptr_t value = 0;
        if (safeRead(addr, &value, sizeof(uintptr_t)) == sizeof(uintptr_t)) {
            // Проверяем, похоже ли на указатель на QuarkRoomPlayer
            if (value >= startAddr && value < endAddr) {
                // Проверяем Team по адресу +0x34
                int team = 0;
                if (safeRead(value + 0x34, &team, sizeof(int)) == sizeof(int)) {
                    if (team == 0 || team == 1) {
                        // Проверяем ID по адресу +0x10
                        int id = 0;
                        if (safeRead(value + 0x10, &id, sizeof(int)) == sizeof(int)) {
                            if (id == 71068432 || (id > 1000000 && id < 100000000)) {
                                addLog(@"✅ Найден QuarkRoomPlayer: 0x%lx (ID: %d, Team: %d)", value, id, team);
                                
                                // Ищем указатель на этот адрес (RoomController)
                                for (uintptr_t ptrAddr = startAddr; ptrAddr < endAddr; ptrAddr += 8) {
                                    uintptr_t ptr = 0;
                                    if (safeRead(ptrAddr, &ptr, sizeof(uintptr_t)) == sizeof(uintptr_t)) {
                                        if (ptr == value) {
                                            addLog(@"   → Указатель найден: 0x%lx", ptrAddr);
                                            
                                            // Проверяем, есть ли массив по +0x140
                                            uintptr_t playersArray = 0;
                                            if (safeRead(ptrAddr + 0x140, &playersArray, sizeof(uintptr_t)) == sizeof(uintptr_t)) {
                                                if (playersArray > startAddr && playersArray < endAddr) {
                                                    addLog(@"   → Массив игроков по +0x140: 0x%lx", playersArray);
                                                    g_foundRoomController = ptrAddr;
                                                    g_foundPlayersArray = playersArray;
                                                    found++;
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        if (found > 0) break;
    }
    
    if (g_foundRoomController) {
        addLog(@"\n✅ ROOMCONTROLLER НАЙДЕН: 0x%lx", g_foundRoomController);
        addLog(@"✅ МАССИВ ИГРОКОВ: 0x%lx", g_foundPlayersArray);
        
        // Получаем количество игроков
        int playerCount = 0;
        for (int i = 0; i < 20; i++) {
            uintptr_t player = 0;
            if (safeRead(g_foundPlayersArray + i * 8, &player, sizeof(uintptr_t)) == sizeof(uintptr_t)) {
                if (player == 0) break;
                playerCount++;
            }
        }
        g_playerCount = playerCount;
        addLog(@"✅ ИГРОКОВ В МАТЧЕ: %d", playerCount);
        
        // Выводим всех игроков
        addLog(@"\n📋 СПИСОК ИГРОКОВ:");
        for (int i = 0; i < playerCount; i++) {
            uintptr_t player = 0;
            safeRead(g_foundPlayersArray + i * 8, &player, sizeof(uintptr_t));
            
            int id = 0;
            int team = 0;
            int isWasted = 0;
            safeRead(player + 0x10, &id, sizeof(int));
            safeRead(player + 0x34, &team, sizeof(int));
            safeRead(player + 0x7A, &isWasted, sizeof(char));
            
            addLog(@"   [%d] ID: %d, Team: %d, Dead: %d, Addr: 0x%lx", i, id, team, isWasted, player);
        }
        
    } else {
        addLog(@"❌ ROOMCONTROLLER НЕ НАЙДЕН");
        addLog(@"💡 Попробуй найти вручную через iGG");
    }
}

// ===== СОЗДАНИЕ ОКНА ЛОГА =====
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
    
    CGFloat width = keyWindow.frame.size.width - 40;
    CGFloat height = 450;
    CGFloat x = 20;
    CGFloat y = (keyWindow.frame.size.height - height) / 2; // Центрируем по вертикали
    
    g_logWindow = [[UIWindow alloc] initWithFrame:CGRectMake(x, y, width, height)];
    g_logWindow.windowLevel = UIWindowLevelAlert + 2;
    g_logWindow.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.98];
    g_logWindow.layer.cornerRadius = 20;
    g_logWindow.layer.borderWidth = 2;
    g_logWindow.layer.borderColor = [UIColor systemBlueColor].CGColor;
    g_logWindow.hidden = NO;
    
    // Заголовок
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 15, width, 30)];
    title.text = @"🎯 ESP SCANNER";
    title.textColor = [UIColor systemBlueColor];
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:18];
    [g_logWindow addSubview:title];
    
    // Текстовое поле
    g_logTextView = [[UITextView alloc] initWithFrame:CGRectMake(10, 55, width - 20, 310)];
    g_logTextView.backgroundColor = [UIColor blackColor];
    g_logTextView.textColor = [UIColor greenColor];
    g_logTextView.font = [UIFont fontWithName:@"Courier" size:11];
    g_logTextView.editable = NO;
    g_logTextView.selectable = YES;
    g_logTextView.layer.cornerRadius = 10;
    [g_logWindow addSubview:g_logTextView];
    
    // Кнопка поиска
    UIButton *searchBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    searchBtn.frame = CGRectMake(15, 380, (width - 40) / 2, 45);
    [searchBtn setTitle:@"🔍 НАЙТИ АДРЕСА" forState:UIControlStateNormal];
    searchBtn.backgroundColor = [UIColor systemBlueColor];
    [searchBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    searchBtn.layer.cornerRadius = 12;
    searchBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [searchBtn addTarget:nil action:@selector(startAutoSearch) forControlEvents:UIControlEventTouchUpInside];
    [g_logWindow addSubview:searchBtn];
    
    // Кнопка копирования
    UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    copyBtn.frame = CGRectMake(30 + (width - 40) / 2, 380, (width - 40) / 2, 45);
    [copyBtn setTitle:@"📋 КОПИРОВАТЬ" forState:UIControlStateNormal];
    copyBtn.backgroundColor = [UIColor systemGreenColor];
    [copyBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    copyBtn.layer.cornerRadius = 12;
    copyBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [copyBtn addTarget:nil action:@selector(copyLog) forControlEvents:UIControlEventTouchUpInside];
    [g_logWindow addSubview:copyBtn];
    
    // Кнопка закрытия
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(width/2 - 60, 440, 120, 35);
    [closeBtn setTitle:@"❌ ЗАКРЫТЬ" forState:UIControlStateNormal];
    closeBtn.backgroundColor = [UIColor systemRedColor];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeBtn.layer.cornerRadius = 10;
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [closeBtn addTarget:g_logWindow action:@selector(setHidden:) forControlEvents:UIControlEventTouchUpInside];
    [g_logWindow addSubview:closeBtn];
    
    [g_logWindow makeKeyAndVisible];
}

void startAutoSearch() {
    addLog(@"\n✅ СКАНЕР ЗАГРУЖЕН");
    addLog(@"🔍 Нажми кнопку -> НАЙТИ АДРЕСА\n");
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        autoFindRoomController();
    });
}

void copyLog() {
    if (g_logTextView) {
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
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [alert dismissViewControllerAnimated:YES completion:nil];
            });
        });
    }
}

// ===== ПЛАВАЮЩАЯ КНОПКА =====
@interface FloatButton : UIImageView
@property (nonatomic, copy) void (^actionBlock)(void);
@property (nonatomic, assign) CGPoint lastLocation;
@end

@implementation FloatButton

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(20, 120, 65, 65)];
    if (self) {
        self.backgroundColor = [UIColor systemBlueColor];
        self.layer.cornerRadius = 32.5;
        self.layer.borderWidth = 3;
        self.layer.borderColor = [UIColor whiteColor].CGColor;
        self.userInteractionEnabled = YES;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOffset = CGSizeMake(0, 4);
        self.layer.shadowOpacity = 0.5;
        self.layer.shadowRadius = 6;
        
        UILabel *label = [[UILabel alloc] initWithFrame:self.bounds];
        label.text = @"🎯";
        label.textColor = [UIColor whiteColor];
        label.textAlignment = NSTextAlignmentCenter;
        label.font = [UIFont boldSystemFontOfSize:32];
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
    
    CGFloat half = 32.5;
    newCenter.x = MAX(half, MIN(self.superview.bounds.size.width - half, newCenter.x));
    newCenter.y = MAX(half + 50, MIN(self.superview.bounds.size.height - half - 50, newCenter.y));
    
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
@property (nonatomic, strong) FloatButton *floatButton;
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
    
    self.floatButton = [[FloatButton alloc] init];
    self.window.floatButton = self.floatButton;
    [self.window addSubview:self.floatButton];
    
    __weak typeof(self) weakSelf = self;
    [self.floatButton setAction:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) {
            // Очищаем старые логи
            g_logText = nil;
            // Создаем окно
            createLogWindow();
            // Запускаем авто-поиск
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                startAutoSearch();
            });
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
