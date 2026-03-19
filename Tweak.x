#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>

// ========== ВСЕ RVA ИЗ ДАМПА ==========

// Players
#define RVA_Players_TryGetPlayer 0x382D754           // bool TryGetPlayer(int id, out INetworkPlayer player)
#define RVA_Players_get_CurrentPlayerId 0x3838D80    // int get_CurrentPlayerId()

// PlayerStatsTracker
#define RVA_PlayerStatsTracker_GetPlayersInMatch 0x344944C // int GetPlayersInMatch()

// NetworkPlayer - основные данные
#define RVA_NetworkPlayer_get_Id 0x37D927C            // int get_Id()
#define RVA_NetworkPlayer_get_IsMine 0x37D4F30        // bool get_IsMine()
#define RVA_NetworkPlayer_IsAllyOfLocalPlayer 0x37D973C // bool IsAllyOfLocalPlayer()
#define RVA_NetworkPlayer_get_IsAlly 0x37DAA38        // bool get_IsAlly()
#define RVA_NetworkPlayer_get_IsDead 0x37D9490        // bool get_IsDead()
#define RVA_NetworkPlayer_get_Health 0x37D970C        // float get_Health()
#define RVA_NetworkPlayer_get_Armor 0x37D96FC         // float get_Armor()
#define RVA_NetworkPlayer_get_Transform 0x37D9370     // Transform get_Transform()
#define RVA_NetworkPlayer_get_Name 0x37D401C          // string get_Name()
#define RVA_NetworkPlayer_get_Players 0x37D45A0       // Players get_Players()
#define RVA_NetworkPlayer_TryGetPlayerTransform 0x37DD1D8 // bool TryGetPlayerTransform(int id, out Transform transform)

// Transform
#define RVA_Transform_get_position 0x44CEED0          // Vector3 get_position()

// Camera
#define RVA_Camera_get_main 0x445BAF8                 // Camera get_main()
#define RVA_Camera_WorldToScreenPoint 0x445AD5C       // Vector3 WorldToScreenPoint(Vector3 position)

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

// Players
typedef bool (*t_Players_TryGetPlayer)(void *players, int id, void **player);
typedef int (*t_Players_get_CurrentPlayerId)(void *players);
typedef int (*t_PlayerStatsTracker_GetPlayersInMatch)();

// NetworkPlayer
typedef int (*t_NetworkPlayer_get_Id)(void *player);
typedef bool (*t_NetworkPlayer_get_IsMine)(void *player);
typedef bool (*t_NetworkPlayer_IsAllyOfLocalPlayer)(void *player);
typedef bool (*t_NetworkPlayer_get_IsAlly)(void *player);
typedef bool (*t_NetworkPlayer_get_IsDead)(void *player);
typedef float (*t_NetworkPlayer_get_Health)(void *player);
typedef float (*t_NetworkPlayer_get_Armor)(void *player);
typedef void* (*t_NetworkPlayer_get_Transform)(void *player);
typedef char* (*t_NetworkPlayer_get_Name)(void *player);
typedef void* (*t_NetworkPlayer_get_Players)(void *player);
typedef bool (*t_NetworkPlayer_TryGetPlayerTransform)(int id, void **transform);

// Transform
typedef void* (*t_Transform_get_position)(void *transform, void *outPosition);

// Camera
typedef void* (*t_Camera_get_main)();
typedef void* (*t_Camera_WorldToScreenPoint)(void *camera, void *worldPos, void *outScreenPos);

