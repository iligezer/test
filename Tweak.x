#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <substrate.h>

// ==================== СМЕЩЕНИЯ ИЗ IDA ====================
#define UTILITIES_TYPEINFO_RVA          0x8E15248
#define STATIC_FIELDS_RVA               0x8D87678
#define GET_PLAYERCONTROLLER_RVA        0x32494cc
#define CAMERA_GET_MAIN_RVA             0x445baf8
#define WORLD_TO_SCREEN_POINT_RVA       0x445a9cc

// Кандидаты смещений _playerController
#define PLAYER_OFFSET_CANDIDATES {0x28, 0x30, 0x38, 0x40, 0x48, 0x50, 0x58, 0x60}

// Кандидаты смещений позиции
#define POS_OFFSET_CANDIDATES {0x20, 0x38, 0x158, 0x15C, 0x160, 0x170, 0x174, 0x178}

// ==================== ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ====================

uintptr_t getBase() {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char* name = _dyld_get_image_name(i);
        if (strstr(name, "UnityFramework")) {
            return (uintptr_t)_dyld_get_image_header(i);
        }
    }
    return 0;
}

struct Vector3 {
    float x, y, z;
};

// ==================== КЛАСС МЕНЮ ====================

@interface ESPMenu : NSObject
+ (void)setup;
@end

@implementation ESPMenu

static UIButton *menuButton = nil;
static UIView *menuView = nil;
static UITextView *infoText = nil;
static BOOL isMenuVisible = NO;
static uintptr_t cachedBase = 0;

+ (NSString *)scanAll {
    NSMutableString *result = [NSMutableString string];
    
    // 1. Найти базу
    uintptr_t base = getBase();
    [result appendFormat:@"🔍 ПОИСК БАЗЫ:\n"];
    [result appendFormat:@"   getBase() = 0x%llx", (unsigned long long)base];
    
    if (base == 0) {
        [result appendString:@" ❌ НЕ НАЙДЕНА!\n\n"];
        [result appendString:@"💡 База не найдена через _dyld_get_image_name\n"];
        [result appendString:@"   Возможно, нужно указать другое имя модуля\n"];
        return result;
    }
    [result appendString:@" ✅\n\n"];
    cachedBase = base;
    
    // 2. Проверить TypeInfo
    [result appendFormat:@"📦 Utilities TypeInfo:\n"];
    uintptr_t typeInfoAddr = base + UTILITIES_TYPEINFO_RVA;
    uintptr_t typeInfo = *(uintptr_t *)typeInfoAddr;
    [result appendFormat:@"   RVA: 0x%llx\n", (unsigned long long)UTILITIES_TYPEINFO_RVA];
    [result appendFormat:@"   Адрес: 0x%llx\n", (unsigned long long)typeInfoAddr];
    [result appendFormat:@"   Значение: 0x%llx", (unsigned long long)typeInfo];
    
    if (typeInfo == 0 || typeInfo < base || typeInfo > base + 0x20000000) {
        [result appendString:@" ❌ НЕВАЛИДНЫЙ!\n\n"];
        [result appendString:@"⚠️ TypeInfo невалидный — база может быть неправильной\n"];
        return result;
    }
    [result appendString:@" ✅\n\n"];
    
    // 3. static_fields
    [result appendFormat:@"📁 static_fields:\n"];
    uintptr_t staticFields = *(uintptr_t *)(typeInfo + 0x08);
    [result appendFormat:@"   Адрес: 0x%llx\n", (unsigned long long)(typeInfo + 0x08)];
    [result appendFormat:@"   Значение: 0x%llx", (unsigned long long)staticFields];
    
    if (staticFields == 0 || staticFields < base || staticFields > base + 0x20000000) {
        [result appendString:@" ❌ НЕВАЛИДНЫЙ!\n\n"];
        return result;
    }
    [result appendString:@" ✅\n\n"];
    
    // 4. Проверка _playerController кандидатов
    [result appendString:@"👤 ПОИСК _playerController:\n"];
    int playerOffsets[] = PLAYER_OFFSET_CANDIDATES;
    int playerOffsetsCount = sizeof(playerOffsets) / sizeof(int);
    
    BOOL foundPlayer = NO;
    for (int i = 0; i < playerOffsetsCount; i++) {
        int offset = playerOffsets[i];
        uintptr_t player = *(uintptr_t *)(staticFields + offset);
        [result appendFormat:@"   [+0x%02x] = 0x%llx", offset, (unsigned long long)player];
        
        if (player != 0 && player > base && player < base + 0x20000000) {
            [result appendString:@" ✅"];
            foundPlayer = YES;
            
            // Пробуем прочитать позицию по разным смещениям
            int posOffsets[] = POS_OFFSET_CANDIDATES;
            int posCount = sizeof(posOffsets) / sizeof(int);
            
            for (int j = 0; j < posCount; j += 3) {
                if (j + 2 >= posCount) break;
                int offX = posOffsets[j];
                int offY = posOffsets[j+1];
                int offZ = posOffsets[j+2];
                
                float x = *(float *)(player + offX);
                float y = *(float *)(player + offY);
                float z = *(float *)(player + offZ);
                
                if (fabs(x) < 5000 && fabs(y) < 5000 && fabs(z) < 5000 && (x != 0 || y != 0 || z != 0)) {
                    [result appendFormat:@"\n      🎯 pos[0x%02x,0x%02x,0x%02x]: (%.2f, %.2f, %.2f) ✅", 
                     offX, offY, offZ, x, y, z];
                } else if (x != 0 || y != 0 || z != 0) {
                    [result appendFormat:@"\n      pos[0x%02x,0x%02x,0x%02x]: (%.2f, %.2f, %.2f)", 
                     offX, offY, offZ, x, y, z];
                }
            }
        } else {
            [result appendString:@" ❌"];
        }
        [result appendString:@"\n"];
    }
    
    if (!foundPlayer) {
        [result appendString:@"   ❌ НИ ОДИН КАНДИДАТ НЕ ДАЛ УКАЗАТЕЛЬ!\n"];
    }
    
    // 5. Информация о функциях
    [result appendString:@"\n🎥 ФУНКЦИИ (RVA из script.json):\n"];
    [result appendFormat:@"   Camera.get_main RVA: 0x%llx\n", (unsigned long long)CAMERA_GET_MAIN_RVA];
    [result appendFormat:@"   WorldToScreenPoint RVA: 0x%llx\n", (unsigned long long)WORLD_TO_SCREEN_POINT_RVA];
    [result appendFormat:@"   get_PlayerController RVA: 0x%llx\n", (unsigned long long)GET_PLAYERCONTROLLER_RVA];
    
    // 6. Проверка адреса get_PlayerController
    uintptr_t getPlayerAddr = base + GET_PLAYERCONTROLLER_RVA;
    uint32_t firstInstr = *(uint32_t *)getPlayerAddr;
    [result appendFormat:@"\n🔧 get_PlayerController @ 0x%llx\n", (unsigned long long)getPlayerAddr];
    [result appendFormat:@"   первая инструкция: 0x%08x", firstInstr];
    if (firstInstr == 0xa9bf6bfd) {
        [result appendString:@" ✅ (STP X29, X30) — похоже на функцию!\n"];
    } else {
        [result appendString:@" ⚠️ (не STP, возможно не та функция)\n"];
    }
    
    return result;
}

