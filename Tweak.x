#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ==================== ОБЪЯВЛЕНИЯ КЛАССОВ ====================

// BehaviourInject
@interface Context : NSObject
+ (instancetype)create:(NSString *)name;
- (id)resolve:(Class)type;
@end

// Основные классы игры
@interface FirstPersonController : NSObject
- (id)RootPoint;
@end

@interface INetworkPlayer : NSObject
- (BOOL)IsMine;
- (BOOL)IsDead;
- (BOOL)IsAllyOfLocalPlayer;
- (id)Transform;
- (float)GetCurrentHealth;
- (id)QuarkPlayer;
@end

@interface QuarkRoomPlayer : NSObject
- (BOOL)IsBot;
- (NSString *)Username;
@end

@interface Camera : NSObject
+ (instancetype)main;
- (id)WorldToScreenPoint:(id)point;
@end

@interface Transform : NSObject
// Убираем прямой метод position, будем использовать valueForKey:
@end

@interface Vector3 : NSObject
// Убираем прямые методы x,y,z, будем использовать valueForKey:
@end

@interface Players : NSObject
- (id)All;
- (BOOL)TryGetCurrentController:(id *)controller;
@end

@interface GameManager : NSObject
+ (instancetype)sharedInstance;
- (id)getPlayers;
- (id)players;
@end

@interface RoomController : NSObject
+ (instancetype)instance;
+ (instancetype)sharedInstance;
- (id)getPlayers;
- (id)players;
@end

// ==================== ПЛАВАЮЩАЯ КНОПКА ====================

@interface MenuButton : UIButton
@end

static NSMutableString *logText = nil;
static int currentMethod = 0;
static BOOL espEnabled = YES;
static UIViewController *logViewController = nil;

@implementation MenuButton

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(20, 100, 50, 50)];
    if (self) {
        self.backgroundColor = [UIColor systemBlueColor];
        self.layer.cornerRadius = 25;
        [self addTarget:self action:@selector(showMenu) forControlEvents:UIControlEventTouchUpInside];
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
        [self addGestureRecognizer:pan];
        
        logText = [[NSMutableString alloc] init];
        [self addLog:@"=== Твик загружен ==="];
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

- (void)addLog:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"HH:mm:ss";
    NSString *time = [formatter stringFromDate:[NSDate date]];
    
    [logText appendFormat:@"[%@] %@\n", time, message];
    NSLog(@"[Aimbot] %@", message);
}

- (void)showMenu {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"ESP Диагностика"
                                                                   message:[NSString stringWithFormat:@"Текущий метод: %d\nESP: %@", currentMethod, espEnabled ? @"✅" : @"❌"]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ ESP", espEnabled ? @"✅" : @"❌"]
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *action) {
        espEnabled = !espEnabled;
        [self addLog:@"ESP переключен в %@", espEnabled ? @"ВКЛ" : @"ВЫКЛ"];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ Метод 0: Context Gameplay", currentMethod == 0 ? @"▶️" : @""]
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *action) {
        currentMethod = 0;
        [self addLog:@"Выбран метод 0 (Context Gameplay)"];
        [self runDiagnostics];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ Метод 1: Context Battle", currentMethod == 1 ? @"▶️" : @""]
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *action) {
        currentMethod = 1;
        [self addLog:@"Выбран метод 1 (Context Battle)"];
        [self runDiagnostics];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ Метод 2: GameManager", currentMethod == 2 ? @"▶️" : @""]
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *action) {
        currentMethod = 2;
        [self addLog:@"Выбран метод 2 (GameManager)"];
        [self runDiagnostics];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ Метод 3: RoomController", currentMethod == 3 ? @"▶️" : @""]
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *action) {
        currentMethod = 3;
        [self addLog:@"Выбран метод 3 (RoomController)"];
        [self runDiagnostics];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"🔍 Запустить диагностику"
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *action) {
        [self runDiagnostics];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"📋 Показать логи"
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *action) {
        [self showLogs];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"🗑 Очистить логи"
                                               style:UIAlertActionStyleDestructive
                                             handler:^(UIAlertAction *action) {
        [logText setString:@""];
        [self addLog:@"Логи очищены"];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Закрыть"
                                               style:UIAlertActionStyleCancel
                                             handler:nil]];
    
    UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (rootVC.presentedViewController) rootVC = rootVC.presentedViewController;
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self;
        alert.popoverPresentationController.sourceRect = self.bounds;
    }
    
    [rootVC presentViewController:alert animated:YES completion:nil];
}

