#import <UIKit/UIKit.h>
#import <mach/mach.h>
#import <objc/runtime.h>

static NSMutableString *logText = nil;
static UIWindow *logWindow = nil;
static UIButton *floatingButton = nil;
static NSMutableArray *addresses = nil;
static NSMutableArray *values = nil;
static uint64_t scanStart = 0x240000000;
static uint64_t scanEnd = 0x290000000;

@interface ButtonHandler : NSObject
+ (void)showMenu;
+ (void)firstScan;
+ (void)filterChanged;
+ (void)filterIncreased;
+ (void)filterDecreased;
+ (void)filterUnchanged;
+ (void)showResults;
+ (void)showMemoryAround;
+ (void)addLog:(NSString*)text;
+ (void)showLog;
+ (void)hideLog;
+ (void)copyLog;
+ (UIWindow*)mainWindow;
+ (void)closeMenu;
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
    CGFloat w = 250, h = 400;
    UIWindow *menu = [[UIWindow alloc] initWithFrame:CGRectMake((UIScreen.mainScreen.bounds.size.width-w)/2, (UIScreen.mainScreen.bounds.size.height-h)/2, w, h)];
    menu.windowLevel = UIWindowLevelAlert + 3;
    menu.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.95];
    menu.layer.cornerRadius = 10;
    
    __block int y = 20;
    void (^btn)(NSString*, SEL) = ^(NSString *t, SEL s) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(10, y, w-20, 35);
        b.backgroundColor = [UIColor systemBlueColor];
        b.layer.cornerRadius = 6;
        [b setTitle:t forState:UIControlStateNormal];
        [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        [b addTarget:self action:s forControlEvents:UIControlEventTouchUpInside];
        [menu addSubview:b];
        y += 40;
    };
    
    btn(@"🔍 ПЕРВЫЙ СКАН", @selector(firstScan));
    btn(@"📈 УВЕЛИЧИЛОСЬ", @selector(filterIncreased));
    btn(@"📉 УМЕНЬШИЛОСЬ", @selector(filterDecreased));
    btn(@"🔄 ИЗМЕНИЛОСЬ", @selector(filterChanged));
    btn(@"⏸️ НЕ ИЗМЕНИЛОСЬ", @selector(filterUnchanged));
    btn(@"📋 ПОКАЗАТЬ", @selector(showResults));
    btn(@"📌 ПАМЯТЬ", @selector(showMemoryAround));
    btn(@"❌ ЗАКРЫТЬ", @selector(closeMenu));
    
    [menu makeKeyAndVisible];
    objc_setAssociatedObject(self, @selector(closeMenu), menu, OBJC_ASSOCIATION_RETAIN);
}

+ (void)closeMenu {
    UIWindow *menu = objc_getAssociatedObject(self, @selector(closeMenu));
    menu.hidden = YES;
}

+ (void)firstScan {
    addresses = [NSMutableArray array];
    values = [NSMutableArray array];
    
    [self addLog:@"\n🔍 ПЕРВЫЙ СКАН"];
    [self addLog:[NSString stringWithFormat:@"Диапазон: 0x%llx - 0x%llx", scanStart, scanEnd]];
    [self showLog];
    
    task_t task = mach_task_self();
    int count = 0;
    
    // Сканируем блоками по 1000 адресов с паузой
    for (uint64_t addr = scanStart; addr < scanEnd; addr += 4) {
        float val;
        vm_size_t read;
        if (vm_read_overwrite(task, addr, 4, (vm_address_t)&val, &read) == KERN_SUCCESS) {
            [addresses addObject:@(addr)];
            [values addObject:@(val)];
            count++;
        }
        
        // Каждые 10000 адресов обновляем лог и делаем паузу
        if (count % 10000 == 0) {
            [self addLog:[NSString stringWithFormat:@"   Прочитано %d...", count]];
            [self updateLog];
            usleep(1000); // пауза 1ms
        }
        
        // Каждые 100000 адресов даем игре подышать подольше
        if (count % 100000 == 0) {
            usleep(10000); // пауза 10ms
        }
    }
    
    [self addLog:[NSString stringWithFormat:@"✅ Найдено %lu float", (unsigned long)addresses.count]];
    [self showLog];
}

// Добавь эту функцию для обновления лога без открытия
+ (void)updateLog {
    if (logWindow) {
        UITextView *tv = logWindow.subviews.firstObject;
        tv.text = logText;
        // Скроллим вниз
        if (tv.text.length > 0) {
            NSRange bottom = NSMakeRange(tv.text.length - 1, 1);
            [tv scrollRangeToVisible:bottom];
        }
    }
}

