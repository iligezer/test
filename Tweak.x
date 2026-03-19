#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ==================== ОБЪЯВЛЕНИЕ КЛАССОВ ====================

@interface Context : NSObject
+ (instancetype)create:(NSString *)name;
- (id)resolve:(Class)type;
@end

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

// ==================== ПЛАВАЮЩАЯ КНОПКА ====================

@interface FloatButton : UIImageView
@property (nonatomic, copy) void (^actionBlock)(void);
@property (nonatomic, assign) CGPoint initialCenter;
- (void)setAction:(void (^)(void))block;
@end

@implementation FloatButton

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(20, 100, 50, 50)];
    if (self) {
        self.backgroundColor = [UIColor systemBlueColor];
        self.layer.cornerRadius = 25;
        self.userInteractionEnabled = YES;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOffset = CGSizeMake(0, 2);
        self.layer.shadowOpacity = 0.5;
        self.layer.shadowRadius = 4;
        
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap)];
        [self addGestureRecognizer:tap];
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self addGestureRecognizer:pan];
    }
    return self;
}

- (void)handleTap {
    if (self.actionBlock) {
        self.actionBlock();
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    if (pan.state == UIGestureRecognizerStateBegan) {
        self.initialCenter = self.center;
    }
    
    CGPoint translation = [pan translationInView:self.superview];
    CGPoint newCenter = CGPointMake(self.initialCenter.x + translation.x, 
                                     self.initialCenter.y + translation.y);
    
    // Ограничения, чтобы кнопка не уходила за края
    CGFloat halfWidth = self.bounds.size.width / 2;
    CGFloat halfHeight = self.bounds.size.height / 2;
    newCenter.x = MAX(halfWidth, MIN(newCenter.x, self.superview.bounds.size.width - halfWidth));
    newCenter.y = MAX(halfHeight, MIN(newCenter.y, self.superview.bounds.size.height - halfHeight));
    
    self.center = newCenter;
}

- (void)setAction:(void (^)(void))block {
    self.actionBlock = block;
}

@end

// ==================== ОКНО ДЛЯ ЛОГОВ ====================

@interface LogWindow : UIWindow
@property (nonatomic, retain) UITextView *textView;
@property (nonatomic, retain) UIButton *closeButton;
@property (nonatomic, retain) UIButton *copyButton;
- (void)showLog:(NSString *)log;
@end

@implementation LogWindow

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(20, 100, [UIScreen mainScreen].bounds.size.width - 40, 300)];
    if (self) {
        self.windowLevel = UIWindowLevelAlert + 2;
        self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.9];
        self.layer.cornerRadius = 10;
        self.layer.borderColor = [UIColor whiteColor].CGColor;
        self.layer.borderWidth = 1;
        self.userInteractionEnabled = YES;
        
        // Заголовок
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, self.frame.size.width, 40)];
        title.text = @"📋 Логи ESP";
        title.textColor = [UIColor whiteColor];
        title.textAlignment = NSTextAlignmentCenter;
        title.font = [UIFont boldSystemFontOfSize:18];
        [self addSubview:title];
        
        // Текстовое поле
        _textView = [[UITextView alloc] initWithFrame:CGRectMake(10, 50, self.frame.size.width - 20, 200)];
        _textView.backgroundColor = [UIColor blackColor];
        _textView.textColor = [UIColor greenColor];
        _textView.font = [UIFont fontWithName:@"Courier" size:12];
        _textView.editable = NO;
        _textView.layer.cornerRadius = 5;
        [self addSubview:_textView];
        
        // Кнопка копирования
        _copyButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _copyButton.frame = CGRectMake(10, 260, 100, 30);
        [_copyButton setTitle:@"📋 Копировать" forState:UIControlStateNormal];
        [_copyButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        _copyButton.backgroundColor = [UIColor darkGrayColor];
        _copyButton.layer.cornerRadius = 5;
        [_copyButton addTarget:self action:@selector(copyLog) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_copyButton];
        
        // Кнопка закрытия
        _closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _closeButton.frame = CGRectMake(self.frame.size.width - 110, 260, 100, 30);
        [_closeButton setTitle:@"❌ Закрыть" forState:UIControlStateNormal];
        [_closeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        _closeButton.backgroundColor = [UIColor redColor];
        _closeButton.layer.cornerRadius = 5;
        [_closeButton addTarget:self action:@selector(closeLog) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_closeButton];
        
        self.hidden = YES;
    }
    return self;
}

- (void)showLog:(NSString *)log {
    _textView.text = log;
    self.hidden = NO;
    [self makeKeyAndVisible];
}