- (void)runDiagnostics {
    [self addLog:@"=== ЗАПУСК ДИАГНОСТИКИ (метод %d) ===", currentMethod];
    
    [self checkClass:@"Context"];
    [self checkClass:@"Players"];
    [self checkClass:@"FirstPersonController"];
    [self checkClass:@"INetworkPlayer"];
    [self checkClass:@"Camera"];
    [self checkClass:@"GameManager"];
    [self checkClass:@"RoomController"];
    
    id players = [self getPlayersWithMethod:currentMethod];
    if (players) {
        [self addLog:@"✅ Players получен!"];
        [self testPlayers:players];
    } else {
        [self addLog:@"❌ Не удалось получить Players"];
    }
    
    [self addLog:@"=== ДИАГНОСТИКА ЗАВЕРШЕНА ==="];
}

- (void)checkClass:(NSString *)className {
    Class cls = objc_getClass([className UTF8String]);
    [self addLog:cls ? @"✅ %@ найден" : @"❌ %@ НЕ найден", className];
}

- (id)getPlayersWithMethod:(int)method {
    switch(method) {
        case 0: {
            [self addLog:@"▶️ Метод 0: Context Gameplay"];
            Class contextClass = objc_getClass("Context");
            if (!contextClass) { [self addLog:@"❌ Context class not found"]; return nil; }
            
            Context *context = [contextClass create:@"Gameplay"];
            if (!context) { [self addLog:@"❌ Failed to create Gameplay context"]; return nil; }
            [self addLog:@"✅ Context Gameplay создан"];
            
            Class playersClass = objc_getClass("Players");
            if (!playersClass) { [self addLog:@"❌ Players class not found"]; return nil; }
            
            id players = [context resolve:playersClass];
            if (players) [self addLog:@"✅ Players получен через resolve"];
            return players;
        }
        case 1: {
            [self addLog:@"▶️ Метод 1: Context Battle"];
            Class contextClass = objc_getClass("Context");
            if (!contextClass) { [self addLog:@"❌ Context class not found"]; return nil; }
            
            Context *context = [contextClass create:@"Battle"];
            if (!context) { [self addLog:@"❌ Failed to create Battle context"]; return nil; }
            [self addLog:@"✅ Context Battle создан"];
            
            Class playersClass = objc_getClass("Players");
            if (!playersClass) { [self addLog:@"❌ Players class not found"]; return nil; }
            
            id players = [context resolve:playersClass];
            if (players) [self addLog:@"✅ Players получен через resolve"];
            return players;
        }
        case 2: {
            [self addLog:@"▶️ Метод 2: GameManager"];
            Class gmClass = objc_getClass("GameManager");
            if (!gmClass) { [self addLog:@"❌ GameManager class not found"]; return nil; }
            
            id gm = [gmClass sharedInstance];
            if (!gm) { [self addLog:@"❌ sharedInstance вернул nil"]; return nil; }
            [self addLog:@"✅ GameManager instance получен"];
            
            id players = nil;
            
            if ([gm respondsToSelector:@selector(getPlayers)]) {
                players = [gm getPlayers];
                if (players) [self addLog:@"✅ Players получен через getPlayers"];
            }
            if (!players && [gm respondsToSelector:@selector(players)]) {
                players = [gm players];
                if (players) [self addLog:@"✅ Players получен через players"];
            }
            
            return players;
        }
        case 3: {
            [self addLog:@"▶️ Метод 3: RoomController"];
            Class rcClass = objc_getClass("RoomController");
            if (!rcClass) { [self addLog:@"❌ RoomController class not found"]; return nil; }
            
            id rc = nil;
            if ([rcClass respondsToSelector:@selector(instance)]) {
                rc = [rcClass instance];
            } else if ([rcClass respondsToSelector:@selector(sharedInstance)]) {
                rc = [rcClass sharedInstance];
            }
            
            if (!rc) { [self addLog:@"❌ instance/sharedInstance вернул nil"]; return nil; }
            [self addLog:@"✅ RoomController instance получен"];
            
            id players = nil;
            
            if ([rc respondsToSelector:@selector(getPlayers)]) {
                players = [rc getPlayers];
                if (players) [self addLog:@"✅ Players получен через getPlayers"];
            }
            if (!players && [rc respondsToSelector:@selector(players)]) {
                players = [rc players];
                if (players) [self addLog:@"✅ Players получен через players"];
            }
            
            return players;
        }
        default:
            return nil;
    }
}

