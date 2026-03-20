#import <UIKit/UIKit.h>
#import <mach/mach.h>
#import <objc/runtime.h>

// ========== НАСТРОЙКИ ==========
#define SCAN_START 0x240000000
#define SCAN_END   0x290000000

static NSMutableString *logText = nil;
static UIWindow *logWindow = nil;
static UIButton *floatingButton = nil;
static NSMutableArray *addresses = nil;
static NSMutableArray *values = nil;
static BOOL isScanning = NO;

@interface ButtonHandler : NSObject
+ (void)showMenu;
+ (void)startFullScan;
+ (void)filterChanged;
+ (void)filterUnchanged;
+ (void)showResults;
+ (void)showMemoryAround;
+ (void)resetScan;
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
    [self setTitle:@"🔍" forState:UIControlStateNormal];
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
    CGFloat w = 260, h = 350;
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
    
    btn(@"🔍 ПОЛНЫЙ СКАН", @selector(startFullScan), UIColor.systemBlueColor);
    btn(@"📈 ИЗМЕНИЛОСЬ", @selector(filterChanged), UIColor.systemOrangeColor);
    btn(@"⏸️ НЕ ИЗМЕНИЛОСЬ", @selector(filterUnchanged), UIColor.systemGrayColor);
    btn(@"📋 РЕЗУЛЬТАТЫ", @selector(showResults), UIColor.systemPurpleColor);
    btn(@"📌 ПАМЯТЬ", @selector(showMemoryAround), UIColor.systemTealColor);
    btn(@"🔄 СБРОС", @selector(resetScan), UIColor.systemRedColor);
    btn(@"❌ ЗАКРЫТЬ", @selector(closeMenu), UIColor.systemRedColor);
    
    [menu makeKeyAndVisible];
    objc_setAssociatedObject(self, @selector(closeMenu), menu, OBJC_ASSOCIATION_RETAIN);
}

+ (void)closeMenu {
    UIWindow *menu = objc_getAssociatedObject(self, @selector(closeMenu));
    menu.hidden = YES;
}

+ (void)startFullScan {
    if (isScanning) {
        [self addLog:@"⏳ Сканирование уже идет..."];
        return;
    }
    
    addresses = [NSMutableArray array];
    values = [NSMutableArray array];
    isScanning = YES;
    
    [self addLog:@"\n🔍 ПОЛНЫЙ СКАН (автоматически)"];
    [self addLog:[NSString stringWithFormat:@"Диапазон: 0x%llx - 0x%llx", SCAN_START, SCAN_END]];
    [self showLog];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        task_t task = mach_task_self();
        int total = 0;
        int chunkSize = 0x400000; // 4 МБ за раз
        
        for (uint64_t addr = SCAN_START; addr < SCAN_END; addr += chunkSize) {
            if (!isScanning) break;
            
            uint64_t chunkEnd = addr + chunkSize;
            if (chunkEnd > SCAN_END) chunkEnd = SCAN_END;
            
            for (uint64_t a = addr; a < chunkEnd; a += 4) {
                float val;
                vm_size_t read;
                if (vm_read_overwrite(task, a, 4, (vm_address_t)&val, &read) == KERN_SUCCESS) {
                    [addresses addObject:@(a)];
                    [values addObject:@(val)];
                    total++;
                }
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [self addLog:[NSString stringWithFormat:@"📊 Прочитано %d float...", total]];
                [self updateLog];
            });
            
            usleep(10000); // пауза 10ms между чанками
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            isScanning = NO;
            [self addLog:[NSString stringWithFormat:@"✅ ГОТОВО: %lu float", (unsigned long)addresses.count]];
            [self showLog];
        });
    });
}