+ (void)copyToClipboard:(NSString *)text {
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    pasteboard.string = text;
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"✅ Скопировано!" 
                                                                   message:@"Текст скопирован в буфер обмена" 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    [rootVC presentViewController:alert animated:YES completion:nil];
}

+ (void)showScanResults {
    NSString *results = [self scanAll];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🔍 СКАНИРОВАНИЕ" 
                                                                   message:results 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    // Кнопка копирования
    [alert addAction:[UIAlertAction actionWithTitle:@"📋 Копировать" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self copyToClipboard:results];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    
    UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    [rootVC presentViewController:alert animated:YES completion:nil];
    
    // Обновляем текстовое поле
    if (infoText) {
        infoText.text = results;
    }
}

+ (void)showCurrentPosition {
    NSMutableString *result = [NSMutableString string];
    
    uintptr_t base = getBase();
    if (base == 0) {
        [result appendString:@"❌ База не найдена!\n"];
        [self copyToClipboard:result];
        return;
    }
    
    uintptr_t typeInfo = *(uintptr_t *)(base + UTILITIES_TYPEINFO_RVA);
    if (typeInfo == 0) {
        [result appendString:@"❌ TypeInfo не найден!\n"];
        [self copyToClipboard:result];
        return;
    }
    
    uintptr_t staticFields = *(uintptr_t *)(typeInfo + 0x08);
    if (staticFields == 0) {
        [result appendString:@"❌ static_fields не найден!\n"];
        [self copyToClipboard:result];
        return;
    }
    
    [result appendFormat:@"База: 0x%llx\n", (unsigned long long)base];
    [result appendFormat:@"static_fields: 0x%llx\n\n", (unsigned long long)staticFields];
    
    int playerOffsets[] = PLAYER_OFFSET_CANDIDATES;
    int playerOffsetsCount = sizeof(playerOffsets) / sizeof(int);
    
    for (int i = 0; i < playerOffsetsCount; i++) {
        int offset = playerOffsets[i];
        uintptr_t player = *(uintptr_t *)(staticFields + offset);
        
        if (player != 0 && player > base && player < base + 0x20000000) {
            [result appendFormat:@"[+0x%02x] player: 0x%llx\n", offset, (unsigned long long)player];
            
            // Проверяем разные смещения позиции
            float x158 = *(float *)(player + 0x158);
            float y158 = *(float *)(player + 0x15C);
            float z158 = *(float *)(player + 0x160);
            
            float x20 = *(float *)(player + 0x20);
            float y20 = *(float *)(player + 0x24);
            float z20 = *(float *)(player + 0x28);
            
            float x38 = *(float *)(player + 0x38);
            float y38 = *(float *)(player + 0x3C);
            float z38 = *(float *)(player + 0x40);
            
            [result appendFormat:@"   pos(0x158): (%.2f, %.2f, %.2f)\n", x158, y158, z158];
            [result appendFormat:@"   pos(0x20):  (%.2f, %.2f, %.2f)\n", x20, y20, z20];
            [result appendFormat:@"   pos(0x38):  (%.2f, %.2f, %.2f)\n\n", x38, y38, z38];
        }
    }
    
    [self copyToClipboard:result];
}

+ (void)toggleMenu {
    isMenuVisible = !isMenuVisible;
    menuView.hidden = !isMenuVisible;
}

+ (void)dragButton:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:menuButton.superview];
    CGPoint newCenter = CGPointMake(menuButton.center.x + translation.x, menuButton.center.y + translation.y);
    
    CGFloat halfWidth = menuButton.frame.size.width / 2;
    CGFloat halfHeight = menuButton.frame.size.height / 2;
    newCenter.x = MAX(halfWidth, MIN(newCenter.x, menuButton.superview.bounds.size.width - halfWidth));
    newCenter.y = MAX(halfHeight, MIN(newCenter.y, menuButton.superview.bounds.size.height - halfHeight));
    
    menuButton.center = newCenter;
    [gesture setTranslation:CGPointZero inView:menuButton.superview];
    
    CGRect frame = menuView.frame;
    frame.origin.x = menuButton.frame.origin.x;
    frame.origin.y = menuButton.frame.origin.y + menuButton.frame.size.height + 5;
    menuView.frame = frame;
}

