#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <objc/runtime.h>

// ==================== RVA ИЗ ТВОЕГО DUMP.CS ====================
#define RVA_Camera_get_main                     0x445BAF8
#define RVA_Camera_WorldToScreenPoint           0x445AD5C
#define RVA_Transform_get_position               0x44CEED0

#define RVA_NetworkPlayer_IsMine                 0x2EA8BE4
#define RVA_NetworkPlayer_IsDead                 0x2EA2230
#define RVA_NetworkPlayer_IsAlly                  0x2E9BE28
#define RVA_NetworkPlayer_GetHealth               0x2EACF44
#define RVA_NetworkPlayer_GetTransform            0x2EA8C10
#define RVA_NetworkPlayer_GetLookPoint            0x2EA8C30

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

// ==================== ПОЛУЧЕНИЕ ОКНА (iOS 15+) ====================
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
typedef void *(*t_NetworkPlayer_GetLookPoint)(void *player);

// ==================== ГЛОБАЛЬНЫЕ УКАЗАТЕЛИ НА ФУНКЦИИ ====================
static t_Camera_get_main Camera_main = NULL;
static t_Camera_WorldToScreenPoint Camera_WorldToScreenPoint = NULL;
static t_Transform_get_position Transform_get_position = NULL;

static t_NetworkPlayer_IsMine NetworkPlayer_IsMine = NULL;
static t_NetworkPlayer_IsDead NetworkPlayer_IsDead = NULL;
static t_NetworkPlayer_IsAlly NetworkPlayer_IsAlly = NULL;
static t_NetworkPlayer_GetHealth NetworkPlayer_GetHealth = NULL;
static t_NetworkPlayer_GetTransform NetworkPlayer_GetTransform = NULL;
static t_NetworkPlayer_GetLookPoint NetworkPlayer_GetLookPoint = NULL;

// ==================== НАСТРОЙКИ МЕНЮ ====================
static BOOL espEnabled = NO;
static BOOL aimbotEnabled = NO;
static BOOL showTeam = NO;
static BOOL showHealth = YES;
static BOOL showDistance = YES;
static float aimFov = 10.0f;
static int aimSmooth = 5;

// ==================== ОКНО ДЛЯ ESP ====================
@interface ESPView : UIView
@end

@implementation ESPView

- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    
    if (!espEnabled) return;
    if (!Camera_main || !Camera_WorldToScreenPoint || !Transform_get_position) return;
    
    // Получаем камеру
    void *camera = Camera_main();
    if (!camera) return;
    
    // TODO: Здесь будет получение списка игроков
    // Пока рисуем тестовый прямоугольник
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetStrokeColorWithColor(ctx, [UIColor redColor].CGColor);
    CGContextSetLineWidth(ctx, 2.0);
    CGContextStrokeRect(ctx, CGRectMake(100, 100, 50, 100));
}

@end

// ==================== ОКНО РЕЗУЛЬТАТОВ ТЕСТА ====================
@interface TestResultWindow : UIWindow
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UIButton *copyButton;
@end

@implementation TestResultWindow

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.windowLevel = UIWindowLevelAlert + 2;
        self.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
        self.layer.cornerRadius = 10;
        self.clipsToBounds = YES;
        
        // Заголовок
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, frame.size.width, 40)];
        title.text = @"📊 Результаты тестирования";
        title.textColor = [UIColor whiteColor];
        title.textAlignment = NSTextAlignmentCenter;
        title.font = [UIFont boldSystemFontOfSize:16];
        title.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
        [self addSubview:title];
        
        // Текстовое поле
        self.textView = [[UITextView alloc] initWithFrame:CGRectMake(10, 50, frame.size.width-20, frame.size.height-100)];
        self.textView.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
        self.textView.textColor = [UIColor greenColor];
        self.textView.font = [UIFont fontWithName:@"Courier" size:12];
        self.textView.editable = NO;
        self.textView.layer.cornerRadius = 5;
        [self addSubview:self.textView];
        
        // Кнопка копирования
        self.copyButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.copyButton.frame = CGRectMake(10, frame.size.height-40, (frame.size.width-30)/2, 30);
        [self.copyButton setTitle:@"📋 Копировать" forState:UIControlStateNormal];
        [self.copyButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.copyButton.backgroundColor = [UIColor systemBlueColor];
        self.copyButton.layer.cornerRadius = 5;
        [self.copyButton addTarget:self action:@selector(copyText) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.copyButton];
        
        // Кнопка закрытия
        self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.closeButton.frame = CGRectMake(20 + (frame.size.width-30)/2, frame.size.height-40, (frame.size.width-30)/2, 30);
        [self.closeButton setTitle:@"❌ Закрыть" forState:UIControlStateNormal];
        [self.closeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.closeButton.backgroundColor = [UIColor systemRedColor];
        self.closeButton.layer.cornerRadius = 5;
        [self.closeButton addTarget:self action:@selector(closeWindow) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.closeButton];
    }
    return self;
}

