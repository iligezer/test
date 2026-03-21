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
        if (g_logTextView) {
            g_logTextView.text = g_logText;
            if (g_logTextView.text.length > 0) {
                NSRange bottom = NSMakeRange(g_logTextView.text.length - 1, 1);
                [g_logTextView scrollRangeToVisible:bottom];
            }
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
    
    uintptr_t startAddr = 0x100000000;
    uintptr_t endAddr = 0x200000000;
    int foundControllers = 0;
    
    addLog(@"📊 Сканирую диапазон: 0x%lx - 0x%lx", startAddr, endAddr);
    addLog(@"⏳ Ищу QuarkRoomPlayer...");
    
    // Сначала находим ВСЕ структуры QuarkRoomPlayer
    NSMutableArray *players = [NSMutableArray array];
    
    for (uintptr_t addr = startAddr; addr < endAddr; addr += 16) {
        int team = 0;
        if (safeRead(addr + 0x34, &team, sizeof(int)) == sizeof(int)) {
            if (team == 0 || team == 1) {
                int id = 0;
                if (safeRead(addr + 0x10, &id, sizeof(int)) == sizeof(int)) {
                    if (id > 1000000 && id < 200000000) {
                        [players addObject:@(addr)];
                        addLog(@"   Найден QuarkRoomPlayer: 0x%lx (ID: %d, Team: %d)", addr, id, team);
                    }
                }
            }
        }
    }
    
    addLog(@"\n📊 Найдено QuarkRoomPlayer: %lu", (unsigned long)players.count);
    
    if (players.count == 0) {
        addLog(@"❌ Не найдено ни одного QuarkRoomPlayer");
        return;
    }
    
    // Берем первый адрес для поиска RoomController
    uintptr_t firstPlayer = [players[0] unsignedLongValue];
    addLog(@"\n🔍 Ищу указатели на 0x%lx", firstPlayer);
    
    // Ищем указатели на первого игрока
    for (uintptr_t addr = startAddr; addr < endAddr; addr += 8) {
        uintptr_t ptr = 0;
        if (safeRead(addr, &ptr, sizeof(uintptr_t)) == sizeof(uintptr_t)) {
            if (ptr == firstPlayer) {
                addLog(@"   → Указатель найден: 0x%lx", addr);
                
                // Проверяем, есть ли массив по +0x140
                uintptr_t arrayPtr = 0;
                if (safeRead(addr + 0x140, &arrayPtr, sizeof(uintptr_t)) == sizeof(uintptr_t)) {
                    if (arrayPtr >= startAddr && arrayPtr < endAddr) {
                        addLog(@"   → Массив игроков по +0x140: 0x%lx", arrayPtr);
                        
                        // Проверяем содержимое массива
                        int count = 0;
                        for (int i = 0; i < 20; i++) {
                            uintptr_t player = 0;
                            if (safeRead(arrayPtr + i * 8, &player, sizeof(uintptr_t)) == sizeof(uintptr_t)) {
                                if (player == 0) break;
                                if ([players containsObject:@(player)]) {
                                    count++;
                                }
                            }
                        }
                        
                        if (count > 0) {
                            addLog(@"   ✅ В массиве %d игроков", count);
                            g_foundRoomController = addr;
                            g_foundPlayersArray = arrayPtr;
                            foundControllers++;
                            break;
                        }
                    }
                }
            }
        }
    }
    
    if (foundControllers > 0) {
        addLog(@"\n✅ ROOMCONTROLLER НАЙДЕН: 0x%lx", g_foundRoomController);
        addLog(@"✅ МАССИВ ИГРОКОВ: 0x%lx", g_foundPlayersArray);
        
        // Получаем всех игроков из массива
        int playerCount = 0;
        addLog(@"\n📋 СПИСОК ИГРОКОВ:");
        for (int i = 0; i < 30; i++) {
            uintptr_t player = 0;
            if (safeRead(g_foundPlayersArray + i * 8, &player, sizeof(uintptr_t)) == sizeof(uintptr_t)) {
                if (player == 0) break;
                
                int id = 0;
                int team = 0;
                char isWasted = 0;
                safeRead(player + 0x10, &id, sizeof(int));
                safeRead(player + 0x34, &team, sizeof(int));
                safeRead(player + 0x7A, &isWasted, sizeof(char));
                
                addLog(@"   [%d] ID: %d, Team: %d, Dead: %d, Addr: 0x%lx", i, id, team, isWasted, player);
                playerCount++;
            }
        }
        addLog(@"\n✅ ВСЕГО ИГРОКОВ: %d", playerCount);
        
    } else {
        addLog(@"❌ ROOMCONTROLLER НЕ НАЙДЕН");
        addLog(@"💡 Попробуй найти вручную через iGG");
    }
}

