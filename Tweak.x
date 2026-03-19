#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>

// ==================== RVA ИЗ ТВОЕГО DUMP.CS ====================
#define RVA_Camera_get_main                     0x445BAF8
#define RVA_Camera_WorldToScreenPoint           0x445AD5C
#define RVA_Transform_get_position               0x44CEED0
#define RVA_NetworkPlayer_IsMine                 0x2EA8BE4
#define RVA_NetworkPlayer_IsDead                 0x2EA2230
#define RVA_NetworkPlayer_IsAlly                  0x2E9BE28
#define RVA_NetworkPlayer_GetHealth               0x2EACF44
#define RVA_NetworkPlayer_GetTransform            0x2EA8C10

// ==================== ПОЛУЧЕНИЕ АДРЕСОВ ====================
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

// ==================== ПОЛУЧЕНИЕ ОКНА ====================
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

UIViewController* getTopVC() {
    UIWindow *win = getMainWindow();
    if (!win) return nil;
    UIViewController *vc = win.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

// ==================== ТИПЫ ФУНКЦИЙ ====================
typedef void *(*t_Camera_get_main)();
typedef void *(*t_Camera_WorldToScreenPoint)(void *camera, void *worldPos);
typedef void *(*t_Transform_get_position)(void *transform);
typedef bool (*t_NetworkPlayer_IsMine)(void *player);
typedef bool (*t_NetworkPlayer_IsDead)(void *player);
typedef bool (*t_NetworkPlayer_IsAlly)(void *player);
typedef float (*t_NetworkPlayer_GetHealth)(void *player);
typedef void *(*t_NetworkPlayer_GetTransform)(void *player);

// ==================== ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ ====================
static t_Camera_get_main Camera_main = NULL;
static t_Camera_WorldToScreenPoint Camera_WorldToScreenPoint = NULL;
static t_Transform_get_position Transform_get_position = NULL;
static t_NetworkPlayer_IsMine NetworkPlayer_IsMine = NULL;
static t_NetworkPlayer_IsDead NetworkPlayer_IsDead = NULL;
static t_NetworkPlayer_IsAlly NetworkPlayer_IsAlly = NULL;
static t_NetworkPlayer_GetHealth NetworkPlayer_GetHealth = NULL;
static t_NetworkPlayer_GetTransform NetworkPlayer_GetTransform = NULL;

static BOOL espEnabled = NO;
static UIWindow *menuWindow = nil;
static UIWindow *espWindow = nil;

// ==================== ESP VIEW ====================
@interface EspRenderView : UIView
@end
@implementation EspRenderView
- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    if (!espEnabled || !Camera_main || !Camera_WorldToScreenPoint) return;
    
    void *cam = Camera_main();
    if (!cam) return;
    
    // Рисуем тестовый прямоугольник (позже заменишь на реальных игроков)
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetStrokeColorWithColor(ctx, [UIColor redColor].CGColor);
    CGContextSetLineWidth(ctx, 2);
    CGContextStrokeRect(ctx, CGRectMake(100, 100, 50, 100));
}
@end

// ==================== МЕНЮ ====================
@interface AimbotMenuController : UIViewController
@property (nonatomic, strong) UISwitch *espSwitch;
@property (nonatomic, strong) UITextView *logView;
@end

