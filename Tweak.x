#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>

// ========== RVA ==========
#define RVA_Players_TryGetPlayer 0x382D754
#define RVA_Players_get_CurrentPlayerId 0x3838D80
#define RVA_PlayerStatsTracker_GetPlayersInMatch 0x344944C
#define RVA_NetworkPlayer_get_Id 0x37D927C
#define RVA_NetworkPlayer_get_IsMine 0x37D4F30
#define RVA_NetworkPlayer_IsAllyOfLocalPlayer 0x37D973C
#define RVA_NetworkPlayer_get_IsDead 0x37D9490
#define RVA_NetworkPlayer_get_Health 0x37D970C
#define RVA_NetworkPlayer_get_Transform 0x37D9370
#define RVA_NetworkPlayer_get_Players 0x37D45A0
#define RVA_NetworkPlayer_TryGetPlayerTransform 0x37DD1D8
#define RVA_Transform_get_position 0x44CEED0
#define RVA_Camera_get_main 0x445BAF8
#define RVA_Camera_WorldToScreenPoint 0x445AD5C

// ========== БАЗОВЫЙ АДРЕС ==========
uint64_t getBaseAddress() {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, "ModernStrike")) {
            return (uint64_t)_dyld_get_image_header(i);
        }
    }
    return 0;
}

void* getRealPtr(uint64_t rva) {
    uint64_t base = getBaseAddress();
    return base ? (void*)(base + rva) : NULL;
}

// ========== ТИПЫ ФУНКЦИЙ ==========
typedef bool (*t_Players_TryGetPlayer)(void *players, int id, void **player);
typedef int (*t_PlayerStatsTracker_GetPlayersInMatch)();
typedef int (*t_NetworkPlayer_get_Id)(void *player);
typedef bool (*t_NetworkPlayer_get_IsMine)(void *player);
typedef bool (*t_NetworkPlayer_IsAllyOfLocalPlayer)(void *player);
typedef bool (*t_NetworkPlayer_get_IsDead)(void *player);
typedef float (*t_NetworkPlayer_get_Health)(void *player);
typedef void* (*t_NetworkPlayer_get_Transform)(void *player);
typedef void* (*t_NetworkPlayer_get_Players)(void *player);
typedef bool (*t_NetworkPlayer_TryGetPlayerTransform)(int id, void **transform);
typedef void* (*t_Transform_get_position)(void *transform);
typedef void* (*t_Camera_get_main)();
typedef void* (*t_Camera_WorldToScreenPoint)(void *camera, void *worldPos);

// ========== ГЛОБАЛЬНЫЕ УКАЗАТЕЛИ ==========
static t_Players_TryGetPlayer Players_TryGetPlayer = NULL;
static t_PlayerStatsTracker_GetPlayersInMatch PlayerStatsTracker_GetPlayersInMatch = NULL;
static t_NetworkPlayer_get_IsMine NetworkPlayer_get_IsMine = NULL;
static t_NetworkPlayer_IsAllyOfLocalPlayer NetworkPlayer_IsAllyOfLocalPlayer = NULL;
static t_NetworkPlayer_get_IsDead NetworkPlayer_get_IsDead = NULL;
static t_NetworkPlayer_get_Health NetworkPlayer_get_Health = NULL;
static t_NetworkPlayer_get_Transform NetworkPlayer_get_Transform = NULL;
static t_Transform_get_position Transform_get_position = NULL;
static t_Camera_get_main Camera_get_main = NULL;
static t_Camera_WorldToScreenPoint Camera_WorldToScreenPoint = NULL;

static BOOL espEnabled = YES;
static UIWindow *overlayWindow = nil;
static NSMutableArray *playersList = nil;

