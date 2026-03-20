#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>
#import <objc/runtime.h>

// ========== ТВОИ ДАННЫЕ ==========
#define MY_ID 71068432
#define STRUCT_SIZE 0x1000

// СМЕЩЕНИЯ (ЗАПОЛНИ ПОСЛЕ НАХОЖДЕНИЯ)
#define OFFSET_ID        0x08
#define OFFSET_GOLD      0x0C
#define OFFSET_SILVER    0x10
#define OFFSET_HEALTH    0x28
#define OFFSET_X         0x50   // ЗАМЕНИТЬ!
#define OFFSET_Y         0x54   // ЗАМЕНИТЬ!
#define OFFSET_Z         0x58   // ЗАМЕНИТЬ!
#define OFFSET_NAME_PTR  0x60

// RVA ИЗ ТВОИХ СКРИНШОТОВ
#define RVA_Camera_get_main         0x445BAF8
#define RVA_Camera_WorldToScreen    0x445AD5C
#define RVA_GameManager_GetLocalPlayer 0x3839064
#define RVA_Player_GetHealth         0x2EACF44
#define RVA_Player_GetTransform      0x2EA8C10
#define RVA_Transform_get_position   0x44CEED0

// ========== ТИПЫ ФУНКЦИЙ ==========
typedef void *(*t_Camera_get_main)();
typedef void *(*t_Camera_WorldToScreen)(void *camera, void *worldPos);
typedef void *(*t_GameManager_GetLocalPlayer)(void *gm);
typedef float (*t_Player_GetHealth)(void *player);
typedef void *(*t_Player_GetTransform)(void *player);
typedef void *(*t_Transform_get_position)(void *transform);

static t_Camera_get_main Camera_get_main = NULL;
static t_Camera_WorldToScreen Camera_WorldToScreen = NULL;
static t_GameManager_GetLocalPlayer GameManager_GetLocalPlayer = NULL;
static t_Player_GetHealth Player_GetHealth = NULL;
static t_Player_GetTransform Player_GetTransform = NULL;
static t_Transform_get_position Transform_get_position = NULL;

static NSMutableString *logText = nil;
static UIWindow *overlayWindow = nil;
static UIWindow *logWindow = nil;
static UIButton *floatingButton = nil;
static NSMutableArray *players = nil;
static uint64_t baseAddr = 0;

// ========== МОДЕЛЬ ИГРОКА ==========
@interface Player : NSObject
@property (assign) uint64_t address;
@property (assign) int playerId;
@property (assign) int gold;
@property (assign) int silver;
@property (assign) float health;
@property (assign) float x, y, z;
@property (strong) NSString *name;
@property (assign) BOOL isLocal;
@end

@implementation Player
- (NSString *)description {
    return [NSString stringWithFormat:@"ID:%d ❤️%.0f 📍(%.1f,%.1f,%.1f) %@%@",
            self.playerId, self.health, self.x, self.y, self.z,
            self.name ?: @"", self.isLocal ? @" 👑" : @""];
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
        
        float pos[3] = {p.x, p.y, p.z};
        void *screenPos = Camera_WorldToScreen(cam, pos);
        if (!screenPos) continue;
        
        float *s = (float*)screenPos;
        float sx = s[0] * rect.size.width;
        float sy = s[1] * rect.size.height;
        
        if (sx < 0 || sx > rect.size.width || sy < 0 || sy > rect.size.height) continue;
        
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
@end

// ========== ПОЛУЧЕНИЕ БАЗОВОГО АДРЕСА ==========
uint64_t getBaseAddress() {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && (strstr(name, "ModernStrike") || strstr(name, "GameAssembly"))) {
            return (uint64_t)_dyld_get_image_header(i);
        }
    }
    return 0;
}

void* getRealPtr(uint64_t rva) {
    uint64_t base = getBaseAddress();
    return base ? (void*)(base + rva) : NULL;
}

// ========== БЕЗОПАСНОЕ ЧТЕНИЕ ==========
uint32_t readU32(uint64_t addr) {
    uint32_t val = 0;
    vm_size_t read;
    vm_read_overwrite(mach_task_self(), addr, 4, (vm_address_t)&val, &read);
    return val;
}

float readFloat(uint64_t addr) {
    float val = 0;
    vm_size_t read;
    vm_read_overwrite(mach_task_self(), addr, 4, (vm_address_t)&val, &read);
    return val;
}

// ========== ИНТЕРФЕЙС ==========
@interface ButtonHandler : NSObject
+ (void)showMenu;
+ (void)scanPlayers;
+ (void)testRVA;
+ (void)addLog:(NSString*)text;
+ (void)showLog;
+ (void)hideLog;
+ (void)copyLog;
+ (UIWindow*)mainWindow;
@end

