#import <UIKit/UIKit.h>
#import <mach/mach.h>

// ===== ГЛОБАЛЬНЫЕ =====
static UIWindow *win = nil;
static UITextView *logView = nil;
static NSMutableString *logText = nil;
static uintptr_t g_myTransform = 0;
static uintptr_t g_arrayStart = 0;

void addLog(NSString *msg) {
    if (!logText) logText = [[NSMutableString alloc] init];
    [logText appendString:msg];
    [logText appendString:@"\n"];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (logView) logView.text = logText;
    });
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

// ===== ПОИСК ID =====
void findMyTransform() {
    addLog(@"🔍 ПОИСК ID 71068432...");
    
    uintptr_t idAddr = 0;
    for (uintptr_t addr = 0x110000000; addr < 0x180000000; addr += 4) {
        if (addr % 0x1000000 == 0) {
            addLog([NSString stringWithFormat:@"   Сканирую 0x%lx...", addr]);
        }
        int val = readInt(addr);
        if (val == 71068432) {
            idAddr = addr;
            addLog([NSString stringWithFormat:@"✅ ID найден: 0x%lx", idAddr]);
            break;
        }
    }
    
    if (!idAddr) {
        addLog(@"❌ ID не найден");
        return;
    }
    
    uintptr_t quark = idAddr - 0x10;
    addLog([NSString stringWithFormat:@"QuarkRoomPlayer: 0x%lx", quark]);
    
    int isWasted = readInt(quark + 0x7A);
    addLog([NSString stringWithFormat:@"IsWasted: %d", isWasted]);
    if (isWasted != 0) {
        addLog(@"⚠️ Мертв, ищу живого...");
        return;
    }
    
    // Ищем NetworkPlayer
    for (int offset = 0x1A8; offset <= 0x1C0; offset += 8) {
        uintptr_t network = quark - offset;
        uintptr_t transform = readPtr(network + 0x58);
        if (transform > 0x100000000) {
            float x = readFloat(transform);
            float y = readFloat(transform + 4);
            float z = readFloat(transform + 8);
            if (y > 0.5 && y < 20) {
                addLog([NSString stringWithFormat:@"✅ NetworkPlayer: 0x%lx (offset +0x%x)", network, offset]);
                addLog([NSString stringWithFormat:@"✅ Transform: 0x%lx", transform]);
                addLog([NSString stringWithFormat:@"📍 Координаты: X=%.2f Y=%.2f Z=%.2f", x, y, z]);
                g_myTransform = transform;
                break;
            }
        }
    }
    
    if (!g_myTransform) {
        addLog(@"❌ Transform не найден");
        return;
    }
    
    // Находим начало массива
    addLog(@"\n🔍 ИЩУ НАЧАЛО МАССИВА...");
    uintptr_t start = g_myTransform;
    while (1) {
        uintptr_t test = start - 0x20;
        float y = readFloat(test + 4);
        if (y < -100 || y > 100) break;
        start = test;
    }
    g_arrayStart = start;
    addLog([NSString stringWithFormat:@"✅ Начало массива: 0x%lx", g_arrayStart]);
    
    // Сканируем игроков
    addLog(@"\n👥 ИГРОКИ НА КАРТЕ:");
    int found = 0;
    for (int i = 0; i < 100; i++) {
        uintptr_t addr = g_arrayStart + i * 0x20;
        float x = readFloat(addr);
        float y = readFloat(addr + 4);
        float z = readFloat(addr + 8);
        
        if (y > 0.5 && y < 20 && x > -200 && x < 200 && z > -200 && z < 200) {
            if (addr == g_myTransform) {
                addLog([NSString stringWithFormat:@"   🎯 ТЫ: X=%.1f Y=%.1f Z=%.1f", x, y, z]);
            } else {
                addLog([NSString stringWithFormat:@"   👤 ИГРОК: X=%.1f Y=%.1f Z=%.1f", x, y, z]);
                found++;
            }
        }
    }
    addLog([NSString stringWithFormat:@"\n✅ Найдено врагов: %d", found]);
    addLog(@"\n🎯 ГОТОВО!");
}

// ===== МЕНЮ =====
void showMenu() {
    UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"ESP FINDER" message:@"Нажми НАЙТИ" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"🔍 НАЙТИ" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            findMyTransform();
        });
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"📋 КОПИ" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        pasteboard.string = logText;
        addLog(@"📋 Лог скопирован");
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"🗑 ОЧИСТИТЬ" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        logText = nil;
        addLog(@"Лог очищен");
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"ЗАКРЫТЬ" style:UIAlertActionStyleCancel handler:nil]];
    [root presentViewController:alert animated:YES completion:nil];
}

// ===== КНОПКА =====
@interface ESPButton : UIButton @end
@implementation ESPButton
- (void)buttonTapped {
    showMenu();
}
@end

__attribute__((constructor)) void init() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
        if (!keyWindow) return;
        
        // Кнопка
        UIButton *btn = [ESPButton buttonWithType:UIButtonTypeSystem];
        btn.frame = CGRectMake(20, 80, 60, 60);
        btn.backgroundColor = [UIColor systemBlueColor];
        btn.layer.cornerRadius = 30;
        [btn setTitle:@"🎯" forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:28];
        [btn addTarget:btn action:@selector(buttonTapped) forControlEvents:UIControlEventTouchUpInside];
        [keyWindow addSubview:btn];
        
        // Лог-окно
        UIView *logBg = [[UIView alloc] initWithFrame:CGRectMake(20, 150, keyWindow.frame.size.width - 40, 300)];
        logBg.backgroundColor = [UIColor colorWithWhite:0 alpha:0.85];
        logBg.layer.cornerRadius = 12;
        [keyWindow addSubview:logBg];
        
        logView = [[UITextView alloc] initWithFrame:CGRectMake(10, 5, logBg.frame.size.width - 20, 280)];
        logView.backgroundColor = [UIColor clearColor];
        logView.textColor = [UIColor whiteColor];
        logView.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
        logView.editable = NO;
        [logBg addSubview:logView];
        
        addLog(@"🎯 ESP FINDER READY");
        addLog(@"Нажми кнопку 🎯 и выбери НАЙТИ");
    });
}