- (void)copyLog {
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    pasteboard.string = _textView.text;
    
    // Показываем уведомление
    UILabel *toast = [[UILabel alloc] initWithFrame:CGRectMake(50, 200, 200, 40)];
    toast.text = @"✅ Скопировано!";
    toast.textColor = [UIColor whiteColor];
    toast.backgroundColor = [UIColor blackColor];
    toast.textAlignment = NSTextAlignmentCenter;
    toast.layer.cornerRadius = 10;
    toast.clipsToBounds = YES;
    [self addSubview:toast];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [toast removeFromSuperview];
    });
}

- (void)closeLog {
    self.hidden = YES;
}

@end

// ==================== ESP ВЬЮ ====================

@interface ESPView : UIView {
    NSMutableArray *_enemies;
    UIFont *_espFont;
    BOOL _espEnabled;
    BOOL _espBox;
    BOOL _espHealth;
    BOOL _espDistance;
}
@property (nonatomic, retain) NSMutableArray *enemies;
@property (nonatomic, assign) BOOL espEnabled;
@property (nonatomic, assign) BOOL espBox;
@property (nonatomic, assign) BOOL espHealth;
@property (nonatomic, assign) BOOL espDistance;
- (void)updateEnemies:(NSArray *)enemies;
@end

@implementation ESPView
@synthesize enemies = _enemies;
@synthesize espEnabled = _espEnabled;
@synthesize espBox = _espBox;
@synthesize espHealth = _espHealth;
@synthesize espDistance = _espDistance;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        _enemies = [[NSMutableArray alloc] init];
        _espFont = [UIFont boldSystemFontOfSize:14];
        _espEnabled = YES;
        _espBox = YES;
        _espHealth = YES;
        _espDistance = YES;
    }
    return self;
}

- (void)dealloc {
    _enemies = nil;
    _espFont = nil;
}

- (void)updateEnemies:(NSArray *)enemies {
    @synchronized(self) {
        [_enemies removeAllObjects];
        [_enemies addObjectsFromArray:enemies];
    }
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    
    if (!_espEnabled) return;
    
    @synchronized(self) {
        CGContextRef ctx = UIGraphicsGetCurrentContext();
        
        for (NSDictionary *enemy in _enemies) {
            NSValue *screenPosValue = [enemy objectForKey:@"screenPos"];
            if (!screenPosValue) continue;
            
            CGPoint screenPos = [screenPosValue CGPointValue];
            float distance = [[enemy objectForKey:@"distance"] floatValue];
            BOOL isBot = [[enemy objectForKey:@"isBot"] boolValue];
            float health = [[enemy objectForKey:@"health"] floatValue];
            NSString *name = [enemy objectForKey:@"name"];
            
            if (screenPos.x < 0 || screenPos.x > self.frame.size.width || 
                screenPos.y < 0 || screenPos.y > self.frame.size.height) {
                continue;
            }
            
            UIColor *color = isBot ? [UIColor orangeColor] : [UIColor redColor];
            
            float boxSize = 60.0f;
            if (distance > 0) {
                boxSize = MIN(MAX(300.0f / distance, 30.0f), 120.0f);
            }
            
            // Рисуем прямоугольник
            if (_espBox) {
                CGRect box = CGRectMake(screenPos.x - boxSize/2, 
                                        screenPos.y - boxSize/2 - 15, 
                                        boxSize, boxSize);
                
                CGContextSetStrokeColorWithColor(ctx, color.CGColor);
                CGContextSetLineWidth(ctx, 2.0f);
                CGContextStrokeRect(ctx, box);
                
                CGContextSetStrokeColorWithColor(ctx, color.CGColor);
                CGContextSetLineWidth(ctx, 1.5f);
                CGContextMoveToPoint(ctx, screenPos.x, screenPos.y - boxSize/2 - 15);
                CGContextAddLineToPoint(ctx, screenPos.x, screenPos.y + boxSize/2 - 15);
                CGContextStrokePath(ctx);
            }
            
            // Рисуем здоровье
            if (_espHealth && health > 0) {
                CGRect healthBar = CGRectMake(screenPos.x - boxSize/2, 
                                              screenPos.y - boxSize/2 - 25, 
                                              boxSize * (health / 100.0f), 3);
                CGContextSetFillColorWithColor(ctx, [UIColor greenColor].CGColor);
                CGContextFillRect(ctx, healthBar);
            }
            
            // Рисуем дистанцию и имя
            if (_espDistance) {
                NSString *distanceText = [NSString stringWithFormat:@"%.1fм", distance];
                if (name) {
                    distanceText = [NSString stringWithFormat:@"%@\n%.1fм%@", name, distance, isBot ? @" (бот)" : @""];
                } else {
                    distanceText = [NSString stringWithFormat:@"%.1fм%@", distance, isBot ? @" (бот)" : @""];
                }
                
                NSDictionary *attrs = @{
                    NSFontAttributeName: _espFont,
                    NSForegroundColorAttributeName: [UIColor whiteColor]
                };
                [distanceText drawAtPoint:CGPointMake(screenPos.x - 40, screenPos.y - boxSize/2 - 40) 
                            withAttributes:attrs];
            }
        }
    }
}

