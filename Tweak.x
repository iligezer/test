#import <UIKit/UIKit.h>
#import <substrate.h>
#import <mach-o/dyld.h>

// ==================== ФУНКЦИИ ДЛЯ РАБОТЫ С ПАМЯТЬЮ ====================

uint64_t getBaseAddress() {
    uint32_t count = _dyld_image_count();
    for(uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if(name != NULL && strstr(name, "ModernStrike") != NULL) {
            return (uint64_t)_dyld_get_image_header(i);
        }
        if(name != NULL && strstr(name, "GameAssembly") != NULL) {
            return (uint64_t)_dyld_get_image_header(i);
        }
    }
    return 0;
}

uint64_t getRealOffset(uint64_t rva) {
    uint64_t base = getBaseAddress();
    if(base == 0) return 0;
    return base + rva;
}

// ==================== RVA ИЗ ТВОИХ DLL ====================

#define RVA_Players_ctor                 0x3838ED4
#define RVA_Camera_get_main               0x445BAF8
#define RVA_Camera_WorldToScreenPoint     0x445AD5C
#define RVA_FirstPersonController_ctor    0x37F47A4
#define RVA_Transform_get_position        0x44CEED0
#define RVA_INetworkPlayer_IsMine          0x2EA8BE4
#define RVA_INetworkPlayer_IsDead          0x2EA2230
#define RVA_INetworkPlayer_IsAlly          0x2E9BE28
#define RVA_INetworkPlayer_GetHealth       0x2EACF44
#define RVA_INetworkPlayer_Transform       0x2EA8C10

// ==================== ТИПЫ ФУНКЦИЙ ====================

typedef void *(*t_Players_ctor)(void *playerProfileService);
typedef void *(*t_Camera_get_main)();
typedef void *(*t_Camera_WorldToScreenPoint)(void *camera, void *position);
typedef void *(*t_FirstPersonController_ctor)();
typedef void *(*t_Transform_get_position)(void *transform);
typedef bool (*t_INetworkPlayer_IsMine)(void *player);
typedef bool (*t_INetworkPlayer_IsDead)(void *player);
typedef bool (*t_INetworkPlayer_IsAlly)(void *player);
typedef float (*t_INetworkPlayer_GetHealth)(void *player);
typedef void *(*t_INetworkPlayer_Transform)(void *player);

// ==================== ПЛАВАЮЩАЯ КНОПКА ====================

@interface MenuButton : UIButton
@end

static BOOL espEnabled = YES;

@implementation MenuButton

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(20, 100, 50, 50)];
    if (self) {
        self.backgroundColor = [UIColor systemBlueColor];
        self.layer.cornerRadius = 25;
        [self addTarget:self action:@selector(toggleESP) forControlEvents:UIControlEventTouchUpInside];
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
        [self addGestureRecognizer:pan];
    }
    return self;
}

- (void)drag:(UIPanGestureRecognizer *)pan {
    if (pan.state == UIGestureRecognizerStateChanged) {
        CGPoint translation = [pan translationInView:self.superview];
        self.center = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
        [pan setTranslation:CGPointZero inView:self.superview];
    }
}

- (void)toggleESP {
    espEnabled = !espEnabled;
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"ESP"
                                                                   message:[NSString stringWithFormat:@"ESP %@", espEnabled ? @"ВКЛ" : @"ВЫКЛ"]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    
    UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (rootVC.presentedViewController) rootVC = rootVC.presentedViewController;
    [rootVC presentViewController:alert animated:YES completion:nil];
}

@end

// ==================== ESP ВЬЮ ====================

@interface ESPView : UIView
@end

@implementation ESPView

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        
        CADisplayLink *link = [CADisplayLink displayLinkWithTarget:self selector:@selector(update)];
        [link addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    }
    return self;
}

- (void)update {
    if (espEnabled) [self setNeedsDisplay];
}

// Получаем указатели на функции
- (void *)getPlayers {
    static void *(*Players_ctor)(void *) = NULL;
    if(Players_ctor == NULL) {
        Players_ctor = (void *(*)(void *))getRealOffset(RVA_Players_ctor);
    }
    
    // В ESP_FreeFire они создают Players через конструктор
    // Но нам нужен существующий экземпляр, а не новый
    // TODO: Нужен способ получить существующий Players
    
    return NULL;
}

