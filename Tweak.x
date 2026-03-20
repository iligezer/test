#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>
#import <objc/runtime.h>

// ========== ТВОИ ДАННЫЕ ==========
#define MY_ID 71068432
#define MY_NICK @"Dojki"
#define STRUCT_SIZE 0x200

// СМЕЩЕНИЯ (ВРЕМЕННЫЕ)
#define OFFSET_ID        0x08
#define OFFSET_GOLD      0x0C
#define OFFSET_SILVER    0x10
#define OFFSET_HEALTH    0x28
#define OFFSET_Y         0x54   // ТОЧНАЯ ВЫСОТА!
#define OFFSET_X         0x50   // ПРЕДПОЛОЖИТЕЛЬНО
#define OFFSET_Z         0x58   // ПРЕДПОЛОЖИТЕЛЬНО

// RVA
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
static UIPanGestureRecognizer *panGesture = nil;
static UIButton *floatingButton = nil;
static NSMutableArray *players = nil;
static uint64_t baseAddr = 0;

// ========== МОДЕЛЬ ИГРОКА ==========
@interface Player : NSObject
@property (assign) uint64_t address;
@property (assign) int playerId;
@property (assign) float health;
@property (assign) float x, y, z;
@property (assign) BOOL isLocal;
@end

@implementation Player
- (NSString *)description {
    return [NSString stringWithFormat:@"ID:%d ❤️%.0f 📍(%.1f,%.1f,%.1f)%s",
            self.playerId, self.health, self.x, self.y, self.z,
            self.isLocal ? " 👑" : ""];
}
@end

// ========== ESP VIEW ==========
@interface ESPView : UIView
@end

@implementation ESPView
- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    if (!players.count || !Camera_get_main || !Camera_WorldToScreen) return;
    
    void *cam = Camera_get_main();
    if (!cam) return;
    
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    
    for (Player *p in players) {
        if (p.health <= 0 || p.isLocal) continue;
        
        // Пробуем разные комбинации осей
        float positions[4][3] = {
            {p.x, p.y, p.z},
            {p.x, p.y, p.z},
            {p.z, p.y, p.x},
            {p.x, p.z, p.y}
        };
        
        for (int i = 0; i < 4; i++) {
            void *screenPos = Camera_WorldToScreen(cam, positions[i]);
            if (!screenPos) continue;
            
            float *s = (float*)screenPos;
            float sx = s[0] * rect.size.width;
            float sy = s[1] * rect.size.height;
            
            if (sx > 0 && sx < rect.size.width && sy > 0 && sy < rect.size.height) {
                // Рисуем
                CGContextSetFillColorWithColor(ctx, [UIColor redColor].CGColor);
                CGContextFillEllipseInRect(ctx, CGRectMake(sx-4, sy-4, 8, 8));
                
                NSString *hp = [NSString stringWithFormat:@"%.0f", p.health];
                [hp drawAtPoint:CGPointMake(sx+8, sy-12) withAttributes:@{
                    NSFontAttributeName: [UIFont boldSystemFontOfSize:11],
                    NSForegroundColorAttributeName: UIColor.whiteColor,
                    NSStrokeColorAttributeName: UIColor.blackColor,
                    NSStrokeWidthAttributeName: @-2
                }];
                break;
            }
        }
    }
}
@end

// ========== ПЛАВАЮЩАЯ КНОПКА ==========
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
    self.layer.shadowRadius = 5;
    [self setTitle:@"⚡" forState:UIControlStateNormal];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:28];
    [self addTarget:self action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];
    
    panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
    [self addGestureRecognizer:panGesture];
    return self;
}

- (void)pan:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self.superview];
    CGPoint center = self.center;
    center.x += translation.x;
    center.y += translation.y;
    
    center.x = MAX(self.frame.size.width/2, MIN(center.x, UIScreen.mainScreen.bounds.size.width - self.frame.size.width/2));
    center.y = MAX(self.frame.size.height/2 + 50, MIN(center.y, UIScreen.mainScreen.bounds.size.height - self.frame.size.height/2 - 50));
    
    self.center = center;
    [gesture setTranslation:CGPointZero inView:self.superview];
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
+ (void)scanPlayers;
+ (void)addLog:(NSString*)text;
+ (void)showLog;
+ (void)hideLog;
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

