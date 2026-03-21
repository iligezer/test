#import <UIKit/UIKit.h>
#import <mach/mach.h>

// ===== ГЛОБАЛЬНЫЕ =====
static UIWindow *win = nil;
static UITextView *logView = nil;
static NSMutableString *logText = nil;
static BOOL isSearching = NO;

void addLog(NSString *msg) {
    if (!logText) logText = [[NSMutableString alloc] init];
    [logText appendString:msg];
    [logText appendString:@"\n"];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (logView) logView.text = logText;
    });
}

void clearLog() {
    logText = nil;
    addLog(@"🗑 Лог очищен");
}

float safeReadFloat(uintptr_t addr) {
    if (addr == 0) return 0;
    @try {
        float val = 0;
        vm_read_overwrite(mach_task_self(), addr, 4, (vm_address_t)&val, NULL);
        return val;
    } @catch (NSException *e) {
        return 0;
    }
}

int safeReadInt(uintptr_t addr) {
    if (addr == 0) return 0;
    @try {
        int val = 0;
        vm_read_overwrite(mach_task_self(), addr, 4, (vm_address_t)&val, NULL);
        return val;
    } @catch (NSException *e) {
        return 0;
    }
}

// ===== ПОИСК ПО КООРДИНАТАМ =====
void searchByCoordinates() {
    if (isSearching) {
        addLog(@"⏳ Уже ищу");
        return;
    }
    isSearching = YES;
    addLog(@"🔍 ПОИСК ПО КООРДИНАТАМ");
    addLog(@"=================================");
    
    // Координаты из скрина: X=6.42 Y=1.82 Z=2.48
    float coords[][3] = {
        {6.42, 1.82, 2.48}
    };
    int coordCount = 1;
    int myID = 71068432;
    
    int foundCoordSets = 0;
    
    task_t task = mach_task_self();
    vm_address_t addr = 0;
    vm_size_t size = 0;
    struct vm_region_basic_info_64 info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object_name = MACH_PORT_NULL;
    
    uint8_t *buffer = malloc(0x1000);
    if (!buffer) {
        addLog(@"❌ Ошибка памяти");
        isSearching = NO;
        return;
    }
    
    addLog(@"📊 Сканирование...");
    
    for (int c = 0; c < coordCount; c++) {
        float targetX = coords[c][0];
        float targetY = coords[c][1];
        float targetZ = coords[c][2];
        
        addLog([NSString stringWithFormat:@"\n🔍 ИЩУ КООРДИНАТЫ: X=%.2f Y=%.2f Z=%.2f (погрешность ±5)", targetX, targetY, targetZ]);
        
        int foundInThisSet = 0;
        
        while (1) {
            kern_return_t kr = vm_region_64(task, &addr, &size, VM_REGION_BASIC_INFO_64,
                                             (vm_region_info_t)&info, &count, &object_name);
            if (kr != KERN_SUCCESS) break;
            
            if ((info.protection & VM_PROT_READ) && (info.protection & VM_PROT_WRITE) &&
                addr >= 0x100000000 && addr <= 0x300000000) {
                
                for (uintptr_t page = addr; page < addr + size; page += 0x1000) {
                    uintptr_t pageSize = (page + 0x1000 > addr + size) ? (addr + size - page) : 0x1000;
                    if (pageSize < 12) continue;
                    
                    vm_size_t read = 0;
                    kern_return_t kr2 = vm_read_overwrite(task, page, pageSize, (vm_address_t)buffer, &read);
                    if (kr2 != KERN_SUCCESS || read < 12) continue;
                    
                    for (uintptr_t offset = 0; offset + 12 <= pageSize; offset += 4) {
                        float x = *(float*)(buffer + offset);
                        float y = *(float*)(buffer + offset + 4);
                        float z = *(float*)(buffer + offset + 8);
                        
                        if (fabs(x - targetX) <= 5 && fabs(y - targetY) <= 5 && fabs(z - targetZ) <= 5) {
                            uintptr_t coordAddr = page + offset;
                            foundCoordSets++;
                            foundInThisSet++;
                            
                            addLog([NSString stringWithFormat:@"\n📍 НАЙДЕНЫ КООРДИНАТЫ #%d", foundCoordSets]);
                            addLog([NSString stringWithFormat:@"   Адрес X: 0x%lx", coordAddr]);
                            addLog([NSString stringWithFormat:@"   X=%.2f Y=%.2f Z=%.2f", x, y, z]);
                            
                            // Ищем ID вверх (3 ближайших)
                            addLog(@"   🔼 3 БЛИЖАЙШИХ ID ВВЕРХ:");
                            int foundUp = 0;
                            for (int up = 0x4; up <= 0x100 && foundUp < 3; up += 4) {
                                uintptr_t checkAddr = coordAddr - up;
                                if (checkAddr < 0x100000000) continue;
                                int val = safeReadInt(checkAddr);
                                if (val == myID) {
                                    foundUp++;
                                    addLog([NSString stringWithFormat:@"      [%d] Смещение -0x%02X: ID=0x%lx", foundUp, up, checkAddr]);
                                }
                            }
                            if (foundUp == 0) addLog(@"      ❌ ID не найден");
                            
                            // Ищем ID вниз (3 ближайших)
                            addLog(@"   🔽 3 БЛИЖАЙШИХ ID ВНИЗ:");
                            int foundDown = 0;
                            for (int down = 0x4; down <= 0x100 && foundDown < 3; down += 4) {
                                uintptr_t checkAddr = coordAddr + down;
                                int val = safeReadInt(checkAddr);
                                if (val == myID) {
                                    foundDown++;
                                    addLog([NSString stringWithFormat:@"      [%d] Смещение +0x%02X: ID=0x%lx", foundDown, down, checkAddr]);
                                }
                            }
                            if (foundDown == 0) addLog(@"      ❌ ID не найден");
                        }
                    }
                }
            }
            
            addr += size;
            if (addr > 0x300000000) break;
        }
        
        if (foundInThisSet == 0) {
            addLog(@"   ⚠️ Координаты не найдены");
        }
    }
    
    free(buffer);
    
    addLog([NSString stringWithFormat:@"\n✅ Всего найдено совпадений координат: %d", foundCoordSets]);
    addLog(@"✅ ГОТОВО");
    isSearching = NO;
}

