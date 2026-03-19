#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ==================== ОБЪЯВЛЕНИЕ КЛАССОВ (IL2CPP) ====================

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

// ==================== ПРОСТОЙ ESP ВЬЮ ====================
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
        _espFont = [UIFont boldSystemFontOfSize:14];
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
    
    @synchronized(self) {
        CGContextRef ctx = UIGraphicsGetCurrentContext();
        
        for (NSDictionary *enemy in _enemies) {
            NSValue *screenPosValue = [enemy objectForKey:@"screenPos"];
            if (!screenPosValue) continue;
            
            CGPoint screenPos = [screenPosValue CGPointValue];
            float distance = [[enemy objectForKey:@"distance"] floatValue];
            BOOL isBot = [[enemy objectForKey:@"isBot"] boolValue];
            float health = [[enemy objectForKey:@"health"] floatValue];
            
            if (screenPos.x < 0 || screenPos.x > self.frame.size.width || 
                screenPos.y < 0 || screenPos.y > self.frame.size.height) {
                continue;
            }
            
            UIColor *color = isBot ? [UIColor orangeColor] : [UIColor redColor];
            
            float boxSize = 60.0f;
            if (distance > 0) {
                boxSize = MIN(MAX(300.0f / distance, 30.0f), 120.0f);
            }
            
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
            
            if (health > 0) {
                CGRect healthBar = CGRectMake(screenPos.x - boxSize/2, 
                                              screenPos.y - boxSize/2 - 25, 
                                              boxSize * (health / 100.0f), 3);
                CGContextSetFillColorWithColor(ctx, [UIColor greenColor].CGColor);
                CGContextFillRect(ctx, healthBar);
            }
            
            NSString *distanceText = [NSString stringWithFormat:@"%.1fм%@", distance, isBot ? @" (бот)" : @""];
            NSDictionary *attrs = @{
                NSFontAttributeName: _espFont,
                NSForegroundColorAttributeName: [UIColor whiteColor]
            };
            [distanceText drawAtPoint:CGPointMake(screenPos.x - 40, screenPos.y - boxSize/2 - 40) 
                        withAttributes:attrs];
        }
    }
}

@end

// ==================== ОСНОВНОЙ ТВИК ====================
@interface AimbotTweak : NSObject
@property (nonatomic, retain) UIWindow *espWindow;
@property (nonatomic, retain) ESPView *espView;
@property (nonatomic, assign) BOOL espEnabled;
@property (nonatomic, retain) NSTimer *updateTimer;
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
    }
    return self;
}

- (void)setupESP {
    if (_espWindow) return;
    
    _espWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    _espWindow.windowLevel = UIWindowLevelAlert + 1;
    _espWindow.backgroundColor = [UIColor clearColor];
    _espWindow.userInteractionEnabled = NO;
    
    _espView = [[ESPView alloc] initWithFrame:_espWindow.bounds];
    _espView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_espWindow addSubview:_espView];
    
    [_espWindow makeKeyAndVisible];
    
    NSLog(@"[Aimbot] ESP window created");
}

- (void)startESP {
    [self setupESP];
    
    _updateTimer = [NSTimer scheduledTimerWithTimeInterval:0.033
                                                     target:self
                                                   selector:@selector(updateESP)
                                                   userInfo:nil
                                                    repeats:YES];
}

- (float)distanceBetween:(id)pos1 and:(id)pos2 {
    // Получаем значения через KVC (без performSelector)
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

- (void)updateESP {
    if (!_espEnabled || !_espView) return;
    
    @autoreleasepool {
        // Получаем контекст Gameplay
        Class contextClass = objc_getClass("Context");
        if (!contextClass) {
            NSLog(@"[Aimbot] Context class not found");
            return;
        }
        
        Context *context = [contextClass performSelector:@selector(create:) withObject:@"Gameplay"];
        if (!context) {
            NSLog(@"[Aimbot] Failed to get Gameplay context");
            return;
        }
        
        // Получаем Players
        Class playersClass = objc_getClass("Players");
        if (!playersClass) {
            NSLog(@"[Aimbot] Players class not found");
            return;
        }
        
        Players *players = [context performSelector:@selector(resolve:) withObject:playersClass];
        if (!players) {
            NSLog(@"[Aimbot] Failed to resolve Players");
            return;
        }
        
        // Получаем локального игрока
        FirstPersonController *localPlayer = nil;
        NSMethodSignature *sig = [players methodSignatureForSelector:@selector(TryGetCurrentController:)];
        if (!sig) {
            NSLog(@"[Aimbot] No signature for TryGetCurrentController");
            return;
        }
        
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setTarget:players];
        [inv setSelector:@selector(TryGetCurrentController:)];
        [inv setArgument:&localPlayer atIndex:2];
        [inv invoke];
        
        BOOL hasLocal = NO;
        [inv getReturnValue:&hasLocal];
        
        if (!hasLocal || !localPlayer) {
            return;
        }
        
        // Получаем камеру
        Class cameraClass = objc_getClass("Camera");
        if (!cameraClass) return;
        
        Camera *mainCamera = [cameraClass performSelector:@selector(main)];
        if (!mainCamera) return;
        
        // Получаем список всех игроков
        NSArray *allPlayers = [players valueForKey:@"All"];
        if (!allPlayers) return;
        
        NSMutableArray *enemiesData = [NSMutableArray array];
        
        // Получаем позицию локального игрока
        id localRootPoint = [localPlayer valueForKey:@"RootPoint"];
        if (!localRootPoint) return;
        
        id localPos = [localRootPoint valueForKey:@"position"];
        if (!localPos) return;
        
        for (id player in allPlayers) {
            @try {
                // Проверяем через IsMine
                BOOL isMine = [[player valueForKey:@"IsMine"] boolValue];
                if (isMine) continue;
                
                // Проверяем жив ли
                BOOL isDead = [[player valueForKey:@"IsDead"] boolValue];
                if (isDead) continue;
                
                // Проверяем, враг ли
                BOOL isAlly = [[player valueForKey:@"IsAllyOfLocalPlayer"] boolValue];
                if (isAlly) continue;
                
                // Получаем позицию
                id transform = [player valueForKey:@"Transform"];
                if (!transform) continue;
                
                id worldPos = [transform valueForKey:@"position"];
                if (!worldPos) continue;
                
                // Конвертируем в экранные координаты
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
                id quarkPlayer = [player valueForKey:@"QuarkPlayer"];
                if (quarkPlayer) {
                    isBot = [[quarkPlayer valueForKey:@"IsBot"] boolValue];
                }
                
                [enemiesData addObject:@{
                    @"screenPos": [NSValue valueWithCGPoint:point],
                    @"distance": @(distance),
                    @"isBot": @(isBot),
                    @"health": @(health)
                }];
            } @catch (NSException *e) {
                NSLog(@"[Aimbot] Exception: %@", e);
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
        
        NSLog(@"[Aimbot] ESP запущен");
    });
}