// ========== КРАСИВОЕ МЕНЮ ==========
+ (void)showMenu {
    if (menuWindow) {
        menuWindow.hidden = NO;
        return;
    }
    
    CGFloat w = 300, h = 400;
    menuWindow = [[UIWindow alloc] initWithFrame:CGRectMake((UIScreen.mainScreen.bounds.size.width-w)/2, (UIScreen.mainScreen.bounds.size.height-h)/2, w, h)];
    menuWindow.windowLevel = UIWindowLevelAlert + 3;
    menuWindow.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.98];
    menuWindow.layer.cornerRadius = 30;
    menuWindow.layer.borderWidth = 2;
    menuWindow.layer.borderColor = UIColor.systemBlueColor.CGColor;
    menuWindow.layer.shadowColor = UIColor.blackColor.CGColor;
    menuWindow.layer.shadowOffset = CGSizeMake(0, 10);
    menuWindow.layer.shadowOpacity = 0.5;
    menuWindow.layer.shadowRadius = 20;
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 30, w, 30)];
    title.text = @"⚡ AIMBOT ESP";
    title.textColor = UIColor.whiteColor;
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:24];
    [menuWindow addSubview:title];
    
    UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(0, 60, w, 20)];
    sub.text = @"Modern Strike Online";
    sub.textColor = UIColor.systemBlueColor;
    sub.textAlignment = NSTextAlignmentCenter;
    sub.font = [UIFont systemFontOfSize:14];
    [menuWindow addSubview:sub];
    
    NSArray *btns = @[
        @{@"title":@"🔍 НАЙТИ ИГРОКОВ", @"color":UIColor.systemBlueColor, @"sel":@"scanPlayers"},
        @{@"title":@"📋 ПОКАЗАТЬ ЛОГ", @"color":UIColor.systemOrangeColor, @"sel":@"showLog"},
        @{@"title":@"✖️ ЗАКРЫТЬ", @"color":UIColor.systemRedColor, @"sel":@"closeMenu"}
    ];
    
    int y = 120;
    for (NSDictionary *b in btns) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.frame = CGRectMake(30, y, w-60, 50);
        btn.backgroundColor = b[@"color"];
        btn.layer.cornerRadius = 15;
        btn.layer.shadowColor = UIColor.blackColor.CGColor;
        btn.layer.shadowOffset = CGSizeMake(0, 3);
        btn.layer.shadowOpacity = 0.3;
        btn.layer.shadowRadius = 5;
        [btn setTitle:b[@"title"] forState:UIControlStateNormal];
        [btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
        [btn addTarget:self action:NSSelectorFromString(b[@"sel"]) forControlEvents:UIControlEventTouchUpInside];
        [menuWindow addSubview:btn];
        y += 65;
    }
    
    [menuWindow makeKeyAndVisible];
}

+ (void)closeMenu {
    menuWindow.hidden = YES;
}

// ========== ОПТИМИЗИРОВАННЫЙ ПОИСК ==========
+ (void)scanPlayers {
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
    
    int total = 0, found = 0;
    int scanLimit = 100000;
    
    while (vm_region_64(task, &addr, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &count, &object_name) == KERN_SUCCESS && total < scanLimit) {
        
        if (size > 4096 && size < 2*1024*1024 && (info.protection & VM_PROT_READ)) {
            
            uint8_t *buffer = malloc(size);
            vm_size_t read;
            
            if (vm_read_overwrite(task, addr, size, (vm_address_t)buffer, &read) == KERN_SUCCESS) {
                
                for (int i = 0; i < size - STRUCT_SIZE; i += 8) {
                    total++;
                    
                    float y = *(float*)(buffer + i + OFFSET_Y);
                    if (y > 0 && y < 100) {
                        
                        float health = *(float*)(buffer + i + OFFSET_HEALTH);
                        if (health > 0 && health < 200) {
                            
                            Player *p = [[Player alloc] init];
                            p.address = addr + i;
                            p.health = health;
                            p.y = y;
                            p.x = *(float*)(buffer + i + OFFSET_X);
                            p.z = *(float*)(buffer + i + OFFSET_Z);
                            p.playerId = *(uint32_t*)(buffer + i + OFFSET_ID);
                            p.isLocal = (p.playerId == MY_ID);
                            
                            [players addObject:p];
                            found++;
                            
                            i += 0x80;
                            if (found > 50) break;
                        }
                    }
                }
            }
            free(buffer);
        }
        addr += size;
        
        if (total % 10000 == 0) {
            [self addLog:[NSString stringWithFormat:@"⏳ Сканировано %d...", total]];
            usleep(1000);
        }
    }
    
    [self addLog:[NSString stringWithFormat:@"📊 Проверено: %d", total]];
    [self addLog:[NSString stringWithFormat:@"🎯 Найдено: %d", found]];
    
    for (Player *p in players) {
        [self addLog:p.description];
    }
    
    [overlayWindow.subviews.firstObject setNeedsDisplay];
    [self showLog];
}

