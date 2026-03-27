#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <substrate.h>

#define UTILITIES_TYPEINFO_RVA          0x8E15248
#define AXEARMS_OFFSET                  0x150

uintptr_t getBase() {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char* name = _dyld_get_image_name(i);
        if (strstr(name, "UnityFramework")) {
            return (uintptr_t)_dyld_get_image_header(i);
        }
    }
    return 0;
}

@interface DebugMenu : NSObject
+ (void)setup;
@end

@implementation DebugMenu

static UIView *menuContainer = nil;
static UIButton *menuButton = nil;
static UITextView *debugText = nil;
static BOOL isMenuVisible = NO;

+ (void)showAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title 
                                                                   message:message 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    [rootVC presentViewController:alert animated:YES completion:nil];
}

+ (void)debugRawData {
    uintptr_t base = getBase();
    if (base == 0) {
        [self showAlert:@"Ошибка" message:@"Base не найдена"];
        return;
    }
    
    NSMutableString *info = [NSMutableString string];
    [info appendFormat:@"Base: 0x%llx\n\n", (unsigned long long)base];
    
    uintptr_t typeInfo = base + UTILITIES_TYPEINFO_RVA;
    uintptr_t static_fields = *(uintptr_t*)(typeInfo + 0x08);
    [info appendFormat:@"static_fields: 0x%llx\n\n", (unsigned long long)static_fields];
    
    // Проверяем смещения 0x28 и 0x30
    int offsets[] = {0x28, 0x30};
    
    for (int i = 0; i < 2; i++) {
        int offset = offsets[i];
        uintptr_t firstPerson = *(uintptr_t*)(static_fields + offset);
        [info appendFormat:@"\n========== offset 0x%02x ==========\n", offset];
        [info appendFormat:@"FirstPerson ptr: 0x%llx\n", (unsigned long long)firstPerson];
        
        if (firstPerson == 0) {
            [info appendString:@"❌ NULL\n"];
            continue;
        }
        
        // Показываем первый qword как HEX (это то, что мы читали как float)
        uint64_t firstQword = *(uint64_t*)(firstPerson);
        [info appendFormat:@"First 8 bytes (as hex): 0x%016llx\n", (unsigned long long)firstQword];
        
        // Читаем Transform по смещению 0x150
        uintptr_t transform = *(uintptr_t*)(firstPerson + AXEARMS_OFFSET);
        [info appendFormat:@"\nTransform ptr (0x150): 0x%llx\n", (unsigned long long)transform];
        
        if (transform == 0) {
            [info appendString:@"❌ Transform = NULL\n"];
            continue;
        }
        
        // Показываем первые 32 байта Transform как hex
        [info appendString:@"\nTransform raw data (32 bytes):\n"];
        for (int j = 0; j < 32; j += 8) {
            uint64_t val = *(uint64_t*)(transform + j);
            [info appendFormat:@"  +0x%02x: 0x%016llx", j, (unsigned long long)val];
            
            // Проверяем, может это указатель на класс?
            if (j == 0) {
                if (val > base && val < base + 0x20000000) {
                    [info appendString:@" ← возможно klass (vtable)"];
                }
            }
            [info appendString:@"\n"];
        }
        
        // Читаем position как float и как uint32
        [info appendString:@"\nPosition (offset 0x20):\n"];
        uint32_t rawX = *(uint32_t*)(transform + 0x20);
        uint32_t rawY = *(uint32_t*)(transform + 0x24);
        uint32_t rawZ = *(uint32_t*)(transform + 0x28);
        float x = *(float*)(transform + 0x20);
        float y = *(float*)(transform + 0x24);
        float z = *(float*)(transform + 0x28);
        
        [info appendFormat:@"  as hex: X=0x%08x Y=0x%08x Z=0x%08x\n", rawX, rawY, rawZ];
        [info appendFormat:@"  as float: X=%f Y=%f Z=%f\n", x, y, z];
        
        // Проверяем, похоже ли на реальные координаты
        if (fabs(x) < 10000 && fabs(y) < 10000 && fabs(z) < 10000 && (x != 0 || y != 0 || z != 0)) {
            [info appendString:@"  ✅ ПОХОЖЕ НА РЕАЛЬНЫЕ КООРДИНАТЫ!\n"];
        } else if (rawX == 0 && rawY == 0 && rawZ == 0) {
            [info appendString:@"  ⚠️ Все нули\n"];
        } else {
            [info appendString:@"  ❌ Это не координаты (слишком большие или нереалистичные)\n"];
            [info appendFormat:@"     Возможно, это указатели: 0x%08x, 0x%08x, 0x%08x\n", rawX, rawY, rawZ];
        }
    }
    
    [self showAlert:@"Raw Data Debug" message:info];
    if (debugText) {
        debugText.text = info;
    }
}