- (void)testPlayers:(id)players {
    if ([players respondsToSelector:@selector(All)]) {
        NSArray *all = [players All];
        if (all) {
            [self addLog:@"✅ players.All работает, размер: %lu", (unsigned long)all.count];
            
            FirstPersonController *local = nil;
            if ([players respondsToSelector:@selector(TryGetCurrentController:)]) {
                BOOL hasLocal = [players TryGetCurrentController:&local];
                
                if (hasLocal && local) {
                    [self addLog:@"✅ TryGetCurrentController работает, local получен"];
                    
                    Camera *cam = [Camera main];
                    if (cam) {
                        [self addLog:@"✅ Camera.main работает"];
                        
                        // Проверяем позицию через valueForKey
                        id localRoot = [local valueForKey:@"RootPoint"];
                        if (localRoot) {
                            id localPos = [localRoot valueForKey:@"position"];
                            if (localPos) {
                                [self addLog:@"✅ local позиция получена через valueForKey"];
                            }
                        }
                    } else {
                        [self addLog:@"❌ Camera.main НЕ работает"];
                    }
                } else {
                    [self addLog:@"❌ TryGetCurrentController вернул NO"];
                }
            } else {
                [self addLog:@"❌ TryGetCurrentController метод отсутствует"];
            }
            
            int aliveCount = 0;
            int enemyCount = 0;
            for (id player in all) {
                BOOL isDead = NO;
                if ([player respondsToSelector:@selector(IsDead)]) {
                    isDead = [player IsDead];
                }
                if (!isDead) aliveCount++;
                
                BOOL isMine = NO;
                if ([player respondsToSelector:@selector(IsMine)]) {
                    isMine = [player IsMine];
                }
                
                if (!isMine) {
                    BOOL isAlly = NO;
                    if ([player respondsToSelector:@selector(IsAllyOfLocalPlayer)]) {
                        isAlly = [player IsAllyOfLocalPlayer];
                    }
                    if (!isAlly) enemyCount++;
                }
            }
            [self addLog:@"📊 Живых игроков: %d, Врагов: %d", aliveCount, enemyCount];
            
        } else {
            [self addLog:@"❌ players.All вернул nil"];
        }
    } else {
        [self addLog:@"❌ players не отвечает на All"];
    }
}