- (void *)getLocalPlayer {
    // В ESP_FreeFire есть функция GetLocalPlayer
    // Нужно найти её RVA
    return NULL;
}

- (void *)getCamera {
    static t_Camera_get_main Camera_main = NULL;
    if(Camera_main == NULL) {
        Camera_main = (t_Camera_get_main)getRealOffset(RVA_Camera_get_main);
    }
    return Camera_main ? Camera_main() : NULL;
}

- (void *)getPlayerTransform:(void *)player {
    static t_INetworkPlayer_Transform getTransform = NULL;
    if(getTransform == NULL) {
        getTransform = (t_INetworkPlayer_Transform)getRealOffset(RVA_INetworkPlayer_Transform);
    }
    return getTransform ? getTransform(player) : NULL;
}

- (void *)getTransformPosition:(void *)transform {
    static t_Transform_get_position getPos = NULL;
    if(getPos == NULL) {
        getPos = (t_Transform_get_position)getRealOffset(RVA_Transform_get_position);
    }
    return getPos ? getPos(transform) : NULL;
}

- (bool)isPlayerMine:(void *)player {
    static t_INetworkPlayer_IsMine isMine = NULL;
    if(isMine == NULL) {
        isMine = (t_INetworkPlayer_IsMine)getRealOffset(RVA_INetworkPlayer_IsMine);
    }
    return isMine ? isMine(player) : false;
}

- (bool)isPlayerDead:(void *)player {
    static t_INetworkPlayer_IsDead isDead = NULL;
    if(isDead == NULL) {
        isDead = (t_INetworkPlayer_IsDead)getRealOffset(RVA_INetworkPlayer_IsDead);
    }
    return isDead ? isDead(player) : false;
}

- (bool)isPlayerAlly:(void *)player {
    static t_INetworkPlayer_IsAlly isAlly = NULL;
    if(isAlly == NULL) {
        isAlly = (t_INetworkPlayer_IsAlly)getRealOffset(RVA_INetworkPlayer_IsAlly);
    }
    return isAlly ? isAlly(player) : false;
}

- (float)getPlayerHealth:(void *)player {
    static t_INetworkPlayer_GetHealth getHealth = NULL;
    if(getHealth == NULL) {
        getHealth = (t_INetworkPlayer_GetHealth)getRealOffset(RVA_INetworkPlayer_GetHealth);
    }
    return getHealth ? getHealth(player) : 0;
}

- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    if(!espEnabled) return;
    
    @autoreleasepool {
        CGContextRef ctx = UIGraphicsGetCurrentContext();
        
        // TODO: Нужен способ получить список всех игроков
        // В ESP_FreeFire они получают Players и потом All
        
        // Временный код - рисуем тестовый прямоугольник
        CGRect box = CGRectMake(100, 100, 50, 50);
        CGContextSetStrokeColorWithColor(ctx, [UIColor redColor].CGColor);
        CGContextSetLineWidth(ctx, 2);
        CGContextStrokeRect(ctx, box);
        
        NSString *text = @"ESP АКТИВЕН";
        [text drawAtPoint:CGPointMake(50, 50)
            withAttributes:@{NSFontAttributeName: [UIFont systemFontOfSize:16],
                            NSForegroundColorAttributeName: [UIColor whiteColor]}];
    }
}

@end

// ==================== ТОЧКА ВХОДА ====================

__attribute__((constructor))
static void init() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        UIWindow *mainWindow = [UIApplication sharedApplication].keyWindow;
        
        // Кнопка
        MenuButton *btn = [[MenuButton alloc] init];
        [mainWindow addSubview:btn];
        
        // ESP окно
        UIWindow *espWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        espWindow.windowLevel = UIWindowLevelAlert + 1;
        espWindow.backgroundColor = [UIColor clearColor];
        espWindow.userInteractionEnabled = NO;
        [espWindow addSubview:[[ESPView alloc] initWithFrame:espWindow.bounds]];
        [espWindow makeKeyAndVisible];
        
        NSLog(@"[Aimbot] Загружено");
    });
}
