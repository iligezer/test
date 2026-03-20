#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>
#import <objc/runtime.h>

// ========== СМЕЩЕНИЯ (ИЗ ТВОИХ НАХОДОК) ==========
#define OFFSET_X         0x00
#define OFFSET_Y         0x04
#define OFFSET_Z         0x08
#define OFFSET_ARMOR     0x0C
#define OFFSET_ID        0x10

// ========== RVA ФУНКЦИЙ ==========
#define RVA_Camera_get_main         0x445BAF8
#define RVA_Camera_WorldToScreen    0x445AD5C

// ========== ТИПЫ ФУНКЦИЙ ==========
typedef void *(*t_Camera_get_main)();
typedef void *(*t_Camera_WorldToScreen)(void *camera, void *worldPos);

static t_Camera_get_main Camera_get_main = NULL;
static t_Camera_WorldToScreen Camera_WorldToScreen = NULL;

static NSMutableString *logText = nil;
static UIWindow *overlayWindow = nil;
static UIWindow *logWindow = nil;
static UIWindow *menuWindow = nil;
static UIButton *floatingButton = nil;
static NSMutableArray *players = nil;
static uint64_t baseAddr = 0;
static BOOL espEnabled = YES;

// ========== МОДЕЛЬ ИГРОКА ==========
@interface Player : NSObject
@property (assign) float x, y, z;
@property (assign) float health;
@property (assign) int armor;
@property (assign) BOOL isLocal;
@end

@implementation Player
- (NSString *)description {
    return [NSString stringWithFormat:@"📍(%.1f,%.1f,%.1f) ❤️%.0f 🛡️%d%s",
            self.x, self.y, self.z, self.health, self.armor,
            self.isLocal ? " 👑" : ""];
}
@end

// ========== ESP VIEW ==========
@interface ESPView : UIView
@end

@implementation ESPView
- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    if (!espEnabled || !players.count || !Camera_get_main || !Camera_WorldToScreen) return;
    
    void *cam = Camera_get_main();
    if (!cam) return;
    
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    
    for (Player *p in players) {
        if (p.isLocal) continue;
        
        float pos[3] = {p.x, p.y, p.z};
        void *screenPos = Camera_WorldToScreen(cam, pos);
        if (!screenPos) continue;
        
        float *s = (float*)screenPos;
        float sx = s[0] * rect.size.width;
        float sy = s[1] * rect.size.height;
        
        if (sx > 0 && sx < rect.size.width && sy > 0 && sy < rect.size.height) {
            CGContextSetFillColorWithColor(ctx, [UIColor redColor].CGColor);
            CGContextFillEllipseInRect(ctx, CGRectMake(sx-4, sy-4, 8, 8));
            
            NSString *hp = [NSString stringWithFormat:@"%.0f", p.health];
            [hp drawAtPoint:CGPointMake(sx+8, sy-12) withAttributes:@{
                NSFontAttributeName: [UIFont boldSystemFontOfSize:11],
                NSForegroundColorAttributeName: UIColor.whiteColor,
                NSStrokeColorAttributeName: UIColor.blackColor,
                NSStrokeWidthAttributeName: @-2
            }];
        }
    }
}
@end

// ========== ПЛАВАЮЩАЯ КНОПКА ==========
@class ButtonHandler;

@interface FloatingButton : UIButton
@end

@implementation FloatingButton
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    self.backgroundColor = [UIColor systemBlueColor];
    self.layer.cornerRadius = frame.size.width/2;
    self.layer.shadowColor = UIColor.blackColor.CGColor;
    self.layer.shadowOffset = CGSizeMake(0, 4);
    self.layer.shadowOpacity = 0.5;
    [self setTitle:@"⚡" forState:UIControlStateNormal];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:28];
    [self addTarget:self action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];
    
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
    [self addGestureRecognizer:pan];
    return self;
}

- (void)pan:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.superview];
    CGPoint c = self.center;
    c.x += t.x;
    c.y += t.y;
    c.x = MAX(30, MIN(c.x, UIScreen.mainScreen.bounds.size.width - 30));
    c.y = MAX(100, MIN(c.y, UIScreen.mainScreen.bounds.size.height - 100));
    self.center = c;
    [g setTranslation:CGPointZero inView:self.superview];
}

- (void)tapped {
    Class handler = NSClassFromString(@"ButtonHandler");
    if (handler) {
        [handler performSelector:@selector(showMenu)];
    }
}
@end

// ========== ОСНОВНАЯ ЛОГИКА ==========
@interface ButtonHandler : NSObject
+ (void)showMenu;
+ (void)closeMenu;
+ (void)findPlayers;
+ (void)toggleESP;
+ (void)addLog:(NSString*)text;
+ (void)showLog;
+ (void)closeLog;
+ (void)copyLog;
+ (uint64_t)getBaseAddress;
+ (UIWindow*)mainWindow;
@end

