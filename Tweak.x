#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>
#import <objc/runtime.h>

// ========== НАСТРОЙКИ ==========
#define TARGET_ID 71068432
#define SCAN_START 0x100000000
#define SCAN_END 0x200000000

static NSMutableString *logText = nil;
static UIWindow *logWindow = nil;
static UIWindow *menuWindow = nil;
static UIButton *floatingButton = nil;

// ========== ОБЪЯВЛЕНИЕ КЛАССА ВПЕРЕДИ ==========
@class ButtonHandler;

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
    [self setTitle:@"🔍" forState:UIControlStateNormal];
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
    [ButtonHandler showMenu];
}
@end

// ========== ОСНОВНАЯ ЛОГИКА ==========
@interface ButtonHandler : NSObject
+ (void)showMenu;
+ (void)closeMenu;
+ (void)findKeyAddresses;
+ (void)showLog;
+ (void)closeLog;
+ (void)copyLog;
+ (void)addLog:(NSString*)text;
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

+ (void)addLog:(NSString*)t {
    if (!logText) logText = [NSMutableString new];
    [logText appendFormat:@"%@\n", t];
    NSLog(@"%@", t);
}

+ (void)showLog {
    if (!logWindow) {
        CGFloat w = 350, h = 500;
        CGFloat x = (UIScreen.mainScreen.bounds.size.width - w) / 2;
        CGFloat y = (UIScreen.mainScreen.bounds.size.height - h) / 2;
        if (y < 50) y = 50;
        
        logWindow = [[UIWindow alloc] initWithFrame:CGRectMake(x, y, w, h)];
        logWindow.windowLevel = UIWindowLevelAlert + 2;
        logWindow.backgroundColor = [UIColor colorWithWhite:0 alpha:0.95];
        logWindow.layer.cornerRadius = 15;
        logWindow.layer.borderWidth = 2;
        logWindow.layer.borderColor = UIColor.systemGreenColor.CGColor;
        
        UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(5, 5, w-10, h-80)];
        tv.backgroundColor = UIColor.blackColor;
        tv.textColor = UIColor.greenColor;
        tv.font = [UIFont fontWithName:@"Courier" size:10];
        tv.editable = NO;
        [logWindow addSubview:tv];
        
        UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        copyBtn.frame = CGRectMake(20, h-65, 120, 40);
        copyBtn.backgroundColor = UIColor.systemBlueColor;
        copyBtn.layer.cornerRadius = 10;
        [copyBtn setTitle:@"📋 КОПИРОВАТЬ" forState:UIControlStateNormal];
        [copyBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        [copyBtn addTarget:self action:@selector(copyLog) forControlEvents:UIControlEventTouchUpInside];
        [logWindow addSubview:copyBtn];
        
        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        closeBtn.frame = CGRectMake(w-140, h-65, 120, 40);
        closeBtn.backgroundColor = UIColor.systemRedColor;
        closeBtn.layer.cornerRadius = 10;
        [closeBtn setTitle:@"✖️ ЗАКРЫТЬ" forState:UIControlStateNormal];
        [closeBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        [closeBtn addTarget:self action:@selector(closeLog) forControlEvents:UIControlEventTouchUpInside];
        [logWindow addSubview:closeBtn];
        
        objc_setAssociatedObject(logWindow, "textView", tv, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    
    UITextView *tv = objc_getAssociatedObject(logWindow, "textView");
    tv.text = logText;
    if (tv.text.length) {
        [tv scrollRangeToVisible:NSMakeRange(tv.text.length - 1, 1)];
    }
    logWindow.hidden = NO;
    [logWindow makeKeyAndVisible];
}

+ (void)closeLog { logWindow.hidden = YES; }
+ (void)copyLog { UIPasteboard.generalPasteboard.string = logText; }

+ (void)showMenu {
    if (menuWindow) {
        menuWindow.hidden = NO;
        return;
    }
    
    CGFloat w = 280, h = 200;
    menuWindow = [[UIWindow alloc] initWithFrame:CGRectMake((UIScreen.mainScreen.bounds.size.width-w)/2, (UIScreen.mainScreen.bounds.size.height-h)/2, w, h)];
    menuWindow.windowLevel = UIWindowLevelAlert + 3;
    menuWindow.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.98];
    menuWindow.layer.cornerRadius = 20;
    menuWindow.layer.borderWidth = 2;
    menuWindow.layer.borderColor = UIColor.systemBlueColor.CGColor;
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 20, w, 30)];
    title.text = @"🎯 ESP SCANNER";
    title.textColor = UIColor.whiteColor;
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:22];
    [menuWindow addSubview:title];
    
    NSArray *btns = @[
        @{@"title":@"🔑 НАЙТИ АДРЕСА", @"color":UIColor.systemBlueColor, @"sel":@"findKeyAddresses"},
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
        [btn addTarget:self action:NSSelectorFromString(b[@"sel"]) forControlEvents:UIControlEventTouchUpInside];
        [menuWindow addSubview:btn];
        y += 55;
    }
    
    [menuWindow makeKeyAndVisible];
}