@end

// ==================== ОСНОВНОЙ ТВИК ====================

@interface AimbotTweak : NSObject
@property (nonatomic, retain) UIWindow *espWindow;
@property (nonatomic, retain) ESPView *espView;
@property (nonatomic, retain) FloatButton *floatButton;
@property (nonatomic, retain) LogWindow *logWindow;
@property (nonatomic, assign) BOOL espEnabled;
@property (nonatomic, assign) BOOL espBox;
@property (nonatomic, assign) BOOL espHealth;
@property (nonatomic, assign) BOOL espDistance;
@property (nonatomic, retain) NSTimer *updateTimer;
@property (nonatomic, retain) NSMutableString *logBuffer;
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

- (id)init {
    self = [super init];
    if (self) {
        _espEnabled = YES;
        _espBox = YES;
        _espHealth = YES;
        _espDistance = YES;
        _logBuffer = [[NSMutableString alloc] init];
    }
    return self;
}

- (void)setupUI {
    // Создаём окно для ESP
    _espWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    _espWindow.windowLevel = UIWindowLevelAlert + 1;
    _espWindow.backgroundColor = [UIColor clearColor];
    _espWindow.userInteractionEnabled = NO;
    
    _espView = [[ESPView alloc] initWithFrame:_espWindow.bounds];
    _espView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _espView.espEnabled = _espEnabled;
    _espView.espBox = _espBox;
    _espView.espHealth = _espHealth;
    _espView.espDistance = _espDistance;
    [_espWindow addSubview:_espView];
    
    [_espWindow makeKeyAndVisible];
    
    // Создаём плавающую кнопку
    UIWindow *mainWindow = [UIApplication sharedApplication].keyWindow;
    _floatButton = [[FloatButton alloc] init];
    __weak typeof(self) weakSelf = self;
    [_floatButton setAction:^{
        [weakSelf showMenu];
    }];
    [mainWindow addSubview:_floatButton];
    
    // Создаём окно для логов
    _logWindow = [[LogWindow alloc] init];
    
    NSLog(@"[Aimbot] UI created");
}

- (void)showMenu {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🎯 Aimbot Menu"
                                                                   message:@"Выберите опции"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    // Переключатели ESP
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ ESP", _espEnabled ? @"✅" : @"❌"]
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *action) {
        self.espEnabled = !self.espEnabled;
        self.espView.espEnabled = self.espEnabled;
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ ESP Box", _espBox ? @"✅" : @"❌"]
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *action) {
        self.espBox = !self.espBox;
        self.espView.espBox = self.espBox;
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ ESP Health", _espHealth ? @"✅" : @"❌"]
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *action) {
        self.espHealth = !self.espHealth;
        self.espView.espHealth = self.espHealth;
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ ESP Distance", _espDistance ? @"✅" : @"❌"]
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *action) {
        self.espDistance = !self.espDistance;
        self.espView.espDistance = self.espDistance;
    }]];
    
    // Кнопка для логов
    [alert addAction:[UIAlertAction actionWithTitle:@"📋 Показать логи"
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *action) {
        [self showLogs];
    }]];
    
    // Кнопка закрытия
    [alert addAction:[UIAlertAction actionWithTitle:@"Закрыть"
                                               style:UIAlertActionStyleCancel
                                             handler:nil]];
    
    UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    
    // Для iPad
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self.floatButton;
        alert.popoverPresentationController.sourceRect = self.floatButton.bounds;
    }
    
    [rootVC presentViewController:alert animated:YES completion:nil];
}

- (void)showLogs {
    if (_logBuffer.length > 0) {
        [_logWindow showLog:_logBuffer];
    } else {
        [_logWindow showLog:@"Логов пока нет"];
    }
}

- (void)addLog:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    NSString *timestamp = [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                          dateStyle:NSDateFormatterShortStyle
                                                          timeStyle:NSDateFormatterMediumStyle];
    NSString *logLine = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];
    
    [_logBuffer appendString:logLine];
    NSLog(@"[Aimbot] %@", message);
}