@interface FloatingButton : UIButton @end
@implementation FloatingButton
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    self.backgroundColor = [UIColor systemBlueColor];
    self.layer.cornerRadius = frame.size.width/2;
    self.layer.shadowColor = UIColor.blackColor.CGColor;
    self.layer.shadowOffset = CGSizeMake(0, 2);
    self.layer.shadowOpacity = 0.5;
    [self setTitle:@"⚡" forState:UIControlStateNormal];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:24];
    [self addTarget:[ButtonHandler class] action:@selector(showMenu) forControlEvents:UIControlEventTouchUpInside];
    return self;
}
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

+ (void)showMenu {
    CGFloat w = 280, h = 380;
    UIWindow *menu = [[UIWindow alloc] initWithFrame:CGRectMake((UIScreen.mainScreen.bounds.size.width-w)/2, (UIScreen.mainScreen.bounds.size.height-h)/2, w, h)];
    menu.windowLevel = UIWindowLevelAlert + 3;
    menu.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.98];
    menu.layer.cornerRadius = 20;
    menu.layer.borderWidth = 2;
    menu.layer.borderColor = UIColor.systemBlueColor.CGColor;
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 15, w, 30)];
    title.text = @"⚡ AIMBOT ESP";
    title.textColor = UIColor.whiteColor;
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:20];
    [menu addSubview:title];
    
    __block int y = 60;
    void (^btn)(NSString*, SEL, UIColor*) = ^(NSString *t, SEL s, UIColor *c) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(20, y, w-40, 45);
        b.backgroundColor = c;
        b.layer.cornerRadius = 12;
        b.layer.shadowColor = UIColor.blackColor.CGColor;
        b.layer.shadowOffset = CGSizeMake(0, 2);
        b.layer.shadowOpacity = 0.3;
        [b setTitle:t forState:UIControlStateNormal];
        [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont boldSystemFontOfSize:16];
        [b addTarget:self action:s forControlEvents:UIControlEventTouchUpInside];
        [menu addSubview:b];
        y += 52;
    };
    
    btn(@"🔍 НАЙТИ ИГРОКОВ", @selector(scanPlayers), UIColor.systemBlueColor);
    btn(@"🧪 ТЕСТ RVA", @selector(testRVA), UIColor.systemPurpleColor);
    btn(@"📋 ПОКАЗАТЬ ЛОГ", @selector(showLog), UIColor.systemOrangeColor);
    btn(@"✖️ ЗАКРЫТЬ", @selector(closeMenu), UIColor.systemRedColor);
    
    [menu makeKeyAndVisible];
    objc_setAssociatedObject(self, @selector(closeMenu), menu, OBJC_ASSOCIATION_RETAIN);
}

+ (void)closeMenu {
    UIWindow *menu = objc_getAssociatedObject(self, @selector(closeMenu));
    menu.hidden = YES;
}

+ (void)testRVA {
    logText = [NSMutableString new];
    baseAddr = getBaseAddress();
    
    [self addLog:@"🧪 ТЕСТ RVA ФУНКЦИЙ"];
    [self addLog:@"==================="];
    [self addLog:[NSString stringWithFormat:@"📌 Base: 0x%llx", baseAddr]];
    
    Camera_get_main = (t_Camera_get_main)getRealPtr(RVA_Camera_get_main);
    Camera_WorldToScreen = (t_Camera_WorldToScreen)getRealPtr(RVA_Camera_WorldToScreen);
    GameManager_GetLocalPlayer = (t_GameManager_GetLocalPlayer)getRealPtr(RVA_GameManager_GetLocalPlayer);
    Player_GetHealth = (t_Player_GetHealth)getRealPtr(RVA_Player_GetHealth);
    Player_GetTransform = (t_Player_GetTransform)getRealPtr(RVA_Player_GetTransform);
    Transform_get_position = (t_Transform_get_position)getRealPtr(RVA_Transform_get_position);
    
    [self addLog:[NSString stringWithFormat:@"✅ Camera: %p", Camera_get_main]];
    [self addLog:[NSString stringWithFormat:@"✅ WorldToScreen: %p", Camera_WorldToScreen]];
    [self addLog:[NSString stringWithFormat:@"✅ GetLocalPlayer: %p", GameManager_GetLocalPlayer]];
    [self addLog:[NSString stringWithFormat:@"✅ GetHealth: %p", Player_GetHealth]];
    [self addLog:[NSString stringWithFormat:@"✅ GetTransform: %p", Player_GetTransform]];
    [self addLog:[NSString stringWithFormat:@"✅ GetPosition: %p", Transform_get_position]];
    
    if (Camera_get_main) {
        @try {
            void *cam = Camera_get_main();
            [self addLog:[NSString stringWithFormat:@"📷 Камера: %p", cam]];
        } @catch (id e) {
            [self addLog:@"❌ Ошибка камеры"];
        }
    }
    
    [self showLog];
}