- (void)copyText {
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    pasteboard.string = self.textView.text;
    
    // Визуальное подтверждение
    self.copyButton.backgroundColor = [UIColor systemGreenColor];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        self.copyButton.backgroundColor = [UIColor systemBlueColor];
    });
}

- (void)closeWindow {
    self.hidden = YES;
    [self removeFromSuperview];
}

@end

// ==================== МЕНЮ ====================
@interface AimbotMenu : UIWindow
@property (nonatomic, strong) UISwitch *espSwitch;
@property (nonatomic, strong) UISwitch *aimbotSwitch;
@property (nonatomic, strong) UISwitch *teamSwitch;
@property (nonatomic, strong) UISwitch *healthSwitch;
@property (nonatomic, strong) UISwitch *distanceSwitch;
@property (nonatomic, strong) UISlider *fovSlider;
@property (nonatomic, strong) UILabel *fovLabel;
@property (nonatomic, strong) UISlider *smoothSlider;
@property (nonatomic, strong) UILabel *smoothLabel;
@property (nonatomic, strong) UIButton *testButton;
@property (nonatomic, strong) UIButton *closeButton;
@end

@implementation AimbotMenu

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.windowLevel = UIWindowLevelAlert + 1;
        self.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
        self.layer.cornerRadius = 15;
        self.clipsToBounds = YES;
        
        CGFloat y = 20;
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, frame.size.width, 30)];
        title.text = @"🎯 AIMBOT CONTROL";
        title.textColor = [UIColor whiteColor];
        title.textAlignment = NSTextAlignmentCenter;
        title.font = [UIFont boldSystemFontOfSize:18];
        [self addSubview:title];
        y += 30;
        
        // ESP Switch
        [self addSwitchWithFrame:CGRectMake(20, y, frame.size.width-40, 40) 
                            label:@"ESP (Wallhack)" 
                            target:self 
                            action:@selector(espChanged:) 
                              tag:1];
        y += 50;
        
        // Aimbot Switch
        [self addSwitchWithFrame:CGRectMake(20, y, frame.size.width-40, 40) 
                            label:@"Aimbot" 
                            target:self 
                            action:@selector(aimbotChanged:) 
                              tag:2];
        y += 50;
        
        // Team Switch
        [self addSwitchWithFrame:CGRectMake(20, y, frame.size.width-40, 40) 
                            label:@"Показывать тиммейтов" 
                            target:self 
                            action:@selector(teamChanged:) 
                              tag:3];
        y += 50;
        
        // Health Switch
        [self addSwitchWithFrame:CGRectMake(20, y, frame.size.width-40, 40) 
                            label:@"Показывать здоровье" 
                            target:self 
                            action:@selector(healthChanged:) 
                              tag:4];
        y += 50;
        
        // Distance Switch
        [self addSwitchWithFrame:CGRectMake(20, y, frame.size.width-40, 40) 
                            label:@"Показывать дистанцию" 
                            target:self 
                            action:@selector(distanceChanged:) 
                              tag:5];
        y += 60;
        
        // FOV Slider
        UILabel *fovTitle = [[UILabel alloc] initWithFrame:CGRectMake(20, y, 100, 30)];
        fovTitle.text = @"FOV:";
        fovTitle.textColor = [UIColor whiteColor];
        [self addSubview:fovTitle];
        
        self.fovLabel = [[UILabel alloc] initWithFrame:CGRectMake(frame.size.width-80, y, 60, 30)];
        self.fovLabel.text = @"10.0";
        self.fovLabel.textColor = [UIColor cyanColor];
        self.fovLabel.textAlignment = NSTextAlignmentRight;
        [self addSubview:self.fovLabel];
        y += 30;
        
        self.fovSlider = [[UISlider alloc] initWithFrame:CGRectMake(20, y, frame.size.width-40, 30)];
        self.fovSlider.minimumValue = 1.0;
        self.fovSlider.maximumValue = 30.0;
        self.fovSlider.value = aimFov;
        [self.fovSlider addTarget:self action:@selector(fovChanged:) forControlEvents:UIControlEventValueChanged];
        [self addSubview:self.fovSlider];
        y += 40;
        
        // Smooth Slider
        UILabel *smoothTitle = [[UILabel alloc] initWithFrame:CGRectMake(20, y, 100, 30)];
        smoothTitle.text = @"Smooth:";
        smoothTitle.textColor = [UIColor whiteColor];
        [self addSubview:smoothTitle];
        
        self.smoothLabel = [[UILabel alloc] initWithFrame:CGRectMake(frame.size.width-80, y, 60, 30)];
        self.smoothLabel.text = @"5";
        self.smoothLabel.textColor = [UIColor cyanColor];
        self.smoothLabel.textAlignment = NSTextAlignmentRight;
        [self addSubview:self.smoothLabel];
        y += 30;
        
        self.smoothSlider = [[UISlider alloc] initWithFrame:CGRectMake(20, y, frame.size.width-40, 30)];
        self.smoothSlider.minimumValue = 1.0;
        self.smoothSlider.maximumValue = 20.0;
        self.smoothSlider.value = aimSmooth;
        [self.smoothSlider addTarget:self action:@selector(smoothChanged:) forControlEvents:UIControlEventValueChanged];
        [self addSubview:self.smoothSlider];
        y += 50;
        
        // Test Button
        self.testButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.testButton.frame = CGRectMake(20, y, frame.size.width-40, 40);
        [self.testButton setTitle:@"🧪 Запустить тест IL2CPP" forState:UIControlStateNormal];
        [self.testButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.testButton.backgroundColor = [UIColor systemPurpleColor];
        self.testButton.layer.cornerRadius = 8;
        [self.testButton addTarget:self action:@selector(runTest) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.testButton];
        y += 50;
        
        // Close Button
        self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.closeButton.frame = CGRectMake(20, y, frame.size.width-40, 40);
        [self.closeButton setTitle:@"❌ Закрыть меню" forState:UIControlStateNormal];
        [self.closeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.closeButton.backgroundColor = [UIColor systemRedColor];
        self.closeButton.layer.cornerRadius = 8;
        [self.closeButton addTarget:self action:@selector(closeMenu) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.closeButton];
    }
    return self;
}

