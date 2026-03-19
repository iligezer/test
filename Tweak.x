#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>
#import <objc/runtime.h>

// ========== АДРЕСА ==========
#define RVA_Camera_get_main         0x10871faf8
#define RVA_Camera_WorldToScreen    0x10871ed5c
#define RVA_Transform_get_position   0x108792ed0
#define BASE_ADDR 0x1042c4000

typedef void *(*t_get_main_camera)();
typedef void *(*t_world_to_screen)(void *camera, void *worldPos);
typedef void *(*t_get_position)(void *transform);

static t_get_main_camera Camera_main = NULL;
static t_world_to_screen Camera_WorldToScreen = NULL;
static t_get_position Transform_get_position = NULL;

static NSMutableString *logText = nil;
static UIWindow *logWindow = nil;
static UIButton *floatingButton = nil;

@interface ButtonHandler : NSObject
+ (void)showMenu;
+ (void)closeMenu;
+ (void)copyLog;
+ (void)showLogWindow;
+ (void)addLog:(NSString*)text;
+ (void)minimalScan;
+ (UIWindow*)mainWindow;
+ (void)handlePan:(UIPanGestureRecognizer*)gesture;
@end

@interface FloatingButton : UIButton
@end

@implementation FloatingButton
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor systemBlueColor];
        self.layer.cornerRadius = frame.size.width/2;
        [self setTitle:@"⚡" forState:UIControlStateNormal];
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:[ButtonHandler class] action:@selector(handlePan:)];
        [self addGestureRecognizer:pan];
        [self addTarget:[ButtonHandler class] action:@selector(showMenu) forControlEvents:UIControlEventTouchUpInside];
    }
    return self;
}
@end

@implementation ButtonHandler

+ (UIWindow*)mainWindow {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            for (UIWindow *window in ((UIWindowScene*)scene).windows) {
                if (window.isKeyWindow) return window;
            }
        }
    }
    return nil;
}

+ (void)handlePan:(UIPanGestureRecognizer*)gesture {
    if (!floatingButton) return;
    CGPoint translation = [gesture translationInView:floatingButton.superview];
    CGPoint center = floatingButton.center;
    center.x += translation.x;
    center.y += translation.y;
    floatingButton.center = center;
    [gesture setTranslation:CGPointZero inView:floatingButton.superview];
}