// ========== ВСПОМОГАТЕЛЬНЫЕ ==========
UIWindow* getMainWindow() {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            for (UIWindow *window in ((UIWindowScene*)scene).windows) {
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

// ========== ПРОВЕРКА ФУНКЦИЙ ==========
BOOL areFunctionsValid() {
    return Players_TryGetPlayer != NULL &&
           PlayerStatsTracker_GetPlayersInMatch != NULL &&
           NetworkPlayer_get_IsMine != NULL &&
           NetworkPlayer_IsAllyOfLocalPlayer != NULL &&
           NetworkPlayer_get_IsDead != NULL &&
           NetworkPlayer_get_Health != NULL &&
           NetworkPlayer_get_Transform != NULL &&
           Transform_get_position != NULL &&
           Camera_get_main != NULL &&
           Camera_WorldToScreenPoint != NULL;
}

// ========== ИНИЦИАЛИЗАЦИЯ ==========
void initFunctions() {
    uint64_t base = getBaseAddress();
    NSLog(@"[Aimbot] Base: 0x%llx", base);
    
    if (base == 0) {
        NSLog(@"[Aimbot] ❌ Base address not found");
        return;
    }
    
    Players_TryGetPlayer = (t_Players_TryGetPlayer)getRealPtr(RVA_Players_TryGetPlayer);
    PlayerStatsTracker_GetPlayersInMatch = (t_PlayerStatsTracker_GetPlayersInMatch)getRealPtr(RVA_PlayerStatsTracker_GetPlayersInMatch);
    NetworkPlayer_get_IsMine = (t_NetworkPlayer_get_IsMine)getRealPtr(RVA_NetworkPlayer_get_IsMine);
    NetworkPlayer_IsAllyOfLocalPlayer = (t_NetworkPlayer_IsAllyOfLocalPlayer)getRealPtr(RVA_NetworkPlayer_IsAllyOfLocalPlayer);
    NetworkPlayer_get_IsDead = (t_NetworkPlayer_get_IsDead)getRealPtr(RVA_NetworkPlayer_get_IsDead);
    NetworkPlayer_get_Health = (t_NetworkPlayer_get_Health)getRealPtr(RVA_NetworkPlayer_get_Health);
    NetworkPlayer_get_Transform = (t_NetworkPlayer_get_Transform)getRealPtr(RVA_NetworkPlayer_get_Transform);
    Transform_get_position = (t_Transform_get_position)getRealPtr(RVA_Transform_get_position);
    Camera_get_main = (t_Camera_get_main)getRealPtr(RVA_Camera_get_main);
    Camera_WorldToScreenPoint = (t_Camera_WorldToScreenPoint)getRealPtr(RVA_Camera_WorldToScreenPoint);
    
    if (areFunctionsValid()) {
        NSLog(@"[Aimbot] ✅ All functions loaded");
    } else {
        NSLog(@"[Aimbot] ❌ Some functions missing");
    }
}

// ========== ESP VIEW ==========
@interface ESPView : UIView
@property (nonatomic, strong) NSArray *players;
@end

@implementation ESPView

- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    
    if (!espEnabled || !areFunctionsValid()) return;
    
    void *cam = Camera_get_main();
    if (!cam) return;
    
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetLineWidth(ctx, 2.0);
    
    for (NSValue *playerVal in self.players) {
        void *player = [playerVal pointerValue];
        if (!player) continue;
        
        @try {
            // Пропускаем себя
            if (NetworkPlayer_get_IsMine && NetworkPlayer_get_IsMine(player)) continue;
            
            // Пропускаем мёртвых
            if (NetworkPlayer_get_IsDead && NetworkPlayer_get_IsDead(player)) continue;
            
            // Союзник или враг
            BOOL isAlly = NO;
            if (NetworkPlayer_IsAllyOfLocalPlayer) {
                isAlly = NetworkPlayer_IsAllyOfLocalPlayer(player);
            }
            
            // Получаем трансформ и позицию
            void *transform = NetworkPlayer_get_Transform ? NetworkPlayer_get_Transform(player) : NULL;
            if (!transform) continue;
            
            void *worldPos = Transform_get_position(transform);
            if (!worldPos) continue;
            
            // Конвертируем в экранные координаты
            void *screenPos = Camera_WorldToScreenPoint(cam, worldPos);
            if (!screenPos) continue;
            
            // Читаем координаты (упрощённо)
            float *pos = (float*)screenPos;
            float x = pos[0];
            float y = pos[1];
            float z = pos[2];
            
            if (z > 0) {
                float size = 50.0f / z;
                CGRect playerRect = CGRectMake(x - size/2, [UIScreen mainScreen].bounds.size.height - y - size/2, size, size);
                
                CGContextSetStrokeColorWithColor(ctx, isAlly ? [UIColor greenColor].CGColor : [UIColor redColor].CGColor);
                CGContextSetFillColorWithColor(ctx, isAlly ? [UIColor colorWithRed:0 green:1 blue:0 alpha:0.3].CGColor : [UIColor colorWithRed:1 green:0 blue:0 alpha:0.3].CGColor);
                
                CGContextFillRect(ctx, playerRect);
                CGContextStrokeRect(ctx, playerRect);
                
                // Здоровье
                if (NetworkPlayer_get_Health) {
                    float health = NetworkPlayer_get_Health(player);
                    NSString *text = [NSString stringWithFormat:@"%.0f", health];
                    [text drawAtPoint:CGPointMake(x - 20, [UIScreen mainScreen].bounds.size.height - y - size/2 - 20) 
                           withAttributes:@{NSFontAttributeName: [UIFont systemFontOfSize:12], 
                                           NSForegroundColorAttributeName: [UIColor whiteColor]}];
                }
            }
        } @catch (NSException *e) {
            NSLog(@"[Aimbot] Exception: %@", e);
        }
    }
}

@end

// ========== ПОЛУЧЕНИЕ ИГРОКОВ ==========
NSArray* getPlayersList() {
    NSMutableArray *players = [NSMutableArray array];
    
    if (!areFunctionsValid()) return players;
    
    int playerCount = PlayerStatsTracker_GetPlayersInMatch();
    NSLog(@"[Aimbot] Player count: %d", playerCount);
    
    // TODO: Нужно получить объект Players и вызывать TryGetPlayer
    // Пока возвращаем пустой массив для теста
    
    return players;
}

// ========== МЕНЮ ==========
void showMenu() {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Aimbot Control"
                                                                   message:@""
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"ESP %@", espEnabled ? @"✅" : @"❌"]
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *a){
        espEnabled = !espEnabled;
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"📊 Тест функций"
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *a){
        NSString *status = areFunctionsValid() ? @"✅ Функции загружены" : @"❌ Функции не загружены";
        UIAlertController *info = [UIAlertController alertControllerWithTitle:@"Статус" message:status preferredStyle:UIAlertControllerStyleAlert];
        [info addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [getTopViewController() presentViewController:info animated:YES completion:nil];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"📊 Обновить игроков"
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *a){
        playersList = [getPlayersList() mutableCopy];
        [(ESPView*)overlayWindow.subviews.firstObject setPlayers:playersList];
        [overlayWindow.subviews.firstObject setNeedsDisplay];
        
        NSString *msg = [NSString stringWithFormat:@"Найдено: %lu", (unsigned long)playersList.count];
        UIAlertController *info = [UIAlertController alertControllerWithTitle:@"✅" message:msg preferredStyle:UIAlertControllerStyleAlert];
        [info addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [getTopViewController() presentViewController:info animated:YES completion:nil];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Отмена"
                                               style:UIAlertActionStyleCancel
                                             handler:nil]];
    
    [getTopViewController() presentViewController:alert animated:YES completion:nil];
}