+ (void)setup {
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    if (!keyWindow) return;
    
    // Кнопка
    menuButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    menuButton.frame = CGRectMake(keyWindow.bounds.size.width - 70, 60, 50, 50);
    menuButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.5 blue:1.0 alpha:0.9];
    menuButton.layer.cornerRadius = 25;
    [menuButton setTitle:@"⚡" forState:UIControlStateNormal];
    [menuButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    menuButton.titleLabel.font = [UIFont boldSystemFontOfSize:24];
    [menuButton addTarget:[ESPMenu class] action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:[ESPMenu class] action:@selector(dragButton:)];
    [menuButton addGestureRecognizer:pan];
    [keyWindow addSubview:menuButton];
    
    // Меню
    menuView = [[UIView alloc] initWithFrame:CGRectMake(menuButton.frame.origin.x, menuButton.frame.origin.y + 55, 330, 350)];
    menuView.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.05 alpha:0.95];
    menuView.layer.cornerRadius = 12;
    menuView.layer.borderWidth = 0.5;
    menuView.layer.borderColor = [UIColor colorWithRed:0.3 green:0.3 blue:0.3 alpha:1].CGColor;
    menuView.hidden = YES;
    menuView.userInteractionEnabled = YES;
    
    // Заголовок
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 8, 330, 28)];
    title.text = @"Modern Strike ESP Scanner";
    title.textColor = [UIColor whiteColor];
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:14];
    [menuView addSubview:title];
    
    // Кнопка сканирования
    UIButton *scanBtn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    scanBtn.frame = CGRectMake(10, 45, 310, 40);
    scanBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.5 blue:0.8 alpha:1];
    scanBtn.layer.cornerRadius = 8;
    [scanBtn setTitle:@"🔍 СКАНИРОВАТЬ ВСЕ" forState:UIControlStateNormal];
    [scanBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    scanBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [scanBtn addTarget:[ESPMenu class] action:@selector(showScanResults) forControlEvents:UIControlEventTouchUpInside];
    [menuView addSubview:scanBtn];
    
    // Кнопка координат
    UIButton *coordBtn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    coordBtn.frame = CGRectMake(10, 95, 310, 40);
    coordBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:0.2 alpha:1];
    coordBtn.layer.cornerRadius = 8;
    [coordBtn setTitle:@"📍 ТЕКУЩИЕ КООРДИНАТЫ" forState:UIControlStateNormal];
    [coordBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    coordBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [coordBtn addTarget:[ESPMenu class] action:@selector(showCurrentPosition) forControlEvents:UIControlEventTouchUpInside];
    [menuView addSubview:coordBtn];
    
    // Текстовое поле для вывода
    infoText = [[UITextView alloc] initWithFrame:CGRectMake(5, 145, 320, 195)];
    infoText.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:1];
    infoText.textColor = [UIColor colorWithRed:0.8 green:0.8 blue:0.8 alpha:1];
    infoText.font = [UIFont fontWithName:@"Courier" size:10];
    infoText.editable = NO;
    infoText.text = @"Нажми кнопку для сканирования";
    [menuView addSubview:infoText];
    
    [keyWindow addSubview:menuView];
    
    // При запуске показываем результат
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [ESPMenu showScanResults];
    });
    
    NSLog(@"[ESP] Scanner loaded! Base = 0x%llx", (unsigned long long)getBase());
}

@end

// ==================== ЗАГРУЗКА ====================

static void loadMenu() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if ([UIApplication sharedApplication].keyWindow) {
            [ESPMenu setup];
        } else {
            loadMenu();
        }
    });
}

%ctor {
    NSLog(@"[ESP] Tweak loaded!");
    loadMenu();
}