void startAutoSearch() {
    addLog(@"🔍 ИЩУ...");
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        autoFindRoomController();
    });
}

void copyLog() {
    if (g_logTextView) {
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        pasteboard.string = g_logTextView.text;
    }
}

// ===== СОЗДАНИЕ МАЛЕНЬКОГО ОКНА ЛОГА =====
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
    
    // Маленькое окно 280x350
    CGFloat width = 280;
    CGFloat height = 350;
    CGFloat x = (keyWindow.frame.size.width - width) / 2;
    CGFloat y = (keyWindow.frame.size.height - height) / 2;
    
    g_logWindow = [[UIWindow alloc] initWithFrame:CGRectMake(x, y, width, height)];
    g_logWindow.windowLevel = UIWindowLevelAlert + 2;
    g_logWindow.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
    g_logWindow.layer.cornerRadius = 15;
    g_logWindow.layer.borderWidth = 1;
    g_logWindow.layer.borderColor = [UIColor systemBlueColor].CGColor;
    g_logWindow.hidden = NO;
    
    // Заголовок
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, width, 25)];
    title.text = @"🎯 SCAN";
    title.textColor = [UIColor systemBlueColor];
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:16];
    [g_logWindow addSubview:title];
    
    // Текстовое поле
    g_logTextView = [[UITextView alloc] initWithFrame:CGRectMake(10, 45, width - 20, 230)];
    g_logTextView.backgroundColor = [UIColor blackColor];
    g_logTextView.textColor = [UIColor greenColor];
    g_logTextView.font = [UIFont fontWithName:@"Courier" size:10];
    g_logTextView.editable = NO;
    g_logTextView.selectable = YES;
    g_logTextView.layer.cornerRadius = 8;
    [g_logWindow addSubview:g_logTextView];
    
    // Кнопка поиска
    UIButton *searchBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    searchBtn.frame = CGRectMake(15, 290, width - 30, 40);
    [searchBtn setTitle:@"🔍 НАЙТИ" forState:UIControlStateNormal];
    searchBtn.backgroundColor = [UIColor systemBlueColor];
    [searchBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    searchBtn.layer.cornerRadius = 10;
    searchBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [searchBtn addTarget:nil action:@selector(startAutoSearch) forControlEvents:UIControlEventTouchUpInside];
    [g_logWindow addSubview:searchBtn];
    
    // Кнопка копирования
    UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    copyBtn.frame = CGRectMake(15, 340, width - 30, 35);
    [copyBtn setTitle:@"📋 КОПИРОВАТЬ" forState:UIControlStateNormal];
    copyBtn.backgroundColor = [UIColor systemGreenColor];
    [copyBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    copyBtn.layer.cornerRadius = 10;
    copyBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [copyBtn addTarget:nil action:@selector(copyLog) forControlEvents:UIControlEventTouchUpInside];
    [g_logWindow addSubview:copyBtn];
    
    // Кнопка закрытия
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(width - 35, 5, 30, 30);
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [closeBtn addTarget:g_logWindow action:@selector(setHidden:) forControlEvents:UIControlEventTouchUpInside];
    [g_logWindow addSubview:closeBtn];
    
    [g_logWindow makeKeyAndVisible];
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
            g_logText = nil;
            createLogWindow();
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