// ===== КЛАСС-ОБРАБОТЧИК =====
@interface MenuHandler : NSObject
+ (void)onSearch;
+ (void)onClear;
+ (void)onCopy;
+ (void)onClose;
@end

@implementation MenuHandler
+ (void)onSearch {
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        searchByCoordinates();
    });
}
+ (void)onClear { clearLog(); }
+ (void)onCopy {
    if (logView && logView.text.length > 0) {
        UIPasteboard.generalPasteboard.string = logView.text;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"✅" message:@"Скопировано" preferredStyle:UIAlertControllerStyleAlert];
        UIWindow *k = nil;
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if ([s isKindOfClass:UIWindowScene.class]) {
                for (UIWindow *w in ((UIWindowScene *)s).windows) {
                    if (w.isKeyWindow) { k = w; break; }
                }
            }
            if (k) break;
        }
        [k.rootViewController presentViewController:alert animated:YES completion:nil];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [alert dismissViewControllerAnimated:YES completion:nil];
        });
    }
}
+ (void)onClose {
    if (win) {
        win.hidden = YES;
        win = nil;
    }
}
@end

// ===== МЕНЮ =====
void createMenu() {
    UIWindow *key = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:UIWindowScene.class]) {
            UIWindowScene *ws = (UIWindowScene *)s;
            for (UIWindow *w in ws.windows) {
                if (w.isKeyWindow) { key = w; break; }
            }
        }
        if (key) break;
    }
    if (!key) return;
    
    CGFloat w = 300, h = 420;
    CGFloat x = (key.bounds.size.width - w) / 2;
    CGFloat y = (key.bounds.size.height - h) / 2;
    
    win = [[UIWindow alloc] initWithFrame:CGRectMake(x, y, w, h)];
    win.windowLevel = UIWindowLevelAlert + 2;
    win.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
    win.layer.cornerRadius = 12;
    win.layer.borderWidth = 1;
    win.layer.borderColor = UIColor.systemBlueColor.CGColor;
    win.hidden = NO;
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 8, w, 28)];
    title.text = @"🎯 ПОИСК ПО КООРДИНАТАМ";
    title.textColor = UIColor.systemBlueColor;
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:14];
    [win addSubview:title];
    
    logView = [[UITextView alloc] initWithFrame:CGRectMake(8, 42, w-16, 270)];
    logView.backgroundColor = UIColor.blackColor;
    logView.textColor = UIColor.greenColor;
    logView.font = [UIFont fontWithName:@"Courier" size:10];
    logView.editable = NO;
    logView.layer.cornerRadius = 6;
    [win addSubview:logView];
    
    UIButton *searchBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    searchBtn.frame = CGRectMake(15, 325, (w-45)/2, 38);
    [searchBtn setTitle:@"🔍 НАЙТИ" forState:UIControlStateNormal];
    searchBtn.backgroundColor = UIColor.systemBlueColor;
    [searchBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    searchBtn.layer.cornerRadius = 8;
    [searchBtn addTarget:[MenuHandler class] action:@selector(onSearch) forControlEvents:UIControlEventTouchUpInside];
    [win addSubview:searchBtn];
    
    UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    copyBtn.frame = CGRectMake(25 + (w-45)/2, 325, (w-45)/2, 38);
    [copyBtn setTitle:@"📋 КОПИ" forState:UIControlStateNormal];
    copyBtn.backgroundColor = UIColor.systemGreenColor;
    [copyBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    copyBtn.layer.cornerRadius = 8;
    [copyBtn addTarget:[MenuHandler class] action:@selector(onCopy) forControlEvents:UIControlEventTouchUpInside];
    [win addSubview:copyBtn];
    
    UIButton *clearBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    clearBtn.frame = CGRectMake(15, 375, (w-45)/2, 38);
    [clearBtn setTitle:@"🗑 ОЧИСТИТЬ" forState:UIControlStateNormal];
    clearBtn.backgroundColor = UIColor.systemOrangeColor;
    [clearBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    clearBtn.layer.cornerRadius = 8;
    [clearBtn addTarget:[MenuHandler class] action:@selector(onClear) forControlEvents:UIControlEventTouchUpInside];
    [win addSubview:clearBtn];
    
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(25 + (w-45)/2, 375, (w-45)/2, 38);
    [closeBtn setTitle:@"❌ ЗАКРЫТЬ" forState:UIControlStateNormal];
    closeBtn.backgroundColor = UIColor.systemRedColor;
    [closeBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    closeBtn.layer.cornerRadius = 8;
    [closeBtn addTarget:[MenuHandler class] action:@selector(onClose) forControlEvents:UIControlEventTouchUpInside];
    [win addSubview:closeBtn];
    
    [win makeKeyAndVisible];
}

// ===== ПЛАВАЮЩАЯ КНОПКА =====
@interface FloatBtn : UIView
@property (nonatomic, copy) void (^onTap)(void);
@property (nonatomic, assign) CGPoint last;
@end

@implementation FloatBtn
- (instancetype)init {
    CGFloat sw = UIScreen.mainScreen.bounds.size.width;
    CGFloat sh = UIScreen.mainScreen.bounds.size.height;
    self = [super initWithFrame:CGRectMake(sw-65, sh-85, 50, 50)];
    if (self) {
        self.backgroundColor = UIColor.systemBlueColor;
        self.layer.cornerRadius = 25;
        self.layer.borderWidth = 2;
        self.layer.borderColor = UIColor.whiteColor.CGColor;
        self.userInteractionEnabled = YES;
        
        UILabel *l = [[UILabel alloc] initWithFrame:self.bounds];
        l.text = @"🎯";
        l.textColor = UIColor.whiteColor;
        l.textAlignment = NSTextAlignmentCenter;
        l.font = [UIFont boldSystemFontOfSize:24];
        [self addSubview:l];
        
        UIPanGestureRecognizer *p = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
        [self addGestureRecognizer:p];
        UITapGestureRecognizer *t = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tap)];
        [self addGestureRecognizer:t];
    }
    return self;
}
- (void)drag:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.superview];
    if (g.state == UIGestureRecognizerStateBegan) self.last = self.center;
    CGPoint c = CGPointMake(self.last.x + t.x, self.last.y + t.y);
    CGFloat h = 25;
    c.x = MAX(h, MIN(self.superview.bounds.size.width - h, c.x));
    c.y = MAX(h+50, MIN(self.superview.bounds.size.height - h-50, c.y));
    self.center = c;
}
- (void)tap { if (self.onTap) self.onTap(); }
@end

@interface OverlayWin : UIWindow @property (nonatomic, weak) FloatBtn *btn; @end
@implementation OverlayWin
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    if (self.btn && !self.btn.hidden && CGRectContainsPoint(self.btn.frame, p)) return self.btn;
    return nil;
}
@end

@interface App : NSObject @property (nonatomic, strong) OverlayWin *w; @end
@implementation App
- (instancetype)init {
    self = [super init];
    if (self) {
        self.w = [[OverlayWin alloc] initWithFrame:UIScreen.mainScreen.bounds];
        self.w.windowLevel = UIWindowLevelAlert + 1;
        self.w.backgroundColor = UIColor.clearColor;
        self.w.hidden = NO;
        
        FloatBtn *b = [[FloatBtn alloc] init];
        self.w.btn = b;
        [self.w addSubview:b];
        
        __weak typeof(self) weak = self;
        b.onTap = ^{
            logText = nil;
            createMenu();
        };
    }
    return self;
}
@end

static App *app = nil;

__attribute__((constructor))
static void init() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        app = [[App alloc] init];
        NSLog(@"[ESP] Ready");
    });
}
