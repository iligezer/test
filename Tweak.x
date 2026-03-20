#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>
#import <objc/runtime.h>

// ========== НАСТРОЙКИ ==========
#define MY_ID 71068432
#define STRUCT_SIZE 0x1000 // размер структуры игрока

// Смещения внутри структуры (из твоих находок)
#define OFFSET_ID        0x08
#define OFFSET_GOLD      0x0C
#define OFFSET_SILVER    0x10
#define OFFSET_HEALTH    0x28
#define OFFSET_X         0x50  // предположительно, нужно уточнить
#define OFFSET_Y         0x54  // предположительно, нужно уточнить
#define OFFSET_Z         0x58  // предположительно, нужно уточнить
#define OFFSET_NAME_PTR  0x60  // указатель на имя (если есть)

// RVA функций (из твоих скриншотов)
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
static UIButton *floatingButton = nil;
static NSMutableArray *players = nil;
static uint64_t baseAddr = 0;

// ========== МОДЕЛЬ ИГРОКА ==========
@interface Player : NSObject
@property (assign) uint64_t address;      // адрес структуры
@property (assign) int playerId;           // ID игрока
@property (assign) int gold;
@property (assign) int silver;
@property (assign) float health;
@property (assign) float x, y, z;
@property (strong) NSString *name;
@property (assign) BOOL isLocal;           // свой игрок
@end

@implementation Player
- (NSString *)description {
    return [NSString stringWithFormat:@"ID:%d HP:%.1f (%.1f,%.1f,%.1f) %@%@",
            self.playerId, self.health, self.x, self.y, self.z,
            self.name ?: @"", self.isLocal ? @" 👤" : @""];
}
@end

// ========== ESP VIEW ==========
@interface ESPView : UIView
@end

@implementation ESPView
- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    
    if (!players || players.count == 0) return;
    if (!Camera_get_main || !Camera_WorldToScreen) return;
    
    void *cam = Camera_get_main();
    if (!cam) return;
    
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    
    for (Player *p in players) {
        if (p.health <= 0) continue; // не рисуем мертвых
        if (p.isLocal) continue;     // не рисуем себя
        
        float position[3] = {p.x, p.y, p.z};
        void *screenPos = Camera_WorldToScreen(cam, position);
        
        if (screenPos) {
            float *screen = (float*)screenPos;
            float screenX = screen[0] * rect.size.width;
            float screenY = screen[1] * rect.size.height;
            
            if (screenX < 0 || screenX > rect.size.width ||
                screenY < 0 || screenY > rect.size.height) continue;
            
            // Цвет (красный для врагов)
            UIColor *color = [UIColor redColor];
            CGContextSetFillColorWithColor(ctx, color.CGColor);
            CGContextFillEllipseInRect(ctx, CGRectMake(screenX - 5, screenY - 5, 10, 10));
            
            // Информация над игроком
            NSString *info = [NSString stringWithFormat:@"HP:%.0f", p.health];
            [info drawAtPoint:CGPointMake(screenX + 10, screenY - 15) withAttributes:@{
                NSFontAttributeName: [UIFont boldSystemFontOfSize:12],
                NSForegroundColorAttributeName: UIColor.whiteColor,
                NSStrokeColorAttributeName: UIColor.blackColor,
                NSStrokeWidthAttributeName: @-2
            }];
        }
    }
}
@end

// ========== ПОЛУЧЕНИЕ БАЗОВОГО АДРЕСА ==========
uint64_t getBaseAddress() {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, "ModernStrike")) {
            return (uint64_t)_dyld_get_image_header(i);
        }
    }
    return 0;
}

void* getRealPtr(uint64_t rva) {
    uint64_t base = getBaseAddress();
    return base ? (void*)(base + rva) : NULL;
}

// ========== ЧТЕНИЕ ПАМЯТИ ==========
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
+ (void)addLog:(NSString*)text;
+ (void)showLog;
+ (UIWindow*)mainWindow;
@end

@interface FloatingButton : UIButton @end

