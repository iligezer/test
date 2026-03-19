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
- (id)position;
@end

@interface Vector3 : NSObject
- (float)x;
- (float)y;
- (float)z;
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
static int currentMethod = 0; // 0-3 разные методы
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
    
    // Вкл/Выкл ESP
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ ESP", espEnabled ? @"✅" : @"❌"]
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *action) {
        espEnabled = !espEnabled;
        [self addLog:@"ESP переключен в %@", espEnabled ? @"ВКЛ" : @"ВЫКЛ"];
    }]];
    
    // Метод 0: Context Gameplay
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ Метод 0: Context Gameplay", currentMethod == 0 ? @"▶️" : @""]
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *action) {
        currentMethod = 0;
        [self addLog:@"Выбран метод 0 (Context Gameplay)"];
        [self runDiagnostics];
    }]];
    
    // Метод 1: Context Battle
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ Метод 1: Context Battle", currentMethod == 1 ? @"▶️" : @""]
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *action) {
        currentMethod = 1;
        [self addLog:@"Выбран метод 1 (Context Battle)"];
        [self runDiagnostics];
    }]];
    
    // Метод 2: GameManager
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ Метод 2: GameManager", currentMethod == 2 ? @"▶️" : @""]
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *action) {
        currentMethod = 2;
        [self addLog:@"Выбран метод 2 (GameManager)"];
        [self runDiagnostics];
    }]];
    
    // Метод 3: RoomController
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ Метод 3: RoomController", currentMethod == 3 ? @"▶️" : @""]
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *action) {
        currentMethod = 3;
        [self addLog:@"Выбран метод 3 (RoomController)"];
        [self runDiagnostics];
    }]];
    
    // Запустить диагностику
    [alert addAction:[UIAlertAction actionWithTitle:@"🔍 Запустить диагностику"
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *action) {
        [self runDiagnostics];
    }]];
    
    // Показать логи
    [alert addAction:[UIAlertAction actionWithTitle:@"📋 Показать логи"
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *action) {
        [self showLogs];
    }]];
    
    // Очистить логи
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
    
    // Проверяем базовые классы
    [self checkClass:@"Context"];
    [self checkClass:@"Players"];
    [self checkClass:@"FirstPersonController"];
    [self checkClass:@"INetworkPlayer"];
    [self checkClass:@"Camera"];
    [self checkClass:@"GameManager"];
    [self checkClass:@"RoomController"];
    
    // Тестируем выбранный метод
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
    if (cls) {
        [self addLog:@"✅ %@ найден", className];
    } else {
        [self addLog:@"❌ %@ НЕ найден", className];
    }
}

- (id)getPlayersWithMethod:(int)method {
    switch(method) {
        case 0: {
            [self addLog:@"▶️ Метод 0: Context Gameplay"];
            Class contextClass = objc_getClass("Context");
            if (!contextClass) { [self addLog:@"❌ Context class not found"]; return nil; }
            
            Context *context = [contextClass performSelector:@selector(create:) withObject:@"Gameplay"];
            if (!context) { [self addLog:@"❌ Failed to create Gameplay context"]; return nil; }
            [self addLog:@"✅ Context Gameplay создан"];
            
            Class playersClass = objc_getClass("Players");
            if (!playersClass) { [self addLog:@"❌ Players class not found"]; return nil; }
            
            id players = [context performSelector:@selector(resolve:) withObject:playersClass];
            if (players) [self addLog:@"✅ Players получен через resolve"];
            return players;
        }
        case 1: {
            [self addLog:@"▶️ Метод 1: Context Battle"];
            Class contextClass = objc_getClass("Context");
            if (!contextClass) { [self addLog:@"❌ Context class not found"]; return nil; }
            
            Context *context = [contextClass performSelector:@selector(create:) withObject:@"Battle"];
            if (!context) { [self addLog:@"❌ Failed to create Battle context"]; return nil; }
            [self addLog:@"✅ Context Battle создан"];
            
            Class playersClass = objc_getClass("Players");
            if (!playersClass) { [self addLog:@"❌ Players class not found"]; return nil; }
            
            id players = [context performSelector:@selector(resolve:) withObject:playersClass];
            if (players) [self addLog:@"✅ Players получен через resolve"];
            return players;
        }
        case 2: {
            [self addLog:@"▶️ Метод 2: GameManager"];
            Class gmClass = objc_getClass("GameManager");
            if (!gmClass) { [self addLog:@"❌ GameManager class not found"]; return nil; }
            
            id gm = [gmClass performSelector:@selector(sharedInstance)];
            if (!gm) { [self addLog:@"❌ sharedInstance вернул nil"]; return nil; }
            [self addLog:@"✅ GameManager instance получен"];
            
            // Пробуем разные названия методов
            id players = nil;
            SEL selectors[] = {@selector(getPlayers), @selector(players), @selector(GetPlayers), @selector(playerManager)};
            const char *names[] = {"getPlayers", "players", "GetPlayers", "playerManager"};
            
            for (int i = 0; i < 4; i++) {
                if ([gm respondsToSelector:selectors[i]]) {
                    players = [gm performSelector:selectors[i]];
                    if (players) {
                        [self addLog:@"✅ Players получен через %s", names[i]];
                        return players;
                    }
                }
            }
            [self addLog:@"❌ Не удалось получить Players из GameManager"];
            return nil;
        }
        case 3: {
            [self addLog:@"▶️ Метод 3: RoomController"];
            Class rcClass = objc_getClass("RoomController");
            if (!rcClass) { [self addLog:@"❌ RoomController class not found"]; return nil; }
            
            id rc = nil;
            if ([rcClass respondsToSelector:@selector(instance)]) {
                rc = [rcClass performSelector:@selector(instance)];
            } else if ([rcClass respondsToSelector:@selector(sharedInstance)]) {
                rc = [rcClass performSelector:@selector(sharedInstance)];
            }
            
            if (!rc) { [self addLog:@"❌ instance/sharedInstance вернул nil"]; return nil; }
            [self addLog:@"✅ RoomController instance получен"];
            
            // Пробуем разные названия методов
            id players = nil;
            SEL selectors[] = {@selector(getPlayers), @selector(players), @selector(GetPlayers), @selector(playerManager)};
            const char *names[] = {"getPlayers", "players", "GetPlayers", "playerManager"};
            
            for (int i = 0; i < 4; i++) {
                if ([rc respondsToSelector:selectors[i]]) {
                    players = [rc performSelector:selectors[i]];
                    if (players) {
                        [self addLog:@"✅ Players получен через %s", names[i]];
                        return players;
                    }
                }
            }
            [self addLog:@"❌ Не удалось получить Players из RoomController"];
            return nil;
        }
        default:
            return nil;
    }
}