@implementation AimbotMenuController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
    self.view.layer.cornerRadius = 15;
    
    CGFloat y = 30;
    
    // Заголовок
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, 260, 30)];
    title.text = @"Aimbot Control";
    title.textColor = UIColor.whiteColor;
    title.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:title];
    
    // ESP Switch
    UILabel *espLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, y, 150, 30)];
    espLabel.text = @"ESP";
    espLabel.textColor = UIColor.whiteColor;
    [self.view addSubview:espLabel];
    
    self.espSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(180, y, 60, 30)];
    [self.espSwitch addTarget:self action:@selector(espToggled) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.espSwitch];
    y += 50;
    
    // Кнопка теста
    UIButton *testBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    testBtn.frame = CGRectMake(20, y, 220, 40);
    [testBtn setTitle:@"Запустить тест" forState:UIControlStateNormal];
    [testBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    testBtn.backgroundColor = UIColor.systemPurpleColor;
    testBtn.layer.cornerRadius = 8;
    [testBtn addTarget:self action:@selector(runTest) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:testBtn];
    y += 50;
    
    // Лог
    self.logView = [[UITextView alloc] initWithFrame:CGRectMake(10, y, 240, 150)];
    self.logView.backgroundColor = UIColor.blackColor;
    self.logView.textColor = UIColor.greenColor;
    self.logView.font = [UIFont fontWithName:@"Courier" size:10];
    self.logView.editable = NO;
    [self.view addSubview:self.logView];
    y += 160;
    
    // Кнопка копирования
    UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    copyBtn.frame = CGRectMake(20, y, 100, 30);
    [copyBtn setTitle:@"Копировать" forState:UIControlStateNormal];
    [copyBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    copyBtn.backgroundColor = UIColor.systemBlueColor;
    copyBtn.layer.cornerRadius = 5;
    [copyBtn addTarget:self action:@selector(copyLog) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:copyBtn];
    
    // Кнопка закрытия
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(140, y, 100, 30);
    [closeBtn setTitle:@"Закрыть" forState:UIControlStateNormal];
    [closeBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    closeBtn.backgroundColor = UIColor.systemRedColor;
    closeBtn.layer.cornerRadius = 5;
    [closeBtn addTarget:self action:@selector(closeMenu) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:closeBtn];
}

- (void)espToggled {
    espEnabled = self.espSwitch.isOn;
}

- (void)runTest {
    NSMutableString *log = [NSMutableString string];
    [log appendString:@"=== ТЕСТ IL2CPP ===\n"];
    [log appendFormat:@"Base: 0x%llx\n", getBaseAddress()];
    
    Camera_main = (t_Camera_get_main)getRealPtr(RVA_Camera_get_main);
    [log appendFormat:@"Camera.main: %p %@\n", Camera_main, Camera_main ? @"✅" : @"❌"];
    
    Camera_WorldToScreenPoint = (t_Camera_WorldToScreenPoint)getRealPtr(RVA_Camera_WorldToScreenPoint);
    [log appendFormat:@"WorldToScreen: %p %@\n", Camera_WorldToScreenPoint, Camera_WorldToScreenPoint ? @"✅" : @"❌"];
    
    Transform_get_position = (t_Transform_get_position)getRealPtr(RVA_Transform_get_position);
    [log appendFormat:@"get_position: %p %@\n", Transform_get_position, Transform_get_position ? @"✅" : @"❌"];
    
    NetworkPlayer_IsMine = (t_NetworkPlayer_IsMine)getRealPtr(RVA_NetworkPlayer_IsMine);
    [log appendFormat:@"IsMine: %p %@\n", NetworkPlayer_IsMine, NetworkPlayer_IsMine ? @"✅" : @"❌"];
    
    NetworkPlayer_IsDead = (t_NetworkPlayer_IsDead)getRealPtr(RVA_NetworkPlayer_IsDead);
    [log appendFormat:@"IsDead: %p %@\n", NetworkPlayer_IsDead, NetworkPlayer_IsDead ? @"✅" : @"❌"];
    
    NetworkPlayer_IsAlly = (t_NetworkPlayer_IsAlly)getRealPtr(RVA_NetworkPlayer_IsAlly);
    [log appendFormat:@"IsAlly: %p %@\n", NetworkPlayer_IsAlly, NetworkPlayer_IsAlly ? @"✅" : @"❌"];
    
    NetworkPlayer_GetHealth = (t_NetworkPlayer_GetHealth)getRealPtr(RVA_NetworkPlayer_GetHealth);
    [log appendFormat:@"GetHealth: %p %@\n", NetworkPlayer_GetHealth, NetworkPlayer_GetHealth ? @"✅" : @"❌"];
    
    NetworkPlayer_GetTransform = (t_NetworkPlayer_GetTransform)getRealPtr(RVA_NetworkPlayer_GetTransform);
    [log appendFormat:@"GetTransform: %p %@\n", NetworkPlayer_GetTransform, NetworkPlayer_GetTransform ? @"✅" : @"❌"];
    
    self.logView.text = log;
}

- (void)copyLog {
    UIPasteboard.generalPasteboard.string = self.logView.text;
}

- (void)closeMenu {
    menuWindow.hidden = YES;
    menuWindow = nil;
}

@end

// ==================== ПЛАВАЮЩАЯ КНОПКА ====================
@interface FloatButton : UIButton
@end

@implementation FloatButton

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(20, 150, 60, 60)];
    if (self) {
        self.backgroundColor = UIColor.systemBlueColor;
        self.layer.cornerRadius = 30;
        [self setTitle:@"⚡" forState:UIControlStateNormal];
        [self addTarget:self action:@selector(tap) forControlEvents:UIControlEventTouchUpInside];
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
        [self addGestureRecognizer:pan];
    }
    return self;
}

- (void)tap {
    if (menuWindow) {
        menuWindow.hidden = YES;
        menuWindow = nil;
    } else {
        menuWindow = [[UIWindow alloc] initWithFrame:CGRectMake(50, 100, 260, 400)];
        menuWindow.windowLevel = UIWindowLevelAlert + 1;
        menuWindow.backgroundColor = UIColor.clearColor;
        menuWindow.rootViewController = [AimbotMenuController new];
        menuWindow.hidden = NO;
    }
}

- (void)pan:(UIPanGestureRecognizer*)g {
    CGPoint t = [g translationInView:self.superview];
    self.center = CGPointMake(self.center.x + t.x, self.center.y + t.y);
    [g setTranslation:CGPointZero inView:self.superview];
}

@end

// ==================== ИНИЦИАЛИЗАЦИЯ ====================
__attribute__((constructor))
static void init() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        UIWindow *win = getMainWindow();
        if (!win) return;
        
        // Кнопка
        FloatButton *btn = [FloatButton new];
        [win addSubview:btn];
        
        // ESP окно
        espWindow = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        espWindow.windowLevel = UIWindowLevelNormal;
        espWindow.backgroundColor = UIColor.clearColor;
        espWindow.userInteractionEnabled = NO;
        [espWindow addSubview:[EspRenderView new]];
        [espWindow makeKeyAndVisible];
        
        // Таймер обновления ESP
        [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *t){
            [espWindow.subviews.firstObject setNeedsDisplay];
        }];
    });
}
