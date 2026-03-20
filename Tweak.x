#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>

// ========== ТВОИ RVA ==========
#define RVA_Camera_get_main         0x445BAF8
#define RVA_Camera_WorldToScreen    0x445AD5C
#define RVA_Transform_get_position   0x44CEED0

// ========== ТИПЫ ФУНКЦИЙ ==========
typedef void *(*t_Camera_get_main)();
typedef void *(*t_Camera_WorldToScreen)(void *camera, void *worldPos);
typedef void *(*t_Transform_get_position)(void *transform);

// ========== ГЛОБАЛЬНЫЕ ==========
static t_Camera_get_main Camera_get_main = NULL;
static t_Camera_WorldToScreen Camera_WorldToScreen = NULL;
static t_Transform_get_position Transform_get_position = NULL;
static NSMutableString *logText = nil;
static UIWindow *logWindow = nil;
static UIButton *floatingButton = nil;

// ========== ПОЛУЧЕНИЕ АДРЕСОВ ==========
uint64_t getBaseAddress() {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && (strstr(name, "ModernStrike") || strstr(name, "GameAssembly"))) {
            return (uint64_t)_dyld_get_image_header(i);
        }
    }
    return 0;
}

void* getRealPtr(uint64_t rva) {
    uint64_t base = getBaseAddress();
    return base ? (void*)(base + rva) : NULL;
}

// ========== ИНТЕРФЕЙС ==========
@interface ButtonHandler : NSObject
+ (void)showMenu;
+ (void)testCamera;
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
    [self setTitle:@"📷" forState:UIControlStateNormal];
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
    CGFloat w = 260, h = 200;
    UIWindow *menu = [[UIWindow alloc] initWithFrame:CGRectMake((UIScreen.mainScreen.bounds.size.width-w)/2, (UIScreen.mainScreen.bounds.size.height-h)/2, w, h)];
    menu.windowLevel = UIWindowLevelAlert + 3;
    menu.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.95];
    menu.layer.cornerRadius = 10;
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, w, 30)];
    title.text = @"📷 КАМЕРА ТЕСТ";
    title.textColor = UIColor.whiteColor;
    title.textAlignment = NSTextAlignmentCenter;
    [menu addSubview:title];
    
    UIButton *testBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    testBtn.frame = CGRectMake(20, 50, w-40, 45);
    testBtn.backgroundColor = UIColor.systemBlueColor;
    testBtn.layer.cornerRadius = 8;
    [testBtn setTitle:@"🔍 ВЫЗВАТЬ КАМЕРУ" forState:UIControlStateNormal];
    [testBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [testBtn addTarget:self action:@selector(testCamera) forControlEvents:UIControlEventTouchUpInside];
    [menu addSubview:testBtn];
    
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(20, 105, w-40, 45);
    closeBtn.backgroundColor = UIColor.systemRedColor;
    closeBtn.layer.cornerRadius = 8;
    [closeBtn setTitle:@"✖️ ЗАКРЫТЬ" forState:UIControlStateNormal];
    [closeBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [closeBtn addTarget:self action:@selector(closeMenu) forControlEvents:UIControlEventTouchUpInside];
    [menu addSubview:closeBtn];
    
    [menu makeKeyAndVisible];
    objc_setAssociatedObject(self, @selector(closeMenu), menu, OBJC_ASSOCIATION_RETAIN);
}

+ (void)closeMenu {
    UIWindow *menu = objc_getAssociatedObject(self, @selector(closeMenu));
    menu.hidden = YES;
}

+ (void)testCamera {
    logText = [NSMutableString new];
    
    [self addLog:@"📷 ТЕСТ КАМЕРЫ"];
    [self addLog:@"==============="];
    
    uint64_t base = getBaseAddress();
    [self addLog:[NSString stringWithFormat:@"📌 Base: 0x%llx", base]];
    
    // Загружаем функции
    Camera_get_main = (t_Camera_get_main)getRealPtr(RVA_Camera_get_main);
    Camera_WorldToScreen = (t_Camera_WorldToScreen)getRealPtr(RVA_Camera_WorldToScreen);
    Transform_get_position = (t_Transform_get_position)getRealPtr(RVA_Transform_get_position);
    
    [self addLog:[NSString stringWithFormat:@"✅ Camera_get_main: %p", Camera_get_main]];
    [self addLog:[NSString stringWithFormat:@"✅ WorldToScreen: %p", Camera_WorldToScreen]];
    [self addLog:[NSString stringWithFormat:@"✅ get_position: %p", Transform_get_position]];
    
    // ПЫТАЕМСЯ ВЫЗВАТЬ
    if (Camera_get_main) {
        @try {
            void *cam = Camera_get_main();
            [self addLog:[NSString stringWithFormat:@"✅ Камера вызвана -> %p", cam]];
        } @catch (NSException *e) {
            [self addLog:[NSString stringWithFormat:@"❌ Ошибка: %@", e.reason]];
        }
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
        logWindow = [[UIWindow alloc] initWithFrame:CGRectMake(20, 70, UIScreen.mainScreen.bounds.size.width-40, 350)];
        logWindow.windowLevel = UIWindowLevelAlert + 2;
        logWindow.backgroundColor = [UIColor colorWithWhite:0 alpha:0.95];
        logWindow.layer.cornerRadius = 10;
        
        UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(5, 5, logWindow.bounds.size.width-10, 290)];
        tv.backgroundColor = UIColor.blackColor;
        tv.textColor = UIColor.greenColor;
        tv.font = [UIFont fontWithName:@"Courier" size:11];
        tv.editable = NO;
        [logWindow addSubview:tv];
        
        UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        copyBtn.frame = CGRectMake(20, 300, 100, 35);
        [copyBtn setTitle:@"📋 Копировать" forState:UIControlStateNormal];
        copyBtn.backgroundColor = UIColor.systemBlueColor;
        copyBtn.layer.cornerRadius = 6;
        [copyBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        [copyBtn addTarget:self action:@selector(copyLog) forControlEvents:UIControlEventTouchUpInside];
        [logWindow addSubview:copyBtn];
        
        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        closeBtn.frame = CGRectMake(logWindow.bounds.size.width-70, 300, 50, 35);
        [closeBtn setTitle:@"✖️" forState:UIControlStateNormal];
        closeBtn.backgroundColor = UIColor.systemRedColor;
        closeBtn.layer.cornerRadius = 6;
        [closeBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
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