+ (void)filterWithBlock:(BOOL(^)(float old, float cur))block {
    if (!addresses) return;
    
    NSMutableArray *newAddr = [NSMutableArray array];
    NSMutableArray *newVal = [NSMutableArray array];
    task_t task = mach_task_self();
    
    for (int i = 0; i < addresses.count; i++) {
        uint64_t addr = [addresses[i] unsignedLongLongValue];
        float cur;
        vm_size_t read;
        if (vm_read_overwrite(task, addr, 4, (vm_address_t)&cur, &read) == KERN_SUCCESS) {
            float old = [values[i] floatValue];
            if (block(old, cur)) {
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

+ (void)filterChanged   { [self filterWithBlock:^BOOL(float o, float c) { return fabs(c-o) > 0.001; }]; }
+ (void)filterUnchanged { [self filterWithBlock:^BOOL(float o, float c) { return fabs(c-o) <= 0.001; }]; }
+ (void)filterIncreased { [self filterWithBlock:^BOOL(float o, float c) { return c > o + 0.001; }]; }
+ (void)filterDecreased { [self filterWithBlock:^BOOL(float o, float c) { return c < o - 0.001; }]; }

+ (void)showResults {
    [self addLog:@"\n📋 РЕЗУЛЬТАТЫ:"];
    for (int i = 0; i < MIN(20, addresses.count); i++) {
        [self addLog:[NSString stringWithFormat:@"%d. 0x%llx = %.3f", i+1, [addresses[i] unsignedLongLongValue], [values[i] floatValue]]];
    }
    [self showLog];
}

+ (void)showMemoryAround {
    if (!addresses || addresses.count == 0) {
        [self addLog:@"❌ Нет адресов для просмотра"];
        [self showLog];
        return;
    }
    
    uint64_t addr = [addresses[0] unsignedLongLongValue];
    addr = addr & ~0xF;
    
    [self addLog:[NSString stringWithFormat:@"\n📌 ПАМЯТЬ ВОКРУГ 0x%llx", addr]];
    [self addLog:@"───────────────────────────────"];
    
    task_t task = mach_task_self();
    uint8_t buffer[128];
    vm_size_t read;
    
    if (vm_read_overwrite(task, addr - 0x40, 128, (vm_address_t)buffer, &read) == KERN_SUCCESS) {
        for (int i = 0; i < 128; i += 16) {
            uint64_t lineAddr = addr - 0x40 + i;
            
            NSMutableString *hex = [NSMutableString string];
            for (int j = 0; j < 16; j++) {
                [hex appendFormat:@"%02x ", buffer[i+j]];
            }
            
            NSMutableString *ascii = [NSMutableString string];
            for (int j = 0; j < 16; j++) {
                char c = buffer[i+j];
                if (c >= 32 && c <= 126) [ascii appendFormat:@"%c", c];
                else [ascii appendString:@"."];
            }
            
            [self addLog:[NSString stringWithFormat:@"0x%08llx: %@ | %@", lineAddr, hex, ascii]];
        }
    } else {
        [self addLog:@"❌ Не удалось прочитать память"];
    }
    
    [self showLog];
}

+ (void)addLog:(NSString*)t {
    if (!logText) logText = [NSMutableString new];
    [logText appendFormat:@"%@\n", t];
    NSLog(@"%@", t);
}

+ (void)showLog {
    if (!logWindow) {
        logWindow = [[UIWindow alloc] initWithFrame:CGRectMake(20, 60, UIScreen.mainScreen.bounds.size.width-40, 450)];
        logWindow.windowLevel = UIWindowLevelAlert + 2;
        logWindow.backgroundColor = [UIColor colorWithWhite:0 alpha:0.95];
        logWindow.layer.cornerRadius = 10;
        
        UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(5, 5, logWindow.bounds.size.width-10, 390)];
        tv.backgroundColor = UIColor.blackColor;
        tv.textColor = UIColor.greenColor;
        tv.font = [UIFont fontWithName:@"Courier" size:10];
        tv.editable = NO;
        [logWindow addSubview:tv];
        
        UIButton *c = [UIButton buttonWithType:UIButtonTypeSystem];
        c.frame = CGRectMake(logWindow.bounds.size.width-100, 405, 80, 30);
        [c setTitle:@"📋 Копировать" forState:UIControlStateNormal];
        [c setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        c.backgroundColor = UIColor.systemBlueColor;
        c.layer.cornerRadius = 6;
        [c addTarget:self action:@selector(copyLog) forControlEvents:UIControlEventTouchUpInside];
        [logWindow addSubview:c];
        
        UIButton *x = [UIButton buttonWithType:UIButtonTypeSystem];
        x.frame = CGRectMake(20, 405, 50, 30);
        [x setTitle:@"✖️" forState:UIControlStateNormal];
        [x setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        x.backgroundColor = UIColor.systemRedColor;
        x.layer.cornerRadius = 6;
        [x addTarget:self action:@selector(hideLog) forControlEvents:UIControlEventTouchUpInside];
        [logWindow addSubview:x];
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
