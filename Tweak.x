#import <UIKit/UIKit.h>
#import <mach/mach.h>

// ===== ГЛОБАЛЬНЫЕ =====
static NSMutableString *logText = nil;
static BOOL isSearching = NO;
static uintptr_t g_myTransform = 0;
static uintptr_t g_arrayStart = 0;

void addLog(NSString *msg) {
    if (!logText) logText = [[NSMutableString alloc] init];
    [logText appendString:msg];
    [logText appendString:@"\n"];
}

uintptr_t readPtr(uintptr_t addr) {
    if (addr == 0) return 0;
    uintptr_t val = 0;
    vm_size_t outSize = 0;
    vm_read_overwrite(mach_task_self(), addr, sizeof(val), (vm_address_t)&val, &outSize);
    return val;
}

int readInt(uintptr_t addr) {
    if (addr == 0) return 0;
    int val = 0;
    vm_size_t outSize = 0;
    vm_read_overwrite(mach_task_self(), addr, sizeof(val), (vm_address_t)&val, &outSize);
    return val;
}

float readFloat(uintptr_t addr) {
    if (addr == 0) return 0;
    float val = 0;
    vm_size_t outSize = 0;
    vm_read_overwrite(mach_task_self(), addr, sizeof(val), (vm_address_t)&val, &outSize);
    return val;
}

void findPlayers() {
    if (isSearching) return;
    isSearching = YES;
    addLog(@"🔍 ПОИСК ID...");
    
    uintptr_t idAddr = 0;
    for (uintptr_t addr = 0x110000000; addr < 0x180000000; addr += 4) {
        int val = readInt(addr);
        if (val == 71068432) {
            idAddr = addr;
            addLog([NSString stringWithFormat:@"✅ ID: 0x%lx", idAddr]);
            break;
        }
    }
    
    if (!idAddr) {
        addLog(@"❌ ID не найден");
        isSearching = NO;
        return;
    }
    
    uintptr_t quark = idAddr - 0x10;
    for (int offset = 0x1A8; offset <= 0x1C0; offset += 8) {
        uintptr_t network = quark - offset;
        uintptr_t transform = readPtr(network + 0x58);
        if (transform > 0x100000000) {
            float y = readFloat(transform + 4);
            if (y > 0.5 && y < 20) {
                addLog([NSString stringWithFormat:@"✅ Transform: 0x%lx", transform]);
                g_myTransform = transform;
                break;
            }
        }
    }
    
    if (!g_myTransform) {
        addLog(@"❌ Transform не найден");
        isSearching = NO;
        return;
    }
    
    uintptr_t start = g_myTransform;
    while (1) {
        uintptr_t test = start - 0x20;
        float y = readFloat(test + 4);
        if (y < -100 || y > 100) break;
        start = test;
    }
    g_arrayStart = start;
    addLog([NSString stringWithFormat:@"✅ Массив: 0x%lx", g_arrayStart]);
    
    int enemyCount = 0;
    for (int i = 0; i < 100; i++) {
        uintptr_t addr = g_arrayStart + i * 0x20;
        float x = readFloat(addr);
        float y = readFloat(addr + 4);
        
        if (y > 0.5 && y < 20 && x > -200 && x < 200) {
            if (addr != g_myTransform) {
                enemyCount++;
            }
        }
    }
    addLog([NSString stringWithFormat:@"✅ Врагов: %d", enemyCount]);
    isSearching = NO;
}

void showMenu() {
    UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"ESP FINDER" message:logText preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"🔍 НАЙТИ" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        logText = nil;
        addLog(@"Поиск...");
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            findPlayers();
            dispatch_async(dispatch_get_main_queue(), ^{
                showMenu();
            });
        });
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"📋 КОПИ" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        pasteboard.string = logText;
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"ЗАКРЫТЬ" style:UIAlertActionStyleCancel handler:nil]];
    [root presentViewController:alert animated:YES completion:nil];
}

__attribute__((constructor)) void init() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
        if (!keyWindow) return;
        
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.frame = CGRectMake(20, 80, 55, 55);
        btn.backgroundColor = [UIColor systemBlueColor];
        btn.layer.cornerRadius = 27.5;
        [btn setTitle:@"🎯" forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:26];
        [btn addTarget:btn action:@selector(showMenu) forControlEvents:UIControlEventTouchUpInside];
        [keyWindow addSubview:btn];
    });
}