@implementation FloatingButton
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    self.backgroundColor = [UIColor systemBlueColor];
    self.layer.cornerRadius = frame.size.width/2;
    [self setTitle:@"⚡" forState:UIControlStateNormal];
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
    CGFloat w = 260, h = 300;
    UIWindow *menu = [[UIWindow alloc] initWithFrame:CGRectMake((UIScreen.mainScreen.bounds.size.width-w)/2, (UIScreen.mainScreen.bounds.size.height-h)/2, w, h)];
    menu.windowLevel = UIWindowLevelAlert + 3;
    menu.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.95];
    menu.layer.cornerRadius = 10;
    
    __block int y = 20;
    void (^btn)(NSString*, SEL, UIColor*) = ^(NSString *t, SEL s, UIColor *c) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(10, y, w-20, 40);
        b.backgroundColor = c;
        b.layer.cornerRadius = 8;
        [b setTitle:t forState:UIControlStateNormal];
        [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        [b addTarget:self action:s forControlEvents:UIControlEventTouchUpInside];
        [menu addSubview:b];
        y += 45;
    };
    
    btn(@"🔍 НАЙТИ ИГРОКОВ", @selector(scanPlayers), UIColor.systemBlueColor);
    btn(@"📋 ПОКАЗАТЬ ЛОГ", @selector(showLog), UIColor.systemPurpleColor);
    btn(@"❌ ЗАКРЫТЬ", @selector(closeMenu), UIColor.systemRedColor);
    
    [menu makeKeyAndVisible];
    objc_setAssociatedObject(self, @selector(closeMenu), menu, OBJC_ASSOCIATION_RETAIN);
}

+ (void)closeMenu {
    UIWindow *menu = objc_getAssociatedObject(self, @selector(closeMenu));
    menu.hidden = YES;
}

+ (void)scanPlayers {
    players = [NSMutableArray array];
    baseAddr = getBaseAddress();
    
    [self addLog:@"\n🔍 ПОИСК ИГРОКОВ ПО СТРУКТУРЕ"];
    [self addLog:[NSString stringWithFormat:@"📌 База: 0x%llx", baseAddr]];
    
    task_t task = mach_task_self();
    vm_address_t addr = 0;
    vm_size_t size = 0;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object_name;
    
    int total = 0;
    int found = 0;
    
    while (vm_region_64(task, &addr, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &count, &object_name) == KERN_SUCCESS) {
        
        if (size > 4096 && size < 10*1024*1024 && (info.protection & VM_PROT_READ)) {
            
            uint8_t *buffer = malloc(size);
            vm_size_t read;
            
            if (vm_read_overwrite(task, addr, size, (vm_address_t)buffer, &read) == KERN_SUCCESS) {
                
                for (int i = 0; i < size - STRUCT_SIZE; i += 4) {
                    total++;
                    
                    // Проверяем, есть ли по смещению OFFSET_ID наш ID
                    uint32_t *pid = (uint32_t*)(buffer + i + OFFSET_ID);
                    if (*pid == MY_ID) {
                        // Нашли своего игрока!
                        Player *p = [Player new];
                        p.address = addr + i;
                        p.playerId = *pid;
                        p.gold = *(uint32_t*)(buffer + i + OFFSET_GOLD);
                        p.silver = *(uint32_t*)(buffer + i + OFFSET_SILVER);
                        p.health = *(float*)(buffer + i + OFFSET_HEALTH);
                        p.x = *(float*)(buffer + i + OFFSET_X);
                        p.y = *(float*)(buffer + i + OFFSET_Y);
                        p.z = *(float*)(buffer + i + OFFSET_Z);
                        p.isLocal = YES;
                        
                        [players addObject:p];
                        found++;
                        
                        [self addLog:[NSString stringWithFormat:@"✅ СВОЙ: 0x%llx", p.address]];
                        
                        i += 0x100; // пропускаем структуру
                    }
                    
                    // Проверяем другие структуры (враги)
                    uint32_t *val = (uint32_t*)(buffer + i + OFFSET_HEALTH);
                    if (*val > 0 && *val < 200 && *(uint32_t*)(buffer + i + OFFSET_ID) != MY_ID) {
                        // Похоже на врага
                        Player *p = [Player new];
                        p.address = addr + i;
                        p.playerId = *(uint32_t*)(buffer + i + OFFSET_ID);
                        p.health = *(float*)(buffer + i + OFFSET_HEALTH);
                        p.x = *(float*)(buffer + i + OFFSET_X);
                        p.y = *(float*)(buffer + i + OFFSET_Y);
                        p.z = *(float*)(buffer + i + OFFSET_Z);
                        p.isLocal = NO;
                        
                        [players addObject:p];
                        found++;
                        
                        i += 0x100;
                    }
                }
            }
            free(buffer);
        }
        
        addr += size;
    }
    
    [self addLog:[NSString stringWithFormat:@"📊 Проверено адресов: %d", total]];
    [self addLog:[NSString stringWithFormat:@"🎯 Найдено игроков: %d", found]];
    
    // Выводим список
    for (Player *p in players) {
        [self addLog:p.description];
    }
    
    [self showLog];
    
    // Обновляем ESP
    [overlayWindow.subviews.firstObject setNeedsDisplay];
}