+ (void)closeMenu { menuWindow.hidden = YES; }

// ========== ГЛАВНАЯ ФУНКЦИЯ: ПОИСК КЛЮЧЕВЫХ АДРЕСОВ ==========
+ (void)findKeyAddresses {
    [self addLog:@"\n🔑 ПОИСК КЛЮЧЕВЫХ АДРЕСОВ"];
    [self addLog:@"======================="];
    [self addLog:[NSString stringWithFormat:@"🎯 Ищем ID: %u", TARGET_ID]];
    
    task_t task = mach_task_self();
    vm_address_t addr = SCAN_START;
    vm_size_t size;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object_name;
    
    NSMutableArray *idAddresses = [NSMutableArray array];
    int scanned = 0;
    
    while (addr < SCAN_END && scanned < 50000) {
        if (vm_region_64(task, &addr, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &count, &object_name) != KERN_SUCCESS) {
            addr += 0x1000;
            continue;
        }
        
        if (size > 0 && (info.protection & VM_PROT_READ)) {
            uint8_t *buffer = malloc(size);
            vm_size_t read;
            
            if (vm_read_overwrite(task, addr, size, (vm_address_t)buffer, &read) == KERN_SUCCESS) {
                for (int i = 0; i < (int)size - 4; i += 4) {
                    uint32_t *val = (uint32_t*)(buffer + i);
                    if (*val == TARGET_ID) {
                        uint64_t foundAddr = addr + i;
                        [idAddresses addObject:@(foundAddr)];
                        [self addLog:[NSString stringWithFormat:@"✅ ID найден: 0x%llx", foundAddr]];
                        scanned++;
                        if (idAddresses.count >= 20) break;
                    }
                }
            }
            free(buffer);
        }
        addr += size;
    }
    
    [self addLog:[NSString stringWithFormat:@"\n📊 Найдено адресов ID: %lu", (unsigned long)idAddresses.count]];
    
    // Проверяем первые 5 адресов
    [self addLog:@"\n🔍 ПРОВЕРКА СТРУКТУРЫ:"];
    for (int i = 0; i < MIN(5, idAddresses.count); i++) {
        uint64_t idAddr = [idAddresses[i] unsignedLongLongValue];
        uint64_t structStart = idAddr - 0x10;
        
        [self addLog:[NSString stringWithFormat:@"\n📌 ID: 0x%llx", idAddr]];
        [self addLog:[NSString stringWithFormat:@"   Начало структуры: 0x%llx", structStart]];
        
        // Проверяем Team (0x34 от начала = 0x24 от ID)
        uint64_t teamAddr = idAddr + 0x24;
        uint32_t team = 0;
        vm_size_t read;
        if (vm_read_overwrite(task, teamAddr, 4, (vm_address_t)&team, &read) == KERN_SUCCESS) {
            [self addLog:[NSString stringWithFormat:@"   Team (+0x24): %u %@", team, team == 0 ? @"(свои)" : @"(враги)"]];
        }
        
        // Проверяем указатель на имя (0x18 от начала = 0x8 от ID)
        uint64_t namePtrAddr = idAddr + 0x8;
        uint64_t namePtr = 0;
        if (vm_read_overwrite(task, namePtrAddr, 8, (vm_address_t)&namePtr, &read) == KERN_SUCCESS && namePtr > 0x100000000) {
            [self addLog:[NSString stringWithFormat:@"   Указатель имени: 0x%llx", namePtr]];
            // Читаем имя
            char nameBuf[64] = {0};
            if (vm_read_overwrite(task, namePtr, 32, (vm_address_t)nameBuf, &read) == KERN_SUCCESS) {
                NSString *name = [NSString stringWithUTF8String:nameBuf];
                [self addLog:[NSString stringWithFormat:@"   Имя: %@", name]];
            }
        }
        
        // Проверяем IsWasted (0x7A от начала = 0x6A от ID)
        uint64_t wastedAddr = idAddr + 0x6A;
        uint8_t isWasted = 0;
        if (vm_read_overwrite(task, wastedAddr, 1, (vm_address_t)&isWasted, &read) == KERN_SUCCESS) {
            [self addLog:[NSString stringWithFormat:@"   IsWasted (+0x6A): %u", isWasted]];
        }
    }
    
    [self addLog:@"\n✅ ПОИСК ЗАВЕРШЕН"];
    [self addLog:@"💡 Скопируй адреса для ESP"];
    [self showLog];
}

@end

// ========== ИНИЦИАЛИЗАЦИЯ ==========
__attribute__((constructor))
static void init() {
    @autoreleasepool {
        logText = [NSMutableString new];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            UIWindow *w = [ButtonHandler mainWindow];
            if (w) {
                floatingButton = [[FloatingButton alloc] initWithFrame:CGRectMake(20, 150, 55, 55)];
                [w addSubview:floatingButton];
                [ButtonHandler addLog:@"✅ СКАНЕР ЗАГРУЖЕН"];
                [ButtonHandler addLog:@"🔍 Нажми кнопку -> НАЙТИ АДРЕСА"];
            }
        });
    }
}
