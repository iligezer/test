#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>

// ===== ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ =====
static UIWindow *g_logWindow = nil;
static UITextView *g_logTextView = nil;
static NSMutableString *g_logText = nil;
static BOOL g_isSearching = NO;

// ===== РАБОТА С ПАМЯТЬЮ =====
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

// ===== ПОИСК ИГРОКОВ В ПАМЯТИ =====
void findPlayersAndRoomController() {
    if (g_isSearching) {
        addLog(@"⚠️ Поиск уже идет...");
        return;
    }
    g_isSearching = YES;
    
    addLog(@"\n🔍 ПОИСК ИГРОКОВ В ПАМЯТИ");
    addLog(@"=========================");
    
    uintptr_t startAddr = 0x100000000;
    uintptr_t endAddr = 0x180000000;
    uintptr_t players[50] = {0};
    int playerCount = 0;
    
    addLog(@"📊 Сканирую память...");
    
    // Ищем всех игроков по паттерну (ID и Team)
    for (uintptr_t addr = startAddr; addr < endAddr && playerCount < 30; addr += 0x1000) {
        for (int offset = 0; offset < 0x1000 && playerCount < 30; offset += 16) {
            uintptr_t ptr = 0;
            if (safeRead(addr + offset, &ptr, 8) != 8) continue;
            if (ptr < startAddr || ptr > endAddr) continue;
            
            int team = 0, id = 0;
            if (safeRead(ptr + 0x34, &team, 4) == 4 &&
                safeRead(ptr + 0x10, &id, 4) == 4) {
                if ((team == 0 || team == 1) && id > 1000000 && id < 200000000) {
                    // Проверяем уникальность
                    BOOL exists = NO;
                    for (int i = 0; i < playerCount; i++) {
                        if (players[i] == ptr) { exists = YES; break; }
                    }
                    if (!exists) {
                        players[playerCount++] = ptr;
                        addLog(@"   🎮 Игрок %d: 0x%lx (ID: %d, Team: %d)", playerCount, ptr, id, team);
                    }
                }
            }
        }
    }
    
    addLog(@"\n📊 Найдено игроков: %d", playerCount);
    
    if (playerCount < 2) {
        addLog(@"❌ Найдено мало игроков. Ты в матче?");
        g_isSearching = NO;
        return;
    }
    
    // Ищем RoomController по указателям на игроков
    addLog(@"\n🔍 Ищу RoomController...");
    
    for (int i = 0; i < playerCount && i < 5; i++) {
        uintptr_t target = players[i];
        addLog(@"\n📌 Проверяю игрока 0x%lx", target);
        
        for (uintptr_t addr = startAddr; addr < startAddr + 0x2000000; addr += 8) {
            uintptr_t ptr = 0;
            if (safeRead(addr, &ptr, 8) != 8) continue;
            if (ptr == target) {
                addLog(@"   🔗 Указатель найден: 0x%lx", addr);
                
                // Проверяем массив по +0x140
                uintptr_t arrayPtr = 0;
                if (safeRead(addr + 0x140, &arrayPtr, 8) == 8 && arrayPtr > startAddr) {
                    addLog(@"   📦 Массив по +0x140: 0x%lx", arrayPtr);
                    
                    // Считаем игроков в массиве
                    int count = 0;
                    for (int j = 0; j < 20; j++) {
                        uintptr_t p = 0;
                        if (safeRead(arrayPtr + j * 8, &p, 8) == 8 && p != 0) count++;
                        else break;
                    }
                    
                    if (count >= playerCount - 2) {
                        addLog(@"\n🎯 ROOMCONTROLLER НАЙДЕН: 0x%lx", addr);
                        addLog(@"🎯 МАССИВ ИГРОКОВ: 0x%lx", arrayPtr);
                        addLog(@"🎯 КОЛИЧЕСТВО: %d", count);
                        
                        addLog(@"\n📋 ВСЕ ИГРОКИ В МАССИВЕ:");
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
    }
    
    addLog(@"\n❌ RoomController не найден");
    addLog(@"💡 Убедись, что ты в активном матче");
    g_isSearching = NO;
}

// ===== СОЗДАНИЕ ОКНА (МАЛЕНЬКОЕ) =====
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
    
    // МАЛЕНЬКОЕ ОКНО
    CGFloat width = 300;
    CGFloat height = 380;
    CGFloat x = (keyWindow.frame.size.width - width) / 2;
    CGFloat y = (keyWindow.frame.size.height - height) / 2;
    
    g_logWindow = [[UIWindow alloc] initWithFrame:CGRectMake(x, y, width, height)];
    g_logWindow.windowLevel = UIWindowLevelAlert + 2;
    g_logWindow.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.98];
    g_logWindow.layer.cornerRadius = 15;
    g_logWindow.layer.borderWidth = 2;
    g_logWindow.layer.borderColor = [UIColor systemBlueColor].CGColor;
    g_logWindow.hidden = NO;
    
    // Заголовок
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 8, width, 28)];
    title.text = @"🎯 ESP";
    title.textColor = [UIColor systemBlueColor];
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:16];
    [g_logWindow addSubview:title];
    
    // Текст
    g_logTextView = [[UITextView alloc] initWithFrame:CGRectMake(8, 40, width - 16, 260)];
    g_logTextView.backgroundColor = [UIColor blackColor];
    g_logTextView.textColor = [UIColor greenColor];
    g_logTextView.font = [UIFont fontWithName:@"Courier" size:10];
    g_logTextView.editable = NO;
    g_logTextView.selectable = YES;
    g_logTextView.layer.cornerRadius = 8;
    [g_logWindow addSubview:g_logTextView];
    
    // Кнопка поиска
    UIButton *searchBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    searchBtn.frame = CGRectMake(12, 310, (width - 35) / 2, 36);
    [searchBtn setTitle:@"🔍 НАЙТИ" forState:UIControlStateNormal];
    searchBtn.backgroundColor = [UIColor systemBlueColor];
    [searchBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    searchBtn.layer.cornerRadius = 8;
    searchBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [searchBtn addTarget:nil action:@selector(startSearch) forControlEvents:UIControlEventTouchUpInside];
    [g_logWindow addSubview:searchBtn];
    
    // Кнопка копирования
    UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    copyBtn.frame = CGRectMake(20 + (width - 35) / 2, 310, (width - 35) / 2, 36);
    [copyBtn setTitle:@"📋 КОПИ" forState:UIControlStateNormal];
    copyBtn.backgroundColor = [UIColor systemGreenColor];
    [copyBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    copyBtn.layer.cornerRadius = 8;
    copyBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [copyBtn addTarget:nil action:@selector(copyLog) forControlEvents:UIControlEventTouchUpInside];
    [g_logWindow addSubview:copyBtn];
    
    // Кнопка закрытия
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(width/2 - 45, 352, 90, 28);
    [closeBtn setTitle:@"ЗАКРЫТЬ" forState:UIControlStateNormal];
    closeBtn.backgroundColor = [UIColor systemRedColor];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeBtn.layer.cornerRadius = 6;
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [closeBtn addTarget:g_logWindow action:@selector(setHidden:) forControlEvents:UIControlEventTouchUpInside];
    [g_logWindow addSubview:closeBtn];
    
    [g_logWindow makeKeyAndVisible];
}

void startSearch() {
    if (g_isSearching) {
        addLog(@"⏳ Жди...");
        return;
    }
    addLog(@"\n🔍 СТАРТ");
    addLog(@"⏳ 10-15 сек");
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        findPlayersAndRoomController();
    });
}

