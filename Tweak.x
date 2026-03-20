#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>

// ========== ТВОИ RVA ИЗ DUMP.CS ==========
#define RVA_GameManager_get_Instance      0x???????? // НУЖНО НАЙТИ!
#define RVA_GameManager_GetLocalPlayer    0x3839064
#define RVA_GameManager_GetAllPlayers     0x???????? // НУЖНО НАЙТИ!
#define RVA_Player_GetHealth               0x2EACF44
#define RVA_Player_GetTransform            0x2EA8C10
#define RVA_Transform_get_position          0x44CEED0

// ========== ТИПЫ ФУНКЦИЙ ==========
typedef void *(*t_GameManager_get_Instance)();
typedef void *(*t_GameManager_GetLocalPlayer)(void *gameManager);
typedef void *(*t_GameManager_GetAllPlayers)(void *gameManager);
typedef float (*t_Player_GetHealth)(void *player);
typedef void *(*t_Player_GetTransform)(void *player);
typedef void *(*t_Transform_get_position)(void *transform);

// ========== ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ ==========
static t_GameManager_GetLocalPlayer GameManager_GetLocalPlayer = NULL;
static t_Player_GetHealth Player_GetHealth = NULL;
static t_Player_GetTransform Player_GetTransform = NULL;
static t_Transform_get_position Transform_get_position = NULL;

static NSMutableString *logText = nil;
static UIWindow *logWindow = nil;
static UIButton *floatingButton = nil;

// ========== ПОЛУЧЕНИЕ БАЗОВОГО АДРЕСА ==========
uint64_t getBaseAddress() {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, "ModernStrike")) {
            return (uint64_t)_dyld_get_image_header(i);
        }
        if (name && strstr(name, "GameAssembly")) {
            return (uint64_t)_dyld_get_image_header(i);
        }
    }
    return 0;
}

void* getRealPtr(uint64_t rva) {
    uint64_t base = getBaseAddress();
    return base ? (void*)(base + rva) : NULL;
}

// ========== ИНИЦИАЛИЗАЦИЯ ==========
__attribute__((constructor))
static void init() {
    @autoreleasepool {
        logText = [[NSMutableString alloc] init];
        
        // Загружаем функции по RVA
        GameManager_GetLocalPlayer = (t_GameManager_GetLocalPlayer)getRealPtr(RVA_GameManager_GetLocalPlayer);
        Player_GetHealth = (t_Player_GetHealth)getRealPtr(RVA_Player_GetHealth);
        Player_GetTransform = (t_Player_GetTransform)getRealPtr(RVA_Player_GetTransform);
        Transform_get_position = (t_Transform_get_position)getRealPtr(RVA_Transform_get_position);
        
        [self addLog:@"✅ Функции загружены"];
        [self addLog:[NSString stringWithFormat:@"📌 Base: 0x%llx", getBaseAddress()]];
        [self addLog:[NSString stringWithFormat:@"📌 GetLocalPlayer: %p", GameManager_GetLocalPlayer]];
        
        // Ждем загрузки игры
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [self testLocalPlayer];
        });
    }
}

// ========== ТЕСТ ПОЛУЧЕНИЯ ЛОКАЛЬНОГО ИГРОКА ==========
+ (void)testLocalPlayer {
    [self addLog:@"\n🔍 Пробуем получить локального игрока..."];
    
    // Здесь нужен GameManager.Instance!
    // Без него мы не можем вызвать GetLocalPlayer
    [self addLog:@"❌ Нет RVA для GameManager.Instance"];
    [self addLog:@"📌 Нужно найти в dump.cs:"];
    [self addLog:@"   public static GameManager Instance { get; }"];
    
    [self showLog];
}

// ========== ЛОГ ==========
+ (void)addLog:(NSString *)text {
    if (!logText) logText = [[NSMutableString alloc] init];
    [logText appendFormat:@"%@\n", text];
    NSLog(@"%@", text);
}

+ (void)showLog {
    if (!logWindow) {
        logWindow = [[UIWindow alloc] initWithFrame:CGRectMake(20, 70, UIScreen.mainScreen.bounds.size.width-40, 400)];
        logWindow.windowLevel = UIWindowLevelAlert + 2;
        logWindow.backgroundColor = [UIColor colorWithWhite:0 alpha:0.95];
        
        UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(5, 5, logWindow.bounds.size.width-10, 340)];
        tv.backgroundColor = UIColor.blackColor;
        tv.textColor = UIColor.greenColor;
        tv.font = [UIFont fontWithName:@"Courier" size:10];
        tv.editable = NO;
        [logWindow addSubview:tv];
        
        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        closeBtn.frame = CGRectMake(logWindow.bounds.size.width-60, 350, 50, 30);
        [closeBtn setTitle:@"X" forState:UIControlStateNormal];
        [closeBtn addTarget:self action:@selector(hideLog) forControlEvents:UIControlEventTouchUpInside];
        [logWindow addSubview:closeBtn];
    }
    
    UITextView *tv = logWindow.subviews.firstObject;
    tv.text = logText;
    [logWindow makeKeyAndVisible];
}

+ (void)hideLog {
    logWindow.hidden = YES;
}

@end