- (void)addSwitchWithFrame:(CGRect)frame label:(NSString*)label target:(id)target action:(SEL)action tag:(NSInteger)tag {
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(frame.origin.x, frame.origin.y, frame.size.width-70, frame.size.height)];
    lbl.text = label;
    lbl.textColor = [UIColor whiteColor];
    [self addSubview:lbl];
    
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(frame.origin.x + frame.size.width - 60, frame.origin.y+5, 60, frame.size.height)];
    sw.tag = tag;
    [sw addTarget:target action:action forControlEvents:UIControlEventValueChanged];
    [self addSubview:sw];
    
    if (tag == 1) self.espSwitch = sw;
    if (tag == 2) self.aimbotSwitch = sw;
    if (tag == 3) self.teamSwitch = sw;
    if (tag == 4) self.healthSwitch = sw;
    if (tag == 5) self.distanceSwitch = sw;
}

- (void)espChanged:(UISwitch*)sender { espEnabled = sender.isOn; }
- (void)aimbotChanged:(UISwitch*)sender { aimbotEnabled = sender.isOn; }
- (void)teamChanged:(UISwitch*)sender { showTeam = sender.isOn; }
- (void)healthChanged:(UISwitch*)sender { showHealth = sender.isOn; }
- (void)distanceChanged:(UISwitch*)sender { showDistance = sender.isOn; }

- (void)fovChanged:(UISlider*)sender { 
    aimFov = sender.value;
    self.fovLabel.text = [NSString stringWithFormat:@"%.1f", aimFov];
}

- (void)smoothChanged:(UISlider*)sender {
    aimSmooth = (int)sender.value;
    self.smoothLabel.text = [NSString stringWithFormat:@"%d", aimSmooth];
}