void copyLog() {
    if (g_logTextView && g_logTextView.text.length > 0) {
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        pasteboard.string = g_logTextView.text;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"✅" message:@"Скопировано" preferredStyle:UIAlertControllerStyleAlert];
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
    CGFloat w = [UIScreen mainScreen].bounds.size.width;
    CGFloat h = [UIScreen mainScreen].bounds.size.height;
    
    self = [super initWithFrame:CGRectMake(w - 70, h - 90, 55, 55)];
    if (self) {
        self.backgroundColor = [UIColor systemBlueColor];
        self.layer.cornerRadius = 27.5;
        self.layer.borderWidth = 2;
        self.layer.borderColor = [UIColor whiteColor].CGColor;
        self.userInteractionEnabled = YES;
        
        UILabel *label = [[UILabel alloc] initWithFrame:self.bounds];
        label.text = @"🎯";
        label.textColor = [UIColor whiteColor];
        label.textAlignment = NSTextAlignmentCenter;
        label.font = [UIFont boldSystemFontOfSize:26];
        [self addSubview:label];
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
        [self addGestureRecognizer:pan];
        
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tap)];
        [self addGestureRecognizer:tap];
    }
    return self;
}

- (void)drag:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.superview];
    if (g.state == UIGestureRecognizerStateBegan) self.lastLocation = self.center;
    CGPoint newCenter = CGPointMake(self.lastLocation.x + t.x, self.lastLocation.y + t.y);
    CGFloat r = 27.5;
    newCenter.x = MAX(r, MIN(self.superview.bounds.size.width - r, newCenter.x));
    newCenter.y = MAX(r + 60, MIN(self.superview.bounds.size.height - r - 60, newCenter.y));
    self.center = newCenter;
}

- (void)tap { if (self.actionBlock) self.actionBlock(); }
- (void)setAction:(void (^)(void))block { self.actionBlock = block; }

@end

// ===== ОКНО =====
@interface PassthroughWindow : UIWindow
@property (nonatomic, weak) FloatButton *btn;
@end

@implementation PassthroughWindow
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    if (self.btn && !self.btn.hidden) {
        CGPoint bp = [self convertPoint:p toView:self.btn];
        if ([self.btn pointInside:bp withEvent:e]) return self.btn;
    }
    return nil;
}
@end

// ===== MAIN =====
@interface App : NSObject
@property (nonatomic, strong) PassthroughWindow *win;
@end

@implementation App
- (instancetype)init {
    self = [super init];
    if (self) {
        self.win = [[PassthroughWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        self.win.windowLevel = UIWindowLevelAlert + 1;
        self.win.backgroundColor = [UIColor clearColor];
        self.win.hidden = NO;
        
        FloatButton *btn = [[FloatButton alloc] init];
        self.win.btn = btn;
        [self.win addSubview:btn];
        
        __weak typeof(self) weakSelf = self;
        [btn setAction:^{
            g_logText = nil;
            createLogWindow();
        }];
    }
    return self;
}
@end

static App *g_app = nil;

__attribute__((constructor))
static void init() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        g_app = [[App alloc] init];
    });
}