+ (void)addLog:(NSString*)t {
    if (!logText) logText = [NSMutableString new];
    [logText appendFormat:@"%@\n", t];
    NSLog(@"%@", t);
}

+ (void)showLog {
    if (!logWindow) {
        logWindow = [[UIWindow alloc] initWithFrame:CGRectMake(20, 70, UIScreen.mainScreen.bounds.size.width-40, 400)];
        logWindow.windowLevel = UIWindowLevelAlert + 2;
        logWindow.backgroundColor = [UIColor colorWithWhite:0 alpha:0.95];
        logWindow.layer.cornerRadius = 10;
        
        UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(5, 5, logWindow.bounds.size.width-10, 340)];
        tv.backgroundColor = UIColor.blackColor;
        tv.textColor = UIColor.greenColor;
        tv.font = [UIFont fontWithName:@"Courier" size:11];
        tv.editable = NO;
        [logWindow addSubview:tv];
        
        UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        copyBtn.frame = CGRectMake(20, 350, 100, 35);
        [copyBtn setTitle:@"📋 Копировать" forState:UIControlStateNormal];
        copyBtn.backgroundColor = UIColor.systemBlueColor;
        copyBtn.layer.cornerRadius = 6;
        [copyBtn addTarget:self action:@selector(copyLog) forControlEvents:UIControlEventTouchUpInside];
        [logWindow addSubview:copyBtn];
        
        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        closeBtn.frame = CGRectMake(logWindow.bounds.size.width-70, 350, 50, 35);
        [closeBtn setTitle:@"✖️" forState:UIControlStateNormal];
        closeBtn.backgroundColor = UIColor.systemRedColor;
        closeBtn.layer.cornerRadius = 6;
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
        
        // Загружаем функции камеры
        Camera_get_main = (t_Camera_get_main)getRealPtr(RVA_Camera_get_main);
        Camera_WorldToScreen = (t_Camera_WorldToScreen)getRealPtr(RVA_Camera_WorldToScreen);
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            UIWindow *mainWindow = [ButtonHandler mainWindow];
            if (!mainWindow) return;
            
            floatingButton = [[FloatingButton alloc] initWithFrame:CGRectMake(20, 150, 50, 50)];
            [mainWindow addSubview:floatingButton];
            
            overlayWindow = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
            overlayWindow.windowLevel = UIWindowLevelAlert + 1;
            overlayWindow.backgroundColor = UIColor.clearColor;
            overlayWindow.userInteractionEnabled = NO;
            
            ESPView *espView = [[ESPView alloc] initWithFrame:UIScreen.mainScreen.bounds];
            espView.backgroundColor = UIColor.clearColor;
            [overlayWindow addSubview:espView];
            
            [overlayWindow makeKeyAndVisible];
            
            [ButtonHandler addLog:@"✅ ESP ЗАГРУЖЕН"];
            [ButtonHandler addLog:@"⚡ ЖМИ КНОПКУ ДЛЯ ПОИСКА"];
        });
    }
}