- (void)testPlayers:(id)players {
    // Проверяем All
    if ([players respondsToSelector:@selector(All)]) {
        NSArray *all = [players valueForKey:@"All"];
        if (all) {
            [self addLog:@"✅ players.All работает, размер: %lu", (unsigned long)all.count];
            
            // Проверяем локального игрока
            FirstPersonController *local = nil;
            NSMethodSignature *sig = [players methodSignatureForSelector:@selector(TryGetCurrentController:)];
            if (sig) {
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                [inv setTarget:players];
                [inv setSelector:@selector(TryGetCurrentController:)];
                [inv setArgument:&local atIndex:2];
                [inv invoke];
                
                BOOL hasLocal = NO;
                [inv getReturnValue:&hasLocal];
                
                if (hasLocal && local) {
                    [self addLog:@"✅ TryGetCurrentController работает, local получен"];
                    
                    // Проверяем камеру
                    Camera *cam = [objc_getClass("Camera") performSelector:@selector(main)];
                    if (cam) {
                        [self addLog:@"✅ Camera.main работает"];
                        
                        // Проверяем конвертацию координат для первого врага
                        for (id player in all) {
                            BOOL isMine = [[player valueForKey:@"IsMine"] boolValue];
                            if (!isMine) {
                                id transform = [player valueForKey:@"Transform"];
                                if (transform) {
                                    id worldPos = [transform valueForKey:@"position"];
                                    if (worldPos) {
                                        id screenPos = [cam performSelector:@selector(WorldToScreenPoint:) withObject:worldPos];
                                        if (screenPos) {
                                            [self addLog:@"✅ WorldToScreenPoint работает"];
                                            float z = [[screenPos valueForKey:@"z"] floatValue];
                                            [self addLog:@"   Z-координата: %.2f", z];
                                        }
                                    }
                                }
                                break;
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
            
            // Считаем живых игроков
            int aliveCount = 0;
            int enemyCount = 0;
            for (id player in all) {
                BOOL isDead = [[player valueForKey:@"IsDead"] boolValue];
                if (!isDead) aliveCount++;
                
                BOOL isMine = [[player valueForKey:@"IsMine"] boolValue];
                if (!isMine) {
                    BOOL isAlly = [[player valueForKey:@"IsAllyOfLocalPlayer"] boolValue];
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

- (float)distanceBetween:(id)pos1 and:(id)pos2 {
    float x1 = [[pos1 valueForKey:@"x"] floatValue];
    float y1 = [[pos1 valueForKey:@"y"] floatValue];
    float z1 = [[pos1 valueForKey:@"z"] floatValue];
    float x2 = [[pos2 valueForKey:@"x"] floatValue];
    float y2 = [[pos2 valueForKey:@"y"] floatValue];
    float z2 = [[pos2 valueForKey:@"z"] floatValue];
    return sqrt(pow(x1-x2,2) + pow(y1-y2,2) + pow(z1-z2,2));
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
            
            // Прямоугольник
            CGRect box = CGRectMake(screenPos.x - boxSize/2, screenPos.y - boxSize/2, boxSize, boxSize);
            CGContextSetStrokeColorWithColor(ctx, [UIColor redColor].CGColor);
            CGContextSetLineWidth(ctx, 2);
            CGContextStrokeRect(ctx, box);
            
            // Полоска здоровья
            CGRect healthBar = CGRectMake(screenPos.x - boxSize/2, screenPos.y - boxSize/2 - 5, boxSize * (health/100), 2);
            CGContextSetFillColorWithColor(ctx, [UIColor greenColor].CGColor);
            CGContextFillRect(ctx, healthBar);
            
            // Дистанция
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
    // Создаём окно для ESP
    _espWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    _espWindow.windowLevel = UIWindowLevelAlert + 1;
    _espWindow.backgroundColor = [UIColor clearColor];
    _espWindow.userInteractionEnabled = NO;
    
    _espView = [[ESPView alloc] initWithFrame:_espWindow.bounds];
    [_espWindow addSubview:_espView];
    [_espWindow makeKeyAndVisible];
    
    // Создаём кнопку
    UIWindow *mainWindow = [UIApplication sharedApplication].keyWindow;
    _menuButton = [[MenuButton alloc] init];
    [mainWindow addSubview:_menuButton];
    
    [_menuButton addLog:@"✅ Интерфейс создан"];
    
    // Запускаем обновление ESP
    [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(updateESP) userInfo:nil repeats:YES];
}

- (void)updateESP {
    if (!espEnabled || !_espView) return;
    
    @autoreleasepool {
        id players = [self getPlayersWithMethod:currentMethod];
        if (!players) return;
        
        FirstPersonController *localPlayer = nil;
        NSMethodSignature *sig = [players methodSignatureForSelector:@selector(TryGetCurrentController:)];
        if (!sig) return;
        
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setTarget:players];
        [inv setSelector:@selector(TryGetCurrentController:)];
        [inv setArgument:&localPlayer atIndex:2];
        [inv invoke];
        
        BOOL hasLocal = NO;
        [inv getReturnValue:&hasLocal];
        if (!hasLocal || !localPlayer) return;
        
        Camera *mainCamera = [objc_getClass("Camera") performSelector:@selector(main)];
        if (!mainCamera) return;
        
        NSArray *allPlayers = [players valueForKey:@"All"];
        if (!allPlayers) return;
        
        id localRoot = [localPlayer valueForKey:@"RootPoint"];
        if (!localRoot) return;
        id localPos = [localRoot valueForKey:@"position"];
        if (!localPos) return;
        
        NSMutableArray *enemiesData = [NSMutableArray array];
        
        for (id player in allPlayers) {
            @try {
                if ([[player valueForKey:@"IsMine"] boolValue]) continue;
                if ([[player valueForKey:@"IsDead"] boolValue]) continue;
                if ([[player valueForKey:@"IsAllyOfLocalPlayer"] boolValue]) continue;
                
                id transform = [player valueForKey:@"Transform"];
                if (!transform) continue;
                
                id worldPos = [transform valueForKey:@"position"];
                if (!worldPos) continue;
                
                id screenPos = [mainCamera performSelector:@selector(WorldToScreenPoint:) withObject:worldPos];
                if (!screenPos) continue;
                
                float z = [[screenPos valueForKey:@"z"] floatValue];
                if (z <= 0) continue;
                
                float x = [[screenPos valueForKey:@"x"] floatValue];
                float y = [[screenPos valueForKey:@"y"] floatValue];
                y = [UIScreen mainScreen].bounds.size.height - y;
                
                float distance = sqrt(pow([[localPos valueForKey:@"x"] floatValue] - [[worldPos valueForKey:@"x"] floatValue], 2) +
                                      pow([[localPos valueForKey:@"y"] floatValue] - [[worldPos valueForKey:@"y"] floatValue], 2) +
                                      pow([[localPos valueForKey:@"z"] floatValue] - [[worldPos valueForKey:@"z"] floatValue], 2));
                
                float health = [[player valueForKey:@"GetCurrentHealth"] floatValue];
                
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
            Context *context = [contextClass performSelector:@selector(create:) withObject:@"Gameplay"];
            if (!context) return nil;
            Class playersClass = objc_getClass("Players");
            return [context performSelector:@selector(resolve:) withObject:playersClass];
        }
        case 1: {
            Class contextClass = objc_getClass("Context");
            if (!contextClass) return nil;
            Context *context = [contextClass performSelector:@selector(create:) withObject:@"Battle"];
            if (!context) return nil;
            Class playersClass = objc_getClass("Players");
            return [context performSelector:@selector(resolve:) withObject:playersClass];
        }
        case 2: {
            Class gmClass = objc_getClass("GameManager");
            if (!gmClass) return nil;
            id gm = [gmClass performSelector:@selector(sharedInstance)];
            if (!gm) return nil;
            id players = [gm performSelector:@selector(getPlayers)];
            if (!players) players = [gm performSelector:@selector(players)];
            return players;
        }
        case 3: {
            Class rcClass = objc_getClass("RoomController");
            if (!rcClass) return nil;
            id rc = [rcClass performSelector:@selector(instance)];
            if (!rc) rc = [rcClass performSelector:@selector(sharedInstance)];
            if (!rc) return nil;
            id players = [rc performSelector:@selector(getPlayers)];
            if (!players) players = [rc performSelector:@selector(players)];
            return players;
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