- (void)runTest {
    NSMutableString *log = [NSMutableString string];
    [log appendString:@"🔍 ТЕСТИРОВАНИЕ IL2CPP ФУНКЦИЙ\n"];
    [log appendString:@"================================\n\n"];
    
    uint64_t base = getBaseAddress();
    [log appendFormat:@"📌 Базовый адрес: 0x%llx\n\n", base];
    
    // Тест Camera
    [log appendString:@"📷 CAMERA\n"];
    Camera_main = (t_Camera_get_main)getRealPtr(RVA_Camera_get_main);
    [log appendFormat:@"   Camera.get_main(): %p - %@\n", Camera_main, Camera_main ? @"✅ OK" : @"❌ FAIL"];
    
    Camera_WorldToScreenPoint = (t_Camera_WorldToScreenPoint)getRealPtr(RVA_Camera_WorldToScreenPoint);
    [log appendFormat:@"   Camera.WorldToScreenPoint(): %p - %@\n", Camera_WorldToScreenPoint, Camera_WorldToScreenPoint ? @"✅ OK" : @"❌ FAIL"];
    
    Transform_get_position = (t_Transform_get_position)getRealPtr(RVA_Transform_get_position);
    [log appendFormat:@"   Transform.get_position(): %p - %@\n\n", Transform_get_position, Transform_get_position ? @"✅ OK" : @"❌ FAIL"];
    
    // Тест NetworkPlayer
    [log appendString:@"👤 NETWORK PLAYER\n"];
    NetworkPlayer_IsMine = (t_NetworkPlayer_IsMine)getRealPtr(RVA_NetworkPlayer_IsMine);
    [log appendFormat:@"   NetworkPlayer.IsMine(): %p - %@\n", NetworkPlayer_IsMine, NetworkPlayer_IsMine ? @"✅ OK" : @"❌ FAIL"];
    
    NetworkPlayer_IsDead = (t_NetworkPlayer_IsDead)getRealPtr(RVA_NetworkPlayer_IsDead);
    [log appendFormat:@"   NetworkPlayer.IsDead(): %p - %@\n", NetworkPlayer_IsDead, NetworkPlayer_IsDead ? @"✅ OK" : @"❌ FAIL"];
    
    NetworkPlayer_IsAlly = (t_NetworkPlayer_IsAlly)getRealPtr(RVA_NetworkPlayer_IsAlly);
    [log appendFormat:@"   NetworkPlayer.IsAlly(): %p - %@\n", NetworkPlayer_IsAlly, NetworkPlayer_IsAlly ? @"✅ OK" : @"❌ FAIL"];
    
    NetworkPlayer_GetHealth = (t_NetworkPlayer_GetHealth)getRealPtr(RVA_NetworkPlayer_GetHealth);
    [log appendFormat:@"   NetworkPlayer.GetHealth(): %p - %@\n", NetworkPlayer_GetHealth, NetworkPlayer_GetHealth ? @"✅ OK" : @"❌ FAIL"];
    
    NetworkPlayer_GetTransform = (t_NetworkPlayer_GetTransform)getRealPtr(RVA_NetworkPlayer_GetTransform);
    [log appendFormat:@"   NetworkPlayer.GetTransform(): %p - %@\n", NetworkPlayer_GetTransform, NetworkPlayer_GetTransform ? @"✅ OK" : @"❌ FAIL"];
    
    // Попытка вызвать функции
    [log appendString:@"\n🔄 ПОПЫТКА ВЫЗОВА\n"];
    if (Camera_main) {
        void *cam = Camera_main();
        [log appendFormat:@"   Camera.main() = %p\n", cam];
    }
    
    // Показываем окно с результатами
    TestResultWindow *resultWindow = [[TestResultWindow alloc] initWithFrame:CGRectMake(50, 100, 300, 400)];
    resultWindow.textView.text = log;
    resultWindow.hidden = NO;
    [resultWindow makeKeyAndVisible];
}

- (void)closeMenu {
    self.hidden = YES;
    [self removeFromSuperview];
}

@end

// ==================== ПЛАВАЮЩАЯ КНОПКА ====================
@interface FloatButton : UIButton
@property (nonatomic, strong) AimbotMenu *menu;
@property (nonatomic, assign) CGPoint initialCenter;
@end