+ (void)scanPlayers {
    players = [NSMutableArray array];
    baseAddr = getBaseAddress();
    
    [self addLog:@"\n🔍 ПОИСК ИГРОКОВ"];
    [self addLog:@"================"];
    [self addLog:[NSString stringWithFormat:@"📌 Base: 0x%llx", baseAddr]];
    
    task_t task = mach_task_self();
    vm_address_t addr = 0;
    vm_size_t size = 0;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object_name;
    
    int total = 0, found = 0;
    
    while (vm_region_64(task, &addr, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &count, &object_name) == KERN_SUCCESS) {
        
        if (size > 4096 && size < 20*1024*1024 && (info.protection & VM_PROT_READ)) {
            
            uint8_t *buffer = malloc(size);
            vm_size_t read;
            
            if (vm_read_overwrite(task, addr, size, (vm_address_t)buffer, &read) == KERN_SUCCESS) {
                
                for (int i = 0; i < size - STRUCT_SIZE; i += 4) {
                    total++;
                    
                    uint32_t *pid = (uint32_t*)(buffer + i + OFFSET_ID);
                    if (*pid == MY_ID || (*pid > 0 && *(uint32_t*)(buffer + i + OFFSET_HEALTH) < 200)) {
                        
                        Player *p = [Player new];
                        p.address = addr + i;
                        p.playerId = *pid;
                        p.health = *(float*)(buffer + i + OFFSET_HEALTH);
                        p.x = *(float*)(buffer + i + OFFSET_X);
                        p.y = *(float*)(buffer + i + OFFSET_Y);
                        p.z = *(float*)(buffer + i + OFFSET_Z);
                        p.isLocal = (*pid == MY_ID);
                        
                        if (p.health > 0 && p.health < 200) {
                            [players addObject:p];
                            found++;
                            i += 0x100;
                        }
                    }
                }
            }
            free(buffer);
        }
        addr += size;
        if (total % 100000 == 0) usleep(1000);
    }
    
    [self addLog:[NSString stringWithFormat:@"📊 Проверено: %d", total]];
    [self addLog:[NSString stringWithFormat:@"🎯 Найдено: %d", found]];
    
    for (Player *p in players) {
        [self addLog:p.description];
    }
    
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
        CGFloat w = UIScreen.mainScreen.bounds.size.width - 40;
        CGFloat h = UIScreen.mainScreen.bounds.size.height - 200;
        
        logWindow = [[UIWindow alloc] initWithFrame:CGRectMake(20, 100, w, h)];
        logWindow.windowLevel = UIWindowLevelAlert + 2;
        logWindow.backgroundColor = [UIColor colorWithWhite:0 alpha:0.95];
        logWindow.layer.cornerRadius = 15;
        logWindow.layer.borderWidth = 2;
        logWindow.layer.borderColor = UIColor.systemGreenColor.CGColor;
        
        UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(5, 5, w-10, h-90)];
        tv.backgroundColor = UIColor.blackColor;
        tv.textColor = UIColor.systemGreenColor;
        tv.font = [UIFont fontWithName:@"Courier" size:12];
        tv.editable = NO;
        [logWindow addSubview:tv];
        
        UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        copyBtn.frame = CGRectMake(20, h-75, 120, 40);
        copyBtn.backgroundColor = UIColor.systemBlueColor;
        copyBtn.layer.cornerRadius = 10;
        [copyBtn setTitle:@"📋 КОПИРОВАТЬ" forState:UIControlStateNormal];
        [copyBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        copyBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        [copyBtn addTarget:self action:@selector(copyLog) forControlEvents:UIControlEventTouchUpInside];
        [logWindow addSubview:copyBtn];
        
        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        closeBtn.frame = CGRectMake(w-140, h-75, 120, 40);
        closeBtn.backgroundColor = UIColor.systemRedColor;
        closeBtn.layer.cornerRadius = 10;
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
        
        Camera_get_main = (t_Camera_get_main)getRealPtr(RVA_Camera_get_main);
        Camera_WorldToScreen = (t_Camera_WorldToScreen)getRealPtr(RVA_Camera_WorldToScreen);
        
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
            
            [ButtonHandler addLog:@"✅ ESP ЗАГРУЖЕН"];
            [ButtonHandler addLog:@"⚡ НАЖМИ КНОПКУ"];
        });
    }
}