- (float)distanceBetween:(id)pos1 and:(id)pos2 {
    float x1 = [[pos1 valueForKey:@"x"] floatValue];
    float y1 = [[pos1 valueForKey:@"y"] floatValue];
    float z1 = [[pos1 valueForKey:@"z"] floatValue];
    
    float x2 = [[pos2 valueForKey:@"x"] floatValue];
    float y2 = [[pos2 valueForKey:@"y"] floatValue];
    float z2 = [[pos2 valueForKey:@"z"] floatValue];
    
    float dx = x1 - x2;
    float dy = y1 - y2;
    float dz = z1 - z2;
    
    return sqrt(dx*dx + dy*dy + dz*dz);
}

- (void)startESP {
    [self setupUI];
    
    _updateTimer = [NSTimer scheduledTimerWithTimeInterval:0.033
                                                     target:self
                                                   selector:@selector(updateESP)
                                                   userInfo:nil
                                                    repeats:YES];
    
    [self addLog:@"ESP запущен"];
}

- (void)updateESP {
    if (!_espEnabled || !_espView) return;
    
    @autoreleasepool {
        Class contextClass = objc_getClass("Context");
        if (!contextClass) return;
        
        Context *context = [contextClass performSelector:@selector(create:) withObject:@"Gameplay"];
        if (!context) return;
        
        Class playersClass = objc_getClass("Players");
        if (!playersClass) return;
        
        Players *players = [context performSelector:@selector(resolve:) withObject:playersClass];
        if (!players) return;
        
        // Получаем локального игрока
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
        
        Class cameraClass = objc_getClass("Camera");
        if (!cameraClass) return;
        
        Camera *mainCamera = [cameraClass performSelector:@selector(main)];
        if (!mainCamera) return;
        
        NSArray *allPlayers = [players valueForKey:@"All"];
        if (!allPlayers) return;
        
        NSMutableArray *enemiesData = [NSMutableArray array];
        
        id localRootPoint = [localPlayer valueForKey:@"RootPoint"];
        if (!localRootPoint) return;
        
        id localPos = [localRootPoint valueForKey:@"position"];
        if (!localPos) return;
        
        int enemyCount = 0;
        
        for (id player in allPlayers) {
            @try {
                BOOL isMine = [[player valueForKey:@"IsMine"] boolValue];
                if (isMine) continue;
                
                BOOL isDead = [[player valueForKey:@"IsDead"] boolValue];
                if (isDead) continue;
                
                BOOL isAlly = [[player valueForKey:@"IsAllyOfLocalPlayer"] boolValue];
                if (isAlly) continue;
                
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
                
                CGPoint point = CGPointMake(x, [UIScreen mainScreen].bounds.size.height - y);
                
                float distance = [self distanceBetween:localPos and:worldPos];
                float health = [[player valueForKey:@"GetCurrentHealth"] floatValue];
                
                BOOL isBot = NO;
                NSString *playerName = @"Unknown";
                
                id quarkPlayer = [player valueForKey:@"QuarkPlayer"];
                if (quarkPlayer) {
                    isBot = [[quarkPlayer valueForKey:@"IsBot"] boolValue];
                    playerName = [quarkPlayer valueForKey:@"Username"];
                    if (!playerName) playerName = @"Bot";
                }
                
                [enemiesData addObject:@{
                    @"screenPos": [NSValue valueWithCGPoint:point],
                    @"distance": @(distance),
                    @"isBot": @(isBot),
                    @"health": @(health),
                    @"name": playerName ?: @""
                }];
                
                enemyCount++;
                
            } @catch (NSException *e) {
                [self addLog:@"Ошибка: %@", e];
            }
        }
        
        if (enemyCount > 0) {
            static int lastCount = 0;
            if (enemyCount != lastCount) {
                [self addLog:@"Найдено врагов: %d", enemyCount];
                lastCount = enemyCount;
            }
        }
        
        [_espView updateEnemies:enemiesData];
    }
}

@end

// ==================== ТОЧКА ВХОДА ====================
__attribute__((constructor))
static void init() {
    NSLog(@"[Aimbot] Загружается...");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        NSLog(@"[Aimbot] Инициализация...");
        
        AimbotTweak *tweak = [AimbotTweak sharedInstance];
        [tweak startESP];
        [tweak addLog:@"✅ Твик успешно загружен"];
        
        NSLog(@"[Aimbot] Готов к работе");
    });
}