@implementation FloatButton

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(20, 150, 60, 60)];
    if (self) {
        self.backgroundColor = [UIColor systemBlueColor];
        self.layer.cornerRadius = 30;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOffset = CGSizeMake(0, 2);
        self.layer.shadowOpacity = 0.5;
        [self setTitle:@"⚡" forState:UIControlStateNormal];
        self.titleLabel.font = [UIFont boldSystemFontOfSize:24];
        
        [self addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
        [self addGestureRecognizer:pan];
    }
    return self;
}

- (void)toggleMenu {
    if (self.menu && !self.menu.hidden) {
        self.menu.hidden = YES;
        [self.menu removeFromSuperview];
        self.menu = nil;
    } else {
        CGRect menuFrame = CGRectMake(50, 100, 280, 500);
        self.menu = [[AimbotMenu alloc] initWithFrame:menuFrame];
        self.menu.hidden = NO;
        [self.menu makeKeyAndVisible];
    }
}

- (void)pan:(UIPanGestureRecognizer*)gesture {
    CGPoint translation = [gesture translationInView:self.superview];
    CGPoint newCenter = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
    
    // Ограничиваем краями экрана
    CGRect bounds = self.superview.bounds;
    newCenter.x = MAX(self.frame.size.width/2, MIN(newCenter.x, bounds.size.width - self.frame.size.width/2));
    newCenter.y = MAX(self.frame.size.height/2, MIN(newCenter.y, bounds.size.height - self.frame.size.height/2));
    
    self.center = newCenter;
    [gesture setTranslation:CGPointZero inView:self.superview];
}

@end

// ==================== ИНИЦИАЛИЗАЦИЯ ====================
__attribute__((constructor))
static void init() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        UIWindow *win = getMainWindow();
        if (!win) return;
        
        // Загружаем все функции
        Camera_main = (t_Camera_get_main)getRealPtr(RVA_Camera_get_main);
        Camera_WorldToScreenPoint = (t_Camera_WorldToScreenPoint)getRealPtr(RVA_Camera_WorldToScreenPoint);
        Transform_get_position = (t_Transform_get_position)getRealPtr(RVA_Transform_get_position);
        
        NetworkPlayer_IsMine = (t_NetworkPlayer_IsMine)getRealPtr(RVA_NetworkPlayer_IsMine);
        NetworkPlayer_IsDead = (t_NetworkPlayer_IsDead)getRealPtr(RVA_NetworkPlayer_IsDead);
        NetworkPlayer_IsAlly = (t_NetworkPlayer_IsAlly)getRealPtr(RVA_NetworkPlayer_IsAlly);
        NetworkPlayer_GetHealth = (t_NetworkPlayer_GetHealth)getRealPtr(RVA_NetworkPlayer_GetHealth);
        NetworkPlayer_GetTransform = (t_NetworkPlayer_GetTransform)getRealPtr(RVA_NetworkPlayer_GetTransform);
        NetworkPlayer_GetLookPoint = (t_NetworkPlayer_GetLookPoint)getRealPtr(RVA_NetworkPlayer_GetLookPoint);
        
        // Создаем кнопку
        FloatButton *btn = [[FloatButton alloc] init];
        [win addSubview:btn];
        
        // Создаем ESP окно
        UIWindow *espWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        espWindow.windowLevel = UIWindowLevelNormal;
        espWindow.backgroundColor = [UIColor clearColor];
        espWindow.userInteractionEnabled = NO;
        
        ESPView *espView = [[ESPView alloc] initWithFrame:[UIScreen mainScreen].bounds];
        espView.backgroundColor = [UIColor clearColor];
        [espWindow addSubview:espView];
        
        [espWindow makeKeyAndVisible];
        
        // Таймер обновления ESP
        [NSTimer scheduledTimerWithTimeInterval:0.1
                                         target:[NSObject class]
                                       selector:@selector(refreshESP)
                                       userInfo:nil
                                        repeats:YES];
    });
}

void refreshESP() {
    // Обновляем ESPView
    UIWindow *espWindow = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if ([w.subviews.firstObject isKindOfClass:[ESPView class]]) {
            espWindow = w;
            break;
        }
    }
    [espWindow.subviews.firstObject setNeedsDisplay];
}