// ========== ЗАГРУЗКА ==========
__attribute__((constructor))
static void init() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        initFunctions();
        
        UIWindow *mainWindow = getMainWindow();
        if (!mainWindow) return;
        
        // Кнопка меню
        UIButton *menuBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        menuBtn.frame = CGRectMake(20, 150, 60, 60);
        menuBtn.backgroundColor = [UIColor systemBlueColor];
        menuBtn.layer.cornerRadius = 30;
        [menuBtn setTitle:@"M" forState:UIControlStateNormal];
        [menuBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [menuBtn addTarget:[NSObject class] action:@selector(showMenu) forControlEvents:UIControlEventTouchUpInside];
        [mainWindow addSubview:menuBtn];
        
        // ESP окно
        overlayWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        overlayWindow.windowLevel = UIWindowLevelAlert + 1;
        overlayWindow.backgroundColor = [UIColor clearColor];
        overlayWindow.userInteractionEnabled = NO;
        
        ESPView *espView = [[ESPView alloc] initWithFrame:[UIScreen mainScreen].bounds];
        espView.backgroundColor = [UIColor clearColor];
        [overlayWindow addSubview:espView];
        [overlayWindow makeKeyAndVisible];
        
        // Таймер обновления
        [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t){
            if (espEnabled && areFunctionsValid()) {
                playersList = [getPlayersList() mutableCopy];
                [(ESPView*)overlayWindow.subviews.firstObject setPlayers:playersList];
                [overlayWindow.subviews.firstObject setNeedsDisplay];
            }
        }];
        
        NSString *status = areFunctionsValid() ? @"✅ Загружен" : @"❌ Ошибка загрузки";
        UIAlertController *ready = [UIAlertController alertControllerWithTitle:@"Aimbot" message:status preferredStyle:UIAlertControllerStyleAlert];
        [ready addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [getTopViewController() presentViewController:ready animated:YES completion:nil];
    });
}