// ========== ГЛОБАЛЬНЫЕ УКАЗАТЕЛИ ==========
static t_Players_TryGetPlayer Players_TryGetPlayer = NULL;
static t_Players_get_CurrentPlayerId Players_get_CurrentPlayerId = NULL;
static t_PlayerStatsTracker_GetPlayersInMatch PlayerStatsTracker_GetPlayersInMatch = NULL;
static t_NetworkPlayer_get_Id NetworkPlayer_get_Id = NULL;
static t_NetworkPlayer_get_IsMine NetworkPlayer_get_IsMine = NULL;
static t_NetworkPlayer_IsAllyOfLocalPlayer NetworkPlayer_IsAllyOfLocalPlayer = NULL;
static t_NetworkPlayer_get_IsAlly NetworkPlayer_get_IsAlly = NULL;
static t_NetworkPlayer_get_IsDead NetworkPlayer_get_IsDead = NULL;
static t_NetworkPlayer_get_Health NetworkPlayer_get_Health = NULL;
static t_NetworkPlayer_get_Armor NetworkPlayer_get_Armor = NULL;
static t_NetworkPlayer_get_Transform NetworkPlayer_get_Transform = NULL;
static t_NetworkPlayer_get_Name NetworkPlayer_get_Name = NULL;
static t_NetworkPlayer_get_Players NetworkPlayer_get_Players = NULL;
static t_NetworkPlayer_TryGetPlayerTransform NetworkPlayer_TryGetPlayerTransform = NULL;
static t_Transform_get_position Transform_get_position = NULL;
static t_Camera_get_main Camera_get_main = NULL;
static t_Camera_WorldToScreenPoint Camera_WorldToScreenPoint = NULL;

static BOOL espEnabled = YES;
static UIWindow *overlayWindow = nil;
static NSMutableArray *playersList = nil;

// ========== ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ==========
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

// ========== ИНИЦИАЛИЗАЦИЯ ФУНКЦИЙ ==========
void initFunctions() {
    uint64_t base = getBaseAddress();
    NSLog(@"[Aimbot] Base address: 0x%llx", base);
    
    Players_TryGetPlayer = (t_Players_TryGetPlayer)(base + 0x382D754);
    Players_get_CurrentPlayerId = (t_Players_get_CurrentPlayerId)(base + 0x3838D80);
    PlayerStatsTracker_GetPlayersInMatch = (t_PlayerStatsTracker_GetPlayersInMatch)(base + 0x344944C);
    NetworkPlayer_get_Id = (t_NetworkPlayer_get_Id)(base + 0x37D927C);
    NetworkPlayer_get_IsMine = (t_NetworkPlayer_get_IsMine)(base + 0x37D4F30);
    NetworkPlayer_IsAllyOfLocalPlayer = (t_NetworkPlayer_IsAllyOfLocalPlayer)(base + 0x37D973C);
    NetworkPlayer_get_IsAlly = (t_NetworkPlayer_get_IsAlly)(base + 0x37DAA38);
    NetworkPlayer_get_IsDead = (t_NetworkPlayer_get_IsDead)(base + 0x37D9490);
    NetworkPlayer_get_Health = (t_NetworkPlayer_get_Health)(base + 0x37D970C);
    NetworkPlayer_get_Armor = (t_NetworkPlayer_get_Armor)(base + 0x37D96FC);
    NetworkPlayer_get_Transform = (t_NetworkPlayer_get_Transform)(base + 0x37D9370);
    NetworkPlayer_get_Name = (t_NetworkPlayer_get_Name)(base + 0x37D401C);
    NetworkPlayer_get_Players = (t_NetworkPlayer_get_Players)(base + 0x37D45A0);
    NetworkPlayer_TryGetPlayerTransform = (t_NetworkPlayer_TryGetPlayerTransform)(base + 0x37DD1D8);
    Transform_get_position = (t_Transform_get_position)(base + 0x44CEED0);
    Camera_get_main = (t_Camera_get_main)(base + 0x445BAF8);
    Camera_WorldToScreenPoint = (t_Camera_WorldToScreenPoint)(base + 0x445AD5C);
    
    NSLog(@"[Aimbot] Functions initialized");
}

// ========== ESP VIEW ==========
@interface ESPView : UIView
@property (nonatomic, strong) NSArray *players;
@end

@implementation ESPView

- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    
    if (!espEnabled) return;
    if (!Camera_get_main || !Camera_WorldToScreenPoint || !Transform_get_position) return;
    
    void *cam = Camera_get_main();
    if (!cam) return;
    
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetLineWidth(ctx, 2.0);
    
    // Рисуем каждого игрока
    for (NSValue *playerVal in self.players) {
        void *player = [playerVal pointerValue];
        if (!player) continue;
        
        // Пропускаем себя
        if (NetworkPlayer_get_IsMine && NetworkPlayer_get_IsMine(player)) continue;
        
        // Пропускаем мёртвых
        if (NetworkPlayer_get_IsDead && NetworkPlayer_get_IsDead(player)) continue;
        
        // Определяем цвет (союзник/враг)
        BOOL isAlly = NO;
        if (NetworkPlayer_IsAllyOfLocalPlayer) {
            isAlly = NetworkPlayer_IsAllyOfLocalPlayer(player);
        } else if (NetworkPlayer_get_IsAlly) {
            isAlly = NetworkPlayer_get_IsAlly(player);
        }
        
        CGContextSetStrokeColorWithColor(ctx, isAlly ? [UIColor greenColor].CGColor : [UIColor redColor].CGColor);
        CGContextSetFillColorWithColor(ctx, isAlly ? [UIColor colorWithRed:0 green:1 blue:0 alpha:0.3].CGColor : [UIColor colorWithRed:1 green:0 blue:0 alpha:0.3].CGColor);
        
        // Получаем трансформ и позицию
        void *transform = NetworkPlayer_get_Transform ? NetworkPlayer_get_Transform(player) : NULL;
        if (!transform) continue;
        
        // Получаем позицию (структура Vector3)
        struct Vector3 { float x, y, z; } worldPos;
        Transform_get_position(transform, &worldPos);
        
        // Конвертируем в экранные координаты
        struct Vector3 screenPos;
        Camera_WorldToScreenPoint(cam, &worldPos, &screenPos);
        
        // Рисуем только если игрок перед камерой
        if (screenPos.z > 0) {
            float size = 50.0f / screenPos.z; // Размер зависит от расстояния
            CGRect playerRect = CGRectMake(screenPos.x - size/2, [UIScreen mainScreen].bounds.size.height - screenPos.y - size/2, size, size);
            
            // Рисуем прямоугольник
            CGContextFillRect(ctx, playerRect);
            CGContextStrokeRect(ctx, playerRect);
            
            // Рисуем здоровье
            if (NetworkPlayer_get_Health) {
                float health = NetworkPlayer_get_Health(player);
                NSString *healthText = [NSString stringWithFormat:@"%.0f", health];
                [healthText drawAtPoint:CGPointMake(screenPos.x - 20, [UIScreen mainScreen].bounds.size.height - screenPos.y - size/2 - 20) withAttributes:@{NSFontAttributeName: [UIFont systemFontOfSize:12], NSForegroundColorAttributeName: [UIColor whiteColor]}];
            }
        }
    }
}

@end

// ========== ПОЛУЧЕНИЕ СПИСКА ИГРОКОВ ==========
NSArray* getPlayersList() {
    NSMutableArray *players = [NSMutableArray array];
    
    if (!PlayerStatsTracker_GetPlayersInMatch) return players;
    
    int playerCount = PlayerStatsTracker_GetPlayersInMatch();
    NSLog(@"[Aimbot] Players in match: %d", playerCount);
    
    // Перебираем возможные ID игроков
    for (int i = 0; i < playerCount + 10; i++) {
        void *transform = NULL;
        if (NetworkPlayer_TryGetPlayerTransform && NetworkPlayer_TryGetPlayerTransform(i, &transform) && transform) {
            // Нашли игрока, нужно получить его объект NetworkPlayer
            // TODO: получить NetworkPlayer из transform или по ID
            // Пока добавляем трансформ как заглушку
            [players addObject:[NSValue valueWithPointer:transform]];
        }
    }
    
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
    
    [alert addAction:[UIAlertAction actionWithTitle:@"📊 Обновить игроков"
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *a){
        playersList = [getPlayersList() mutableCopy];
        [(ESPView*)overlayWindow.subviews.firstObject setPlayers:playersList];
        [overlayWindow.subviews.firstObject setNeedsDisplay];
        
        UIAlertController *info = [UIAlertController alertControllerWithTitle:@"✅" message:[NSString stringWithFormat:@"Найдено игроков: %lu", (unsigned long)playersList.count] preferredStyle:UIAlertControllerStyleAlert];
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
            if (espEnabled) {
                playersList = [getPlayersList() mutableCopy];
                [(ESPView*)overlayWindow.subviews.firstObject setPlayers:playersList];
                [overlayWindow.subviews.firstObject setNeedsDisplay];
            }
        }];
        
        UIAlertController *ready = [UIAlertController alertControllerWithTitle:@"✅ Aimbot" message:@"Загружен" preferredStyle:UIAlertControllerStyleAlert];
        [ready addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [getTopViewController() presentViewController:ready animated:YES completion:nil];
    });
}
