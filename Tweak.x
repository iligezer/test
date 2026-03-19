#import <UIKit/UIKit.h>
#import <substrate.h>
#import <mach-o/dyld.h>

// ==================== RVA ИЗ ТВОИХ DLL ====================

#define RVA_Players_All                     0x??? // Нужно найти где хранится список
#define RVA_Players_TryGetCurrentController  0x3839064
#define RVA_Camera_get_main                 0x445BAF8
#define RVA_Camera_WorldToScreenPoint        0x445AD5C
#define RVA_INetworkPlayer_IsMine             0x2EA8BE4
#define RVA_INetworkPlayer_IsDead             0x2EA2230
#define RVA_INetworkPlayer_IsAlly             0x2E9BE28
#define RVA_INetworkPlayer_GetHealth          0x2EACF44
#define RVA_INetworkPlayer_Transform          0x2EA8C10
#define RVA_Transform_get_position            0x44CEED0
#define RVA_FirstPersonController_RootPoint   0x170  // Это смещение поля, не RVA!

// ==================== ПОЛУЧЕНИЕ АДРЕСОВ ====================

uint64_t getBaseAddress() {
    uint32_t count = _dyld_image_count();
    for(uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if(name && strstr(name, "ModernStrike")) return (uint64_t)_dyld_get_image_header(i);
        if(name && strstr(name, "GameAssembly")) return (uint64_t)_dyld_get_image_header(i);
    }
    return 0;
}

uint64_t getRealOffset(uint64_t rva) {
    uint64_t base = getBaseAddress();
    return base ? base + rva : 0;
}

// ==================== ТИПЫ ФУНКЦИЙ ====================

typedef void *(*t_Camera_get_main)();
typedef void *(*t_Camera_WorldToScreenPoint)(void *camera, void *position);
typedef bool (*t_Players_TryGetCurrentController)(void *players, void **controller);
typedef bool (*t_INetworkPlayer_IsMine)(void *player);
typedef bool (*t_INetworkPlayer_IsDead)(void *player);
typedef bool (*t_INetworkPlayer_IsAlly)(void *player);
typedef float (*t_INetworkPlayer_GetHealth)(void *player);
typedef void *(*t_INetworkPlayer_Transform)(void *player);
typedef void *(*t_Transform_get_position)(void *transform);

// ==================== ГЛОБАЛЬНЫЕ УКАЗАТЕЛИ ====================

static t_Camera_get_main Camera_main = NULL;
static t_Camera_WorldToScreenPoint Camera_WorldToScreenPoint = NULL;
static t_Players_TryGetCurrentController Players_TryGetCurrentController = NULL;
static t_INetworkPlayer_IsMine INetworkPlayer_IsMine = NULL;
static t_INetworkPlayer_IsDead INetworkPlayer_IsDead = NULL;
static t_INetworkPlayer_IsAlly INetworkPlayer_IsAlly = NULL;
static t_INetworkPlayer_GetHealth INetworkPlayer_GetHealth = NULL;
static t_INetworkPlayer_Transform INetworkPlayer_Transform = NULL;
static t_Transform_get_position Transform_get_position = NULL;

// ==================== ИНИЦИАЛИЗАЦИЯ ====================

__attribute__((constructor))
static void init() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        // Загружаем все функции
        Camera_main = (t_Camera_get_main)getRealOffset(RVA_Camera_get_main);
        Camera_WorldToScreenPoint = (t_Camera_WorldToScreenPoint)getRealOffset(RVA_Camera_WorldToScreenPoint);
        Players_TryGetCurrentController = (t_Players_TryGetCurrentController)getRealOffset(RVA_Players_TryGetCurrentController);
        INetworkPlayer_IsMine = (t_INetworkPlayer_IsMine)getRealOffset(RVA_INetworkPlayer_IsMine);
        INetworkPlayer_IsDead = (t_INetworkPlayer_IsDead)getRealOffset(RVA_INetworkPlayer_IsDead);
        INetworkPlayer_IsAlly = (t_INetworkPlayer_IsAlly)getRealOffset(RVA_INetworkPlayer_IsAlly);
        INetworkPlayer_GetHealth = (t_INetworkPlayer_GetHealth)getRealOffset(RVA_INetworkPlayer_GetHealth);
        INetworkPlayer_Transform = (t_INetworkPlayer_Transform)getRealOffset(RVA_INetworkPlayer_Transform);
        Transform_get_position = (t_Transform_get_position)getRealOffset(RVA_Transform_get_position);
        
        NSLog(@"[Aimbot] Загружено %llx %llx", (uint64_t)Camera_main, (uint64_t)Players_TryGetCurrentController);
        
        UIWindow *mainWindow = [UIApplication sharedApplication].keyWindow;
        
        // Кнопка
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.frame = CGRectMake(20, 100, 50, 50);
        btn.backgroundColor = [UIColor systemBlueColor];
        btn.layer.cornerRadius = 25;
        [btn addTarget:self action:@selector(showMenu) forControlEvents:UIControlEventTouchUpInside];
        [mainWindow addSubview:btn];
        
        // ESP окно
        UIWindow *espWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        espWindow.windowLevel = UIWindowLevelAlert + 1;
        espWindow.backgroundColor = [UIColor clearColor];
        espWindow.userInteractionEnabled = NO;
        
        // TODO: Создать ESPView и добавить
        [espWindow makeKeyAndVisible];
    });
}