- (void)showLogs {
    if (!logViewController) {
        logViewController = [[UIViewController alloc] init];
        logViewController.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.9];
        logViewController.view.frame = [UIScreen mainScreen].bounds;
        
        UITextView *textView = [[UITextView alloc] initWithFrame:CGRectMake(20, 60, logViewController.view.frame.size.width - 40, logViewController.view.frame.size.height - 140)];
        textView.backgroundColor = [UIColor blackColor];
        textView.textColor = [UIColor greenColor];
        textView.font = [UIFont fontWithName:@"Courier" size:12];
        textView.editable = NO;
        textView.layer.cornerRadius = 10;
        textView.tag = 999;
        [logViewController.view addSubview:textView];
        
        UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        copyBtn.frame = CGRectMake(20, logViewController.view.frame.size.height - 70, 120, 40);
        [copyBtn setTitle:@"📋 Копировать" forState:UIControlStateNormal];
        [copyBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        copyBtn.backgroundColor = [UIColor darkGrayColor];
        copyBtn.layer.cornerRadius = 8;
        [copyBtn addTarget:self action:@selector(copyLogs) forControlEvents:UIControlEventTouchUpInside];
        [logViewController.view addSubview:copyBtn];
        
        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        closeBtn.frame = CGRectMake(logViewController.view.frame.size.width - 140, logViewController.view.frame.size.height - 70, 120, 40);
        [closeBtn setTitle:@"❌ Закрыть" forState:UIControlStateNormal];
        [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        closeBtn.backgroundColor = [UIColor redColor];
        closeBtn.layer.cornerRadius = 8;
        [closeBtn addTarget:self action:@selector(closeLogs) forControlEvents:UIControlEventTouchUpInside];
        [logViewController.view addSubview:closeBtn];
    }
    
    UITextView *tv = [logViewController.view viewWithTag:999];
    tv.text = logText;
    
    UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (rootVC.presentedViewController) rootVC = rootVC.presentedViewController;
    [rootVC presentViewController:logViewController animated:YES completion:nil];
}

- (void)copyLogs {
    UITextView *tv = [logViewController.view viewWithTag:999];
    [UIPasteboard generalPasteboard].string = tv.text;
    
    UILabel *toast = [[UILabel alloc] initWithFrame:CGRectMake(50, 200, 200, 40)];
    toast.text = @"✅ Скопировано!";
    toast.backgroundColor = [UIColor blackColor];
    toast.textColor = [UIColor whiteColor];
    toast.textAlignment = NSTextAlignmentCenter;
    toast.layer.cornerRadius = 10;
    toast.clipsToBounds = YES;
    [logViewController.view addSubview:toast];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [toast removeFromSuperview];
    });
}

- (void)closeLogs {
    [logViewController dismissViewControllerAnimated:YES completion:nil];
}

@end

// ==================== ESP ВЬЮ ====================

@interface ESPView : UIView {
    NSMutableArray *_enemies;
    UIFont *_espFont;
}
@property (nonatomic, retain) NSMutableArray *enemies;
- (void)updateEnemies:(NSArray *)enemies;
@end

@implementation ESPView
@synthesize enemies = _enemies;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        _enemies = [[NSMutableArray alloc] init];
        _espFont = [UIFont boldSystemFontOfSize:12];
        
        CADisplayLink *link = [CADisplayLink displayLinkWithTarget:self selector:@selector(redraw)];
        [link addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    }
    return self;
}

- (void)redraw {
    if (espEnabled) [self setNeedsDisplay];
}

- (void)updateEnemies:(NSArray *)enemies {
    @synchronized(self) {
        [_enemies removeAllObjects];
        [_enemies addObjectsFromArray:enemies];
    }
}

- (float)getFloat:(id)obj forKey:(NSString *)key {
    id value = [obj valueForKey:key];
    if (value && [value respondsToSelector:@selector(floatValue)]) {
        return [value floatValue];
    }
    return 0;
}

- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    if (!espEnabled || _enemies.count == 0) return;
    
    @autoreleasepool {
        CGContextRef ctx = UIGraphicsGetCurrentContext();
        
        for (NSDictionary *enemy in _enemies) {
            NSValue *screenPosValue = [enemy objectForKey:@"screenPos"];
            if (!screenPosValue) continue;
            
            CGPoint screenPos = [screenPosValue CGPointValue];
            float distance = [[enemy objectForKey:@"distance"] floatValue];
            float health = [[enemy objectForKey:@"health"] floatValue];
            
            if (screenPos.x < 0 || screenPos.x > self.frame.size.width || 
                screenPos.y < 0 || screenPos.y > self.frame.size.height) {
                continue;
            }
            
            float boxSize = MIN(MAX(300.0/distance, 20), 80);
            
            CGRect box = CGRectMake(screenPos.x - boxSize/2, screenPos.y - boxSize/2, boxSize, boxSize);
            CGContextSetStrokeColorWithColor(ctx, [UIColor redColor].CGColor);
            CGContextSetLineWidth(ctx, 2);
            CGContextStrokeRect(ctx, box);
            
            CGRect healthBar = CGRectMake(screenPos.x - boxSize/2, screenPos.y - boxSize/2 - 5, boxSize * (health/100), 2);
            CGContextSetFillColorWithColor(ctx, [UIColor greenColor].CGColor);
            CGContextFillRect(ctx, healthBar);
            
            NSString *distText = [NSString stringWithFormat:@"%.0fм", distance];
            [distText drawAtPoint:CGPointMake(screenPos.x - 20, screenPos.y - boxSize/2 - 20)
                    withAttributes:@{NSFontAttributeName: _espFont,
                                    NSForegroundColorAttributeName: [UIColor whiteColor]}];
        }
    }
}

@end

// ==================== ОСНОВНОЙ ТВИК ====================

@interface AimbotTweak : NSObject
@property (nonatomic, retain) UIWindow *espWindow;
@property (nonatomic, retain) ESPView *espView;
@property (nonatomic, retain) MenuButton *menuButton;
@end

@implementation AimbotTweak

+ (instancetype)sharedInstance {
    static AimbotTweak *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AimbotTweak alloc] init];
    });
    return instance;
}

- (void)start {
    _espWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    _espWindow.windowLevel = UIWindowLevelAlert + 1;
    _espWindow.backgroundColor = [UIColor clearColor];
    _espWindow.userInteractionEnabled = NO;
    
    _espView = [[ESPView alloc] initWithFrame:_espWindow.bounds];
    [_espWindow addSubview:_espView];
    [_espWindow makeKeyAndVisible];
    
    UIWindow *mainWindow = [UIApplication sharedApplication].keyWindow;
    _menuButton = [[MenuButton alloc] init];
    [mainWindow addSubview:_menuButton];
    
    [_menuButton addLog:@"✅ Интерфейс создан"];
    
    [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(updateESP) userInfo:nil repeats:YES];
}