@implementation ButtonHandler

+ (UIWindow*)mainWindow {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class]) {
            for (UIWindow *w in ((UIWindowScene*)scene).windows)
                if (w.isKeyWindow) return w;
        }
    }
    return nil;
}

+ (uint64_t)getBaseAddress {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && (strstr(name, "ModernStrike") || strstr(name, "GameAssembly"))) {
            return (uint64_t)_dyld_get_image_header(i);
        }
    }
    return 0;
}

+ (void)showMenu {
    if (menuWindow) {
        menuWindow.hidden = NO;
        return;
    }
    
    CGFloat w = 280, h = 350;
    menuWindow = [[UIWindow alloc] initWithFrame:CGRectMake((UIScreen.mainScreen.bounds.size.width-w)/2, (UIScreen.mainScreen.bounds.size.height-h)/2, w, h)];
    menuWindow.windowLevel = UIWindowLevelAlert + 3;
    menuWindow.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.98];
    menuWindow.layer.cornerRadius = 20;
    menuWindow.layer.borderWidth = 2;
    menuWindow.layer.borderColor = UIColor.systemBlueColor.CGColor;
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 20, w, 30)];
    title.text = @"⚡ ESP MODERN";
    title.textColor = UIColor.whiteColor;
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:22];
    [menuWindow addSubview:title];
    
    NSArray *btns = @[
        @{@"title":@"🔍 НАЙТИ ИГРОКОВ", @"color":UIColor.systemBlueColor, @"sel":@"findPlayers"},
        @{@"title":@"👁️ ВКЛ/ВЫКЛ ESP", @"color":UIColor.systemGreenColor, @"sel":@"toggleESP"},
        @{@"title":@"📋 ПОКАЗАТЬ ЛОГ", @"color":UIColor.systemOrangeColor, @"sel":@"showLog"},
        @{@"title":@"✖️ ЗАКРЫТЬ", @"color":UIColor.systemRedColor, @"sel":@"closeMenu"}
    ];
    
    int y = 70;
    for (NSDictionary *b in btns) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.frame = CGRectMake(20, y, w-40, 45);
        btn.backgroundColor = b[@"color"];
        btn.layer.cornerRadius = 12;
        [btn setTitle:b[@"title"] forState:UIControlStateNormal];
        [btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont boldSystemFontOfSize:15];
        [btn addTarget:self action:NSSelectorFromString(b[@"sel"]) forControlEvents:UIControlEventTouchUpInside];
        [menuWindow addSubview:btn];
        y += 55;
    }
    
    [menuWindow makeKeyAndVisible];
}

+ (void)closeMenu {
    menuWindow.hidden = YES;
}

+ (void)toggleESP {
    espEnabled = !espEnabled;
    [self addLog:espEnabled ? @"✅ ESP ВКЛЮЧЕН" : @"❌ ESP ВЫКЛЮЧЕН"];
    [overlayWindow.subviews.firstObject setNeedsDisplay];
}

+ (void)findPlayers {
    players = [NSMutableArray array];
    baseAddr = [self getBaseAddress];
    
    [self addLog:@"\n🔍 ПОИСК ИГРОКОВ"];
    [self addLog:@"================"];
    [self addLog:[NSString stringWithFormat:@"📌 База: 0x%llx", baseAddr]];
    
    task_t task = mach_task_self();
    vm_address_t addr = 0;
    vm_size_t size = 0;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object_name;
    
    int found = 0;
    int scanned = 0;
    
    while (vm_region_64(task, &addr, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &count, &object_name) == KERN_SUCCESS && found < 30) {
        
        if (size > 4096 && size < 5*1024*1024 && (info.protection & VM_PROT_READ)) {
            
            uint8_t *buffer = malloc(size);
            vm_size_t read;
            
            if (vm_read_overwrite(task, addr, size, (vm_address_t)buffer, &read) == KERN_SUCCESS) {
                
                for (int i = 0; i < size - 0x100; i += 8) {
                    scanned++;
                    
                    // Читаем X, Y, Z как три float подряд
                    float *x = (float*)(buffer + i);
                    float *y = (float*)(buffer + i + 4);
                    float *z = (float*)(buffer + i + 8);
                    
                    // Фильтр 1: координаты не нулевые и не огромные
                    if (fabs(*x) < 0.1 && fabs(*y) < 0.1 && fabs(*z) < 0.1) continue;
                    if (fabs(*x) > 10000 || fabs(*y) > 10000 || fabs(*z) > 10000) continue;
                    
                    // Фильтр 2: броня рядом (10000-150000)
                    int *armor = (int*)(buffer + i + OFFSET_ARMOR);
                    if (*armor < 10000 || *armor > 150000) continue;
                    
                    // Нашли игрока!
                    Player *p = [[Player alloc] init];
                    p.x = *x;
                    p.y = *y;
                    p.z = *z;
                    p.armor = *armor;
                    p.health = 100;
                    p.isLocal = NO;
                    
                    [players addObject:p];
                    found++;
                    
                    [self addLog:[NSString stringWithFormat:@"✅ Игрок %d: (%.1f,%.1f,%.1f) 🛡️%d",
                                  found, p.x, p.y, p.z, p.armor]];
                    
                    i += 0x80;
                    if (found >= 20) break;
                }
            }
            free(buffer);
        }
        addr += size;
        if (found % 100 == 0) usleep(1000);
    }
    
    [self addLog:[NSString stringWithFormat:@"📊 Проверено адресов: %d", scanned]];
    [self addLog:[NSString stringWithFormat:@"🎯 Найдено игроков: %d", found]];
    [overlayWindow.subviews.firstObject setNeedsDisplay];
    [self showLog];
}