+ (void)showMenu {
    CGFloat menuWidth = 240;
    CGFloat menuHeight = 200;
    CGFloat menuX = ([UIScreen mainScreen].bounds.size.width - menuWidth) / 2;
    CGFloat menuY = ([UIScreen mainScreen].bounds.size.height - menuHeight) / 2;
    
    UIWindow *menuWindow = [[UIWindow alloc] initWithFrame:CGRectMake(menuX, menuY, menuWidth, menuHeight)];
    menuWindow.windowLevel = UIWindowLevelAlert + 3;
    menuWindow.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.95];
    menuWindow.layer.cornerRadius = 10;
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, menuWidth, 30)];
    title.text = @"⚡ SCANNER";
    title.textColor = [UIColor whiteColor];
    title.textAlignment = NSTextAlignmentCenter;
    [menuWindow addSubview:title];
    
    UIButton *scanBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    scanBtn.frame = CGRectMake(20, 50, menuWidth-40, 40);
    scanBtn.backgroundColor = [UIColor systemBlueColor];
    [scanBtn setTitle:@"🔍 МИНИМАЛЬНОЕ СКАНИРОВАНИЕ" forState:UIControlStateNormal];
    [scanBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [scanBtn addTarget:self action:@selector(minimalScan) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:scanBtn];
    
    UIButton *logBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    logBtn.frame = CGRectMake(20, 100, menuWidth-40, 40);
    logBtn.backgroundColor = [UIColor systemGrayColor];
    [logBtn setTitle:@"📋 ПОКАЗАТЬ ЛОГ" forState:UIControlStateNormal];
    [logBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [logBtn addTarget:self action:@selector(showLogWindow) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:logBtn];
    
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(20, 150, menuWidth-40, 40);
    closeBtn.backgroundColor = [UIColor systemRedColor];
    [closeBtn setTitle:@"✖️ ЗАКРЫТЬ" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [closeBtn addTarget:self action:@selector(closeMenu) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:closeBtn];
    
    [menuWindow makeKeyAndVisible];
    objc_setAssociatedObject(self, @selector(closeMenu), menuWindow, OBJC_ASSOCIATION_RETAIN);
}

+ (void)closeMenu {
    UIWindow *menuWindow = objc_getAssociatedObject(self, @selector(closeMenu));
    menuWindow.hidden = YES;
    [menuWindow resignKeyWindow];
}

// ========== МИНИМАЛЬНОЕ БЕЗОПАСНОЕ СКАНИРОВАНИЕ ==========
+ (void)minimalScan {
    [logText setString:@""];
    [self addLog:@"🔍 МИНИМАЛЬНОЕ СКАНИРОВАНИЕ..."];
    
    task_t task = mach_task_self();
    vm_address_t address = 0;
    vm_size_t size = 0;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object_name;
    
    int candidates = 0;
    
    while (vm_region_64(task, &address, &size, VM_REGION_BASIC_INFO_64, 
                        (vm_region_info_t)&info, &count, &object_name) == KERN_SUCCESS) {
        
        // ТОЛЬКО читаемые регионы
        if (!(info.protection & VM_PROT_READ)) {
            address += size;
            continue;
        }
        
        // Только разумный размер
        if (size < 4096 || size > 10*1024*1024) {
            address += size;
            continue;
        }
        
        // Пробуем прочитать 4 байта для теста
        uint32_t test = 0;
        vm_size_t test_read = 0;
        kern_return_t kr = vm_read_overwrite(task, address, 4, (vm_address_t)&test, &test_read);
        
        if (kr == KERN_SUCCESS) {
            candidates++;
            if (candidates <= 20) { // Показываем только первые 20
                [self addLog:[NSString stringWithFormat:@"✅ Регион %d: 0x%llx - %llu KB", 
                              candidates, address, size/1024]];
            }
        }
        
        address += size;
        
        // Пауза
        if (candidates % 10 == 0) usleep(10000);
    }
    
    [self addLog:[NSString stringWithFormat:@"\n📊 Найдено читаемых регионов: %d", candidates]];
    [self showLogWindow];
}

+ (void)addLog:(NSString *)text {
    if (!logText) logText = [[NSMutableString alloc] init];
    [logText appendFormat:@"%@\n", text];
    NSLog(@"%@", text);
}

+ (void)showLogWindow {
    if (logWindow) {
        logWindow.hidden = NO;
        return;
    }
    
    CGFloat w = [UIScreen mainScreen].bounds.size.width - 40;
    CGFloat h = [UIScreen mainScreen].bounds.size.height - 150;
    CGFloat x = 20;
    CGFloat y = 70;
    
    logWindow = [[UIWindow alloc] initWithFrame:CGRectMake(x, y, w, h)];
    logWindow.windowLevel = UIWindowLevelAlert + 2;
    logWindow.backgroundColor = [UIColor colorWithWhite:0 alpha:0.95];
    
    UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(5, 5, w-10, h-60)];
    tv.backgroundColor = [UIColor blackColor];
    tv.textColor = [UIColor greenColor];
    tv.font = [UIFont fontWithName:@"Courier" size:10];
    tv.text = logText;
    tv.editable = NO;
    [logWindow addSubview:tv];
    
    UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    copyBtn.frame = CGRectMake(20, h-50, 100, 40);
    copyBtn.backgroundColor = [UIColor systemBlueColor];
    [copyBtn setTitle:@"📋 Копировать" forState:UIControlStateNormal];
    [copyBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [copyBtn addTarget:self action:@selector(copyLog) forControlEvents:UIControlEventTouchUpInside];
    [logWindow addSubview:copyBtn];
    
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(w-120, h-50, 100, 40);
    closeBtn.backgroundColor = [UIColor systemRedColor];
    [closeBtn setTitle:@"❌ Закрыть" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [closeBtn addTarget:self action:@selector(closeLogWindow) forControlEvents:UIControlEventTouchUpInside];
    [logWindow addSubview:closeBtn];
    
    [logWindow makeKeyAndVisible];
}

+ (void)closeLogWindow {
    logWindow.hidden = YES;
}

+ (void)copyLog {
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    pasteboard.string = logText;
    
    UILabel *toast = [[UILabel alloc] initWithFrame:CGRectMake(120, 300, 120, 40)];
    toast.backgroundColor = [UIColor blackColor];
    toast.textColor = [UIColor whiteColor];
    toast.text = @"✅ Скопировано";
    toast.textAlignment = NSTextAlignmentCenter;
    toast.layer.cornerRadius = 8;
    [[self mainWindow] addSubview:toast];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [toast removeFromSuperview];
    });
}

@end

__attribute__((constructor))
static void init() {
    @autoreleasepool {
        logText = [[NSMutableString alloc] init];
        
        uint64_t base = BASE_ADDR;
        Camera_main = (t_get_main_camera)(base + (RVA_Camera_get_main - 0x1042c4000));
        Camera_WorldToScreen = (t_world_to_screen)(base + (RVA_Camera_WorldToScreen - 0x1042c4000));
        Transform_get_position = (t_get_position)(base + (RVA_Transform_get_position - 0x1042c4000));
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            UIWindow *mainWindow = [ButtonHandler mainWindow];
            if (!mainWindow) return;
            
            floatingButton = [[FloatingButton alloc] initWithFrame:CGRectMake(20, 150, 50, 50)];
            [mainWindow addSubview:floatingButton];
            
            [ButtonHandler addLog:@"✅ Твик загружен"];
        });
    }
}