- (void)updateESP {
    if (!espEnabled || !_espView) return;
    
    @autoreleasepool {
        id players = [self getPlayersWithMethod:currentMethod];
        if (!players) return;
        
        FirstPersonController *localPlayer = nil;
        if ([players respondsToSelector:@selector(TryGetCurrentController:)]) {
            BOOL hasLocal = [players TryGetCurrentController:&localPlayer];
            if (!hasLocal || !localPlayer) return;
        } else {
            return;
        }
        
        Camera *mainCamera = [Camera main];
        if (!mainCamera) return;
        
        NSArray *allPlayers = nil;
        if ([players respondsToSelector:@selector(All)]) {
            allPlayers = [players All];
        }
        if (!allPlayers) return;
        
        id localRoot = [localPlayer valueForKey:@"RootPoint"];
        if (!localRoot) return;
        
        id localPos = [localRoot valueForKey:@"position"];
        if (!localPos) return;
        
        NSMutableArray *enemiesData = [NSMutableArray array];
        
        for (id player in allPlayers) {
            @try {
                BOOL isMine = NO;
                if ([player respondsToSelector:@selector(IsMine)]) {
                    isMine = [player IsMine];
                }
                if (isMine) continue;
                
                BOOL isDead = NO;
                if ([player respondsToSelector:@selector(IsDead)]) {
                    isDead = [player IsDead];
                }
                if (isDead) continue;
                
                BOOL isAlly = NO;
                if ([player respondsToSelector:@selector(IsAllyOfLocalPlayer)]) {
                    isAlly = [player IsAllyOfLocalPlayer];
                }
                if (isAlly) continue;
                
                id transform = [player valueForKey:@"Transform"];
                if (!transform) continue;
                
                id worldPos = [transform valueForKey:@"position"];
                if (!worldPos) continue;
                
                id screenPos = [mainCamera WorldToScreenPoint:worldPos];
                if (!screenPos) continue;
                
                float z = [[screenPos valueForKey:@"z"] floatValue];
                if (z <= 0) continue;
                
                float x = [[screenPos valueForKey:@"x"] floatValue];
                float y = [[screenPos valueForKey:@"y"] floatValue];
                y = [UIScreen mainScreen].bounds.size.height - y;
                
                float localX = [[localPos valueForKey:@"x"] floatValue];
                float localY = [[localPos valueForKey:@"y"] floatValue];
                float localZ = [[localPos valueForKey:@"z"] floatValue];
                float worldX = [[worldPos valueForKey:@"x"] floatValue];
                float worldY = [[worldPos valueForKey:@"y"] floatValue];
                float worldZ = [[worldPos valueForKey:@"z"] floatValue];
                
                float distance = sqrt(pow(localX - worldX, 2) +
                                      pow(localY - worldY, 2) +
                                      pow(localZ - worldZ, 2));
                
                float health = 0;
                if ([player respondsToSelector:@selector(GetCurrentHealth)]) {
                    health = [player GetCurrentHealth];
                }
                
                [enemiesData addObject:@{
                    @"screenPos": [NSValue valueWithCGPoint:CGPointMake(x, y)],
                    @"distance": @(distance),
                    @"health": @(health)
                }];
            } @catch (NSException *e) {}
        }
        
        [_espView updateEnemies:enemiesData];
    }
}

- (id)getPlayersWithMethod:(int)method {
    switch(method) {
        case 0: {
            Class contextClass = objc_getClass("Context");
            if (!contextClass) return nil;
            Context *context = [contextClass create:@"Gameplay"];
            if (!context) return nil;
            Class playersClass = objc_getClass("Players");
            return [context resolve:playersClass];
        }
        case 1: {
            Class contextClass = objc_getClass("Context");
            if (!contextClass) return nil;
            Context *context = [contextClass create:@"Battle"];
            if (!context) return nil;
            Class playersClass = objc_getClass("Players");
            return [context resolve:playersClass];
        }
        case 2: {
            Class gmClass = objc_getClass("GameManager");
            if (!gmClass) return nil;
            id gm = [gmClass sharedInstance];
            if (!gm) return nil;
            
            if ([gm respondsToSelector:@selector(getPlayers)]) {
                return [gm getPlayers];
            }
            if ([gm respondsToSelector:@selector(players)]) {
                return [gm players];
            }
            return nil;
        }
        case 3: {
            Class rcClass = objc_getClass("RoomController");
            if (!rcClass) return nil;
            id rc = nil;
            if ([rcClass respondsToSelector:@selector(instance)]) {
                rc = [rcClass instance];
            } else if ([rcClass respondsToSelector:@selector(sharedInstance)]) {
                rc = [rcClass sharedInstance];
            }
            if (!rc) return nil;
            
            if ([rc respondsToSelector:@selector(getPlayers)]) {
                return [rc getPlayers];
            }
            if ([rc respondsToSelector:@selector(players)]) {
                return [rc players];
            }
            return nil;
        }
        default:
            return nil;
    }
}

@end

// ==================== ТОЧКА ВХОДА ====================
__attribute__((constructor))
static void init() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        AimbotTweak *tweak = [AimbotTweak sharedInstance];
        [tweak start];
    });
}