+ (void)addLog:(NSString*)t {
    if (!logText) logText = [NSMutableString new];
    [logText appendFormat:@"%@\n", t];
    NSLog(@"%@", t);
}

+ (void)showLog {
    if (!logWindow) {
        CGFloat w = 300;
        CGFloat h = 400;
        CGFloat x = (UIScreen.mainScreen.bounds.size.width - w) / 2;
        CGFloat y = (UIScreen.mainScreen.bounds.size.height - h) / 2;
        
        logWindow = [[UIWindow alloc] initWithFrame:CGRectMake(x, y, w, h)];
        logWindow.windowLevel = UIWindowLevelAlert + 2;
        logWindow.backgroundColor = [UIColor colorWithWhite:0 alpha:0.95];
        logWindow.layer.cornerRadius = 15;
        logWindow.layer.borderWidth = 2;
        logWindow.layer.borderColor = UIColor.systemGreenColor.CGColor;
        
        UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(5, 5, w-10, h-80)];
        tv.backgroundColor = UIColor.blackColor;
        tv.textColor = UIColor.greenColor;
        tv.font = [UIFont fontWithName:@"Courier" size:11];
        tv.editable = NO;
        [logWindow addSubview:tv];
        
        UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        copyBtn.frame = CGRectMake(20, h-65, 100, 40);
        copyBtn.backgroundColor = UIColor.systemBlueColor;
        copyBtn.layer.cornerRadius = 10;
        [copyBtn setTitle:@"📋 Копировать" forState:UIControlStateNormal];
        [copyBtn addTarget:self action:@selector(copyLog) forControlEvents:UIControlEventTouchUpInside];
        [logWindow addSubview:copyBtn];
        
        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        closeBtn.frame = CGRectMake(w-120, h-65, 100, 40);
        closeBtn.backgroundColor = UIColor.systemRedColor;
        closeBtn.layer.cornerRadius = 10;
        [closeBtn setTitle:@"✖️ Закрыть" forState:UIControlStateNormal];
        [closeBtn addTarget:self action:@selector(closeLog) forControlEvents:UIControlEventTouchUpInside];
        [logWindow addSubview:closeBtn];
    }
    
    UITextView *tv = logWindow.subviews.firstObject;
    tv.text = logText;
    [logWindow makeKeyAndVisible];
}

+ (void)closeLog { logWindow.hidden = YES; }
+ (void)copyLog { UIPasteboard.generalPasteboard.string = logText; }

@end

// ========== ИНИЦИАЛИЗАЦИЯ ==========
__attribute__((constructor))
static void init() {
    @autoreleasepool {
        logText = [NSMutableString new];
        
        uint64_t base = [ButtonHandler getBaseAddress];
        Camera_get_main = (t_Camera_get_main)(base + RVA_Camera_get_main);
        Camera_WorldToScreen = (t_Camera_WorldToScreen)(base + RVA_Camera_WorldToScreen);
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            UIWindow *w = [ButtonHandler mainWindow];
            if (!w) return;
            
            floatingButton = [[FloatingButton alloc] initWithFrame:CGRectMake(20, 150, 55, 55)];
            [w addSubview:floatingButton];
            
            overlayWindow = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
            overlayWindow.windowLevel = UIWindowLevelAlert + 1;
            overlayWindow.backgroundColor = UIColor.clearColor;
            overlayWindow.userInteractionEnabled = NO;
            
            ESPView *esp = [[ESPView alloc] initWithFrame:UIScreen.mainScreen.bounds];
            esp.backgroundColor = UIColor.clearColor;
            [overlayWindow addSubview:esp];
            
            [overlayWindow makeKeyAndVisible];
            
            [ButtonHandler addLog:@"✅ ESP ГОТОВ"];
            [ButtonHandler addLog:@"⚡ НАЖМИ КНОПКУ"];
        });
    }
}