+ (void)toggleMenu {
    isMenuVisible = !isMenuVisible;
    menuContainer.hidden = !isMenuVisible;
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
    
    CGRect frame = menuContainer.frame;
    frame.origin.x = menuButton.frame.origin.x;
    frame.origin.y = menuButton.frame.origin.y + menuButton.frame.size.height + 5;
    menuContainer.frame = frame;
}

+ (void)setup {
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    if (!keyWindow) return;
    
    menuButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    menuButton.frame = CGRectMake(keyWindow.bounds.size.width - 70, 60, 50, 50);
    menuButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.5 blue:1.0 alpha:0.9];
    menuButton.layer.cornerRadius = 25;
    [menuButton setTitle:@"🔍" forState:UIControlStateNormal];
    [menuButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    menuButton.titleLabel.font = [UIFont boldSystemFontOfSize:24];
    [menuButton addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragButton:)];
    [menuButton addGestureRecognizer:pan];
    [keyWindow addSubview:menuButton];
    
    menuContainer = [[UIView alloc] initWithFrame:CGRectMake(menuButton.frame.origin.x, 
                                                              menuButton.frame.origin.y + 55, 
                                                              380, 500)];
    menuContainer.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.05 alpha:0.95];
    menuContainer.layer.cornerRadius = 12;
    menuContainer.hidden = YES;
    menuContainer.userInteractionEnabled = YES;
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 8, 380, 28)];
    title.text = @"Modern Strike Debug - RAW DATA";
    title.textColor = [UIColor whiteColor];
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:14];
    [menuContainer addSubview:title];
    
    UIButton *debugBtn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    debugBtn.frame = CGRectMake(10, 45, 360, 40);
    debugBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.5 blue:0.8 alpha:1];
    debugBtn.layer.cornerRadius = 8;
    [debugBtn setTitle:@"🔍 Показать RAW DATA" forState:UIControlStateNormal];
    [debugBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    debugBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [debugBtn addTarget:self action:@selector(debugRawData) forControlEvents:UIControlEventTouchUpInside];
    [menuContainer addSubview:debugBtn];
    
    debugText = [[UITextView alloc] initWithFrame:CGRectMake(5, 95, 370, 390)];
    debugText.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:1];
    debugText.textColor = [UIColor colorWithRed:0.8 green:0.8 blue:0.8 alpha:1];
    debugText.font = [UIFont fontWithName:@"Courier" size:9];
    debugText.editable = NO;
    debugText.text = @"Нажми кнопку после захода в матч";
    [menuContainer addSubview:debugText];
    
    [keyWindow addSubview:menuContainer];
    
    NSLog(@"[ESP] Debug menu loaded!");
}

@end

static void loadMenu() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if ([UIApplication sharedApplication].keyWindow) {
            [DebugMenu setup];
        } else {
            loadMenu();
        }
    });
}

%ctor {
    NSLog(@"[ESP] Debug tweak loaded!");
    loadMenu();
}