+ (void)filterChanged {
    if (!addresses || addresses.count == 0) return;
    
    NSMutableArray *newAddr = [NSMutableArray array];
    NSMutableArray *newVal = [NSMutableArray array];
    task_t task = mach_task_self();
    
    for (int i = 0; i < addresses.count; i++) {
        uint64_t addr = [addresses[i] unsignedLongLongValue];
        float cur;
        vm_size_t read;
        if (vm_read_overwrite(task, addr, 4, (vm_address_t)&cur, &read) == KERN_SUCCESS) {
            float old = [values[i] floatValue];
            if (fabs(cur - old) > 0.001) {
                [newAddr addObject:@(addr)];
                [newVal addObject:@(cur)];
            }
        }
    }
    
    addresses = newAddr;
    values = newVal;
    [self addLog:[NSString stringWithFormat:@"📊 Осталось %lu", (unsigned long)addresses.count]];
    [self showLog];
}

+ (void)filterUnchanged {
    if (!addresses || addresses.count == 0) return;
    
    NSMutableArray *newAddr = [NSMutableArray array];
    NSMutableArray *newVal = [NSMutableArray array];
    task_t task = mach_task_self();
    
    for (int i = 0; i < addresses.count; i++) {
        uint64_t addr = [addresses[i] unsignedLongLongValue];
        float cur;
        vm_size_t read;
        if (vm_read_overwrite(task, addr, 4, (vm_address_t)&cur, &read) == KERN_SUCCESS) {
            float old = [values[i] floatValue];
            if (fabs(cur - old) <= 0.001) {
                [newAddr addObject:@(addr)];
                [newVal addObject:@(cur)];
            }
        }
    }
    
    addresses = newAddr;
    values = newVal;
    [self addLog:[NSString stringWithFormat:@"📊 Осталось %lu", (unsigned long)addresses.count]];
    [self showLog];
}

+ (void)showResults {
    [self addLog:@"\n📋 РЕЗУЛЬТАТЫ:"];
    for (int i = 0; i < MIN(20, addresses.count); i++) {
        [self addLog:[NSString stringWithFormat:@"%d. 0x%llx = %.3f", i+1, [addresses[i] unsignedLongLongValue], [values[i] floatValue]]];
    }
    [self showLog];
}

+ (void)showMemoryAround {
    if (!addresses || addresses.count == 0) {
        [self addLog:@"❌ Нет адресов"];
        [self showLog];
        return;
    }
    
    uint64_t addr = [addresses[0] unsignedLongLongValue];
    addr = addr & ~0xF;
    
    [self addLog:[NSString stringWithFormat:@"\n📌 ПАМЯТЬ ВОКРУГ 0x%llx", addr]];
    
    task_t task = mach_task_self();
    uint8_t buffer[128];
    vm_size_t read;
    
    if (vm_read_overwrite(task, addr - 0x40, 128, (vm_address_t)buffer, &read) == KERN_SUCCESS) {
        for (int i = 0; i < 128; i += 16) {
            uint64_t lineAddr = addr - 0x40 + i;
            NSMutableString *hex = [NSMutableString string];
            for (int j = 0; j < 16; j++) [hex appendFormat:@"%02x ", buffer[i+j]];
            [self addLog:[NSString stringWithFormat:@"0x%08llx: %@", lineAddr, hex]];
        }
    } else {
        [self addLog:@"❌ Ошибка чтения"];
    }
    [self showLog];
}

+ (void)resetScan {
    [addresses removeAllObjects];
    [values removeAllObjects];
    isScanning = NO;
    [self addLog:@"🔄 СБРОШЕНО"];
    [self showLog];
}

+ (void)addLog:(NSString*)t {
    if (!logText) logText = [NSMutableString new];
    [logText appendFormat:@"%@\n", t];
    NSLog(@"%@", t);
}

+ (void)updateLog {
    if (logWindow) {
        UITextView *tv = logWindow.subviews.firstObject;
        tv.text = logText;
        if (tv.text.length > 0) {
            NSRange bottom = NSMakeRange(tv.text.length - 1, 1);
            [tv scrollRangeToVisible:bottom];
        }
    }
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

__attribute__((constructor)) static void init() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        UIWindow *w = [ButtonHandler mainWindow];
        if (w) {
            floatingButton = [[FloatingButton alloc] initWithFrame:CGRectMake(20, 150, 50, 50)];
            [w addSubview:floatingButton];
        }
    });
}
