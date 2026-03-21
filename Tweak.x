#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>

// ===== ГЛОБАЛЬНЫЕ =====
static UIWindow *win = nil;
static UITextView *logView = nil;
static NSMutableString *logText = nil;
static BOOL isSearching = NO;

// ===== БЕЗОПАСНОЕ ЧТЕНИЕ =====
uintptr_t readPtr(uintptr_t addr) {
    uintptr_t val = 0;
    vm_read_overwrite(mach_task_self(), addr, 8, (vm_address_t)&val, NULL);
    return val;
}

int readInt(uintptr_t addr) {
    int val = 0;
    vm_read_overwrite(mach_task_self(), addr, 4, (vm_address_t)&val, NULL);
    return val;
}

void addLog(NSString *msg) {
    if (!logText) logText = [[NSMutableString alloc] init];
    [logText appendString:msg];
    [logText appendString:@"\n"];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (logView) logView.text = logText;
    });
}

// ===== ПОИСК ПО ID =====
void searchByIDs() {
    if (isSearching) { addLog(@"⏳ Уже ищу"); return; }
    isSearching = YES;
    addLog(@"🔍 ПОИСК ПО ID");
    addLog(@"=================================");
    
    uintptr_t start = 0x100000000;
    uintptr_t end = 0x300000000;
    
    int myID = 71068432;
    int enemyID = 55471766;
    
    int myCount = 0;
    int enemyCount = 0;
    
    addLog([NSString stringWithFormat:@"\n📋 ИЩУ ID %d (твой)...", myID]);
    for (uintptr_t addr = start; addr < end; addr += 4) {
        int val = readInt(addr);
        if (val == myID) {
            myCount++;
            uintptr_t structStart = addr - 0x10;
            int team = readInt(structStart + 0x34);
            int isWasted = readInt(structStart + 0x7A);
            addLog([NSString stringWithFormat:@"   [%d] 0x%lx Team:%d Dead:%d", myCount, structStart, team, isWasted]);
            if (myCount >= 30) break;
        }
    }
    addLog([NSString stringWithFormat:@"✅ Найдено твоих: %d", myCount]);
    
    addLog([NSString stringWithFormat:@"\n📋 ИЩУ ID %d (враг)...", enemyID]);
    for (uintptr_t addr = start; addr < end; addr += 4) {
        int val = readInt(addr);
        if (val == enemyID) {
            enemyCount++;
            uintptr_t structStart = addr - 0x10;
            int team = readInt(structStart + 0x34);
            int isWasted = readInt(structStart + 0x7A);
            addLog([NSString stringWithFormat:@"   [%d] 0x%lx Team:%d Dead:%d", enemyCount, structStart, team, isWasted]);
            if (enemyCount >= 30) break;
        }
    }
    addLog([NSString stringWithFormat:@"✅ Найдено врагов: %d", enemyCount]);
    
    addLog(@"\n✅ ГОТОВО");
    isSearching = NO;
}

// ===== КЛАСС-ОБРАБОТЧИК КНОПОК =====
@interface MenuHandler : NSObject
+ (void)onSearch;
+ (void)onCopy;
+ (void)onClose;
@end

@implementation MenuHandler
+ (void)onSearch {
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        searchByIDs();
    });
}
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

// ===== СОЗДАНИЕ МЕНЮ =====
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
    
    CGFloat w = 280, h = 360;
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
    title.text = @"🎯 ID SCANNER";
    title.textColor = UIColor.systemBlueColor;
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:16];
    [win addSubview:title];
    
    logView = [[UITextView alloc] initWithFrame:CGRectMake(8, 42, w-16, 230)];
    logView.backgroundColor = UIColor.blackColor;
    logView.textColor = UIColor.greenColor;
    logView.font = [UIFont fontWithName:@"Courier" size:11];
    logView.editable = NO;
    logView.layer.cornerRadius = 6;
    [win addSubview:logView];
    
    UIButton *searchBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    searchBtn.frame = CGRectMake(15, 282, (w-45)/2, 38);
    [searchBtn setTitle:@"🔍 НАЙТИ" forState:UIControlStateNormal];
    searchBtn.backgroundColor = UIColor.systemBlueColor;
    [searchBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    searchBtn.layer.cornerRadius = 8;
    [searchBtn addTarget:[MenuHandler class] action:@selector(onSearch) forControlEvents:UIControlEventTouchUpInside];
    [win addSubview:searchBtn];
    
    UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    copyBtn.frame = CGRectMake(25 + (w-45)/2, 282, (w-45)/2, 38);
    [copyBtn setTitle:@"📋 КОПИ" forState:UIControlStateNormal];
    copyBtn.backgroundColor = UIColor.systemGreenColor;
    [copyBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    copyBtn.layer.cornerRadius = 8;
    [copyBtn addTarget:[MenuHandler class] action:@selector(onCopy) forControlEvents:UIControlEventTouchUpInside];
    [win addSubview:copyBtn];
    
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(w/2-40, 330, 80, 28);
    [closeBtn setTitle:@"ЗАКРЫТЬ" forState:UIControlStateNormal];
    closeBtn.backgroundColor = UIColor.systemRedColor;
    [closeBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    closeBtn.layer.cornerRadius = 6;
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
        NSLog(@"[SCAN] Ready");
    });
}