// ========== ПОЛУЧЕНИЕ БАЗОВОГО АДРЕСА ==========
+ (uint64_t)getBaseAddress {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && (strstr(name, "ModernStrike") || strstr(name, "GameAssembly"))) {
            return (uint64_t)_dyld_get_image_header(i);
        }
    }
    return 0;
}

+ (void*)getRealPtr:(uint64_t)rva {
    uint64_t base = [self getBaseAddress];
    return base ? (void*)(base + rva) : NULL;
}

// ========== ЛОГ ==========
+ (void)addLog:(NSString*)t {
    if (!logText) logText = [NSMutableString new];
    [logText appendFormat:@"%@\n", t];
    NSLog(@"%@", t);
}

+ (void)showLog {
    if (!logWindow) {
        CGFloat w = UIScreen.mainScreen.bounds.size.width - 40;
        CGFloat h = 400;
        
        logWindow = [[UIWindow alloc] initWithFrame:CGRectMake(20, 150, w, h)];
        logWindow.windowLevel = UIWindowLevelAlert + 2;
        logWindow.backgroundColor = [UIColor colorWithWhite:0 alpha:0.95];
        logWindow.layer.cornerRadius = 20;
        logWindow.layer.borderWidth = 2;
        logWindow.layer.borderColor = UIColor.systemGreenColor.CGColor;
        
        UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(10, 10, w-20, h-80)];
        tv.backgroundColor = UIColor.blackColor;
        tv.textColor = UIColor.systemGreenColor;
        tv.font = [UIFont fontWithName:@"Courier" size:12];
        tv.editable = NO;
        [logWindow addSubview:tv];
        
        UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        copyBtn.frame = CGRectMake(20, h-60, 120, 40);
        copyBtn.backgroundColor = UIColor.systemBlueColor;
        copyBtn.layer.cornerRadius = 12;
        [copyBtn setTitle:@"📋 КОПИРОВАТЬ" forState:UIControlStateNormal];
        [copyBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        copyBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        [copyBtn addTarget:self action:@selector(copyLog) forControlEvents:UIControlEventTouchUpInside];
        [logWindow addSubview:copyBtn];
        
        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        closeBtn.frame = CGRectMake(w-140, h-60, 120, 40);
        closeBtn.backgroundColor = UIColor.systemRedColor;
        closeBtn.layer.cornerRadius = 12;
        [closeBtn setTitle:@"✖️ ЗАКРЫТЬ" forState:UIControlStateNormal];
        [closeBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        [closeBtn addTarget:self action:@selector(hideLog) forControlEvents:UIControlEventTouchUpInside];
        [logWindow addSubview:closeBtn];
    }
    
    UITextView *tv = logWindow.subviews.firstObject;
    tv.text = logText;
    [logWindow makeKeyAndVisible];
}

+ (void)hideLog { logWindow.hidden = YES; }
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
            
            FloatingButton *btn = [[FloatingButton alloc] initWithFrame:CGRectMake(20, 150, 60, 60)];
            [w addSubview:btn];
            floatingButton = btn;
            
            overlayWindow = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
            overlayWindow.windowLevel = UIWindowLevelAlert + 1;
            overlayWindow.backgroundColor = UIColor.clearColor;
            overlayWindow.userInteractionEnabled = NO;
            
            ESPView *esp = [[ESPView alloc] initWithFrame:UIScreen.mainScreen.bounds];
            esp.backgroundColor = UIColor.clearColor;
            [overlayWindow addSubview:esp];
            
            [overlayWindow makeKeyAndVisible];
            
            [ButtonHandler addLog:@"✅ ESP ЗАГРУЖЕН"];
            [ButtonHandler addLog:@"⚡ НАЖМИ КНОПКУ"];
        });
    }
}
