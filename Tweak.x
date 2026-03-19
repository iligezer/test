#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>

// ========== ТВОИ RVA ИЗ DUMP.CS ==========
#define RVA_GameManager_GetLocalPlayer       0x3839064
#define RVA_Player_get_Health                0x2EACF44

// ========== ПОЛУЧЕНИЕ АДРЕСОВ ==========
uint64_t getBaseAddress() {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        if (name) {
            if (strstr(name, "ModernStrike")) return (uint64_t)_dyld_get_image_header(i);
            if (strstr(name, "GameAssembly")) return (uint64_t)_dyld_get_image_header(i);
        }
    }
    return 0;
}

void* getRealPtr(uint64_t rva) {
    uint64_t base = getBaseAddress();
    return base ? (void*)(base + rva) : NULL;
}

// ========== ПОЛУЧЕНИЕ ГЛАВНОГО ОКНА (ТОЛЬКО ЧЕРЕЗ СЦЕНЫ) ==========
UIWindow* getMainWindow() {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            for (UIWindow *window in windowScene.windows) {
                if (window.isKeyWindow) return window;
            }
        }
    }
    return nil;
}

UIViewController* getTopViewController() {
    UIWindow *window = getMainWindow();
    if (!window) return nil;
    
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController) {
        vc = vc.presentedViewController;
    }
    return vc;
}

// ========== КНОПКА ==========
@interface SimpleButton : UIButton @end
@implementation SimpleButton
- (instancetype)init {
    self = [super initWithFrame:CGRectMake(20, 150, 60, 60)];
    if (self) {
        self.backgroundColor = [UIColor systemBlueColor];
        self.layer.cornerRadius = 30;
        [self setTitle:@"A" forState:UIControlStateNormal];
        [self setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [self addTarget:self action:@selector(tap) forControlEvents:UIControlEventTouchUpInside];
    }
    return self;
}
- (void)tap {
    void *(*func)() = getRealPtr(RVA_GameManager_GetLocalPlayer);
    
    NSString *msg;
    if (func) {
        void *result = func();
        msg = [NSString stringWithFormat:@"✅ Вызов успешен\nАдрес: %p\nРезультат: %p", func, result];
    } else {
        msg = @"❌ Адрес функции не получен";
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Aimbot Debug"
                                                                   message:msg
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [getTopViewController() presentViewController:alert animated:YES completion:nil];
}
@end

// ========== ЗАГРУЗКА ==========
__attribute__((constructor))
static void init() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        UIWindow *win = getMainWindow();
        if (!win) {
            NSLog(@"[Aimbot] Окно не найдено");
            return;
        }
        
        SimpleButton *btn = [[SimpleButton alloc] init];
        [win addSubview:btn];
        
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Aimbot"
                                                                       message:[NSString stringWithFormat:@"Загружен\nBase: 0x%llx", getBaseAddress()]
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [getTopViewController() presentViewController:alert animated:YES completion:nil];
    });
}
