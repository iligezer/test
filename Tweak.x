#import <UIKit/UIKit.h>
#import <mach/mach.h>

// ===== ГЛОБАЛЬНЫЕ =====
static UIWindow *win = nil;
static UITextView *logView = nil;
static NSMutableString *logText = nil;
static UIButton *findBtn = nil;
static BOOL isSearching = NO;
static uintptr_t g_myTransform = 0;
static uintptr_t g_arrayStart = 0;

void addLog(NSString *msg) {
    if (!logText) logText = [[NSMutableString alloc] init];
    [logText appendString:msg];
    [logText appendString:@"\n"];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (logView) logView.text = logText;
        // Автоскролл вниз
        if (logView.text.length > 0) {
            NSRange bottom = NSMakeRange(logView.text.length - 1, 1);
            [logView scrollRangeToVisible:bottom];
        }
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

// ===== ПОИСК =====
void findPlayers() {
    if (isSearching) return;
    isSearching = YES;
    addLog(@"🔍 ПОИСК ID 71068432...");
    
    uintptr_t idAddr = 0;
    int scanned = 0;
    for (uintptr_t addr = 0x110000000; addr < 0x180000000; addr += 4) {
        scanned++;
        if (scanned % 500000 == 0) {
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
        isSearching = NO;
        return;
    }
    
    uintptr_t quark = idAddr - 0x10;
    addLog([NSString stringWithFormat:@"QuarkRoomPlayer: 0x%lx", quark]);
    
    int isWasted = readInt(quark + 0x7A);
    addLog([NSString stringWithFormat:@"IsWasted: %d", isWasted]);
    
    // Ищем NetworkPlayer
    addLog(@"\n🔍 ИЩУ NETWORKPLAYER...");
    int foundTransform = 0;
    for (int offset = 0x1A8; offset <= 0x1C0; offset += 8) {
        uintptr_t network = quark - offset;
        uintptr_t transform = readPtr(network + 0x58);
        if (transform > 0x100000000) {
            float x = readFloat(transform);
            float y = readFloat(transform + 4);
            float z = readFloat(transform + 8);
            if (y > 0.5 && y < 20) {
                addLog([NSString stringWithFormat:@"✅ Найден! Смещение 0x%x", offset]);
                addLog([NSString stringWithFormat:@"   NetworkPlayer: 0x%lx", network]);
                addLog([NSString stringWithFormat:@"   Transform: 0x%lx", transform]);
                addLog([NSString stringWithFormat:@"   Координаты: X=%.2f Y=%.2f Z=%.2f", x, y, z]);
                g_myTransform = transform;
                foundTransform = 1;
                break;
            }
        }
    }
    
    if (!foundTransform) {
        addLog(@"❌ Transform не найден");
        isSearching = NO;
        return;
    }
    
    // Находим начало массива
    addLog(@"\n🔍 ИЩУ НАЧАЛО МАССИВА...");
    uintptr_t start = g_myTransform;
    int steps = 0;
    while (1) {
        uintptr_t test = start - 0x20;
        float y = readFloat(test + 4);
        if (y < -100 || y > 100) break;
        start = test;
        steps++;
        if (steps % 10 == 0) {
            addLog([NSString stringWithFormat:@"   Проверено %d шагов...", steps]);
        }
    }
    g_arrayStart = start;
    addLog([NSString stringWithFormat:@"✅ Начало массива: 0x%lx", g_arrayStart]);
    
    // Сканируем игроков
    addLog(@"\n👥 ИГРОКИ НА КАРТЕ:");
    int enemyCount = 0;
    for (int i = 0; i < 100; i++) {
        uintptr_t addr = g_arrayStart + i * 0x20;
        float x = readFloat(addr);
        float y = readFloat(addr + 4);
        float z = readFloat(addr + 8);
        
        if (y > 0.5 && y < 20 && x > -200 && x < 200 && z > -200 && z < 200) {
            if (addr == g_myTransform) {
                addLog([NSString stringWithFormat:@"   🎯 ТЫ: X=%.1f Y=%.1f Z=%.1f", x, y, z]);
            } else {
                addLog([NSString stringWithFormat:@"   👤 ВРАГ: X=%.1f Y=%.1f Z=%.1f", x, y, z]);
                enemyCount++;
            }
        }
    }
    addLog([NSString stringWithFormat:@"\n✅ Найдено врагов: %d", enemyCount]);
    addLog(@"\n🎯 ГОТОВО!");
    isSearching = NO;
}

// ===== КНОПКИ =====
void setupUI() {
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    if (!keyWindow) return;
    
    // Плавающая кнопка 🎯
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.frame = CGRectMake(20, 80, 55, 55);
    btn.backgroundColor = [UIColor systemBlueColor];
    btn.layer.cornerRadius = 27.5;
    [btn setTitle:@"🎯" forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:26];
    [btn addTarget:self action:@selector(onFindTap) forControlEvents:UIControlEventTouchUpInside];
    [keyWindow addSubview:btn];
    
    // Кнопка очистки 🗑
    UIButton *clearBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    clearBtn.frame = CGRectMake(20, 145, 55, 40);
    clearBtn.backgroundColor = [UIColor systemGrayColor];
    clearBtn.layer.cornerRadius = 8;
    [clearBtn setTitle:@"🗑" forState:UIControlStateNormal];
    [clearBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    clearBtn.titleLabel.font = [UIFont systemFontOfSize:20];
    [clearBtn addTarget:self action:@selector(onClearTap) forControlEvents:UIControlEventTouchUpInside];
    [keyWindow addSubview:clearBtn];
    
    // Лог-окно
    UIView *logBg = [[UIView alloc] initWithFrame:CGRectMake(20, 195, keyWindow.frame.size.width - 40, keyWindow.frame.size.height - 215)];
    logBg.backgroundColor = [UIColor colorWithWhite:0 alpha:0.85];
    logBg.layer.cornerRadius = 12;
    [keyWindow addSubview:logBg];
    
    logView = [[UITextView alloc] initWithFrame:CGRectMake(8, 5, logBg.frame.size.width - 16, logBg.frame.size.height - 10)];
    logView.backgroundColor = [UIColor clearColor];
    logView.textColor = [UIColor whiteColor];
    logView.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    logView.editable = NO;
    [logBg addSubview:logView];
    
    addLog(@"🎯 ESP FINDER READY");
    addLog(@"Нажми 🎯 для поиска игроков");
}

void onFindTap() {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        findPlayers();
    });
}

void onClearTap() {
    logText = nil;
    addLog(@"🗑 Лог очищен");
    addLog(@"🎯 ESP FINDER READY");
    addLog(@"Нажми 🎯 для поиска игроков");
}

__attribute__((constructor)) void init() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        setupUI();
    });
}
