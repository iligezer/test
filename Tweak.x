#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach/mach.h>

// ============================================
// НАСТРОЙКИ
// ============================================
#define LOG_FILE_PATH @"/var/mobile/Documents/modern/aimbot_log.txt"

// ============================================
// ЛОГИРОВАНИЕ
// ============================================
void writeLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    NSLog(@"[Aimbot] %@", message);
    
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    NSString *timestamp = [formatter stringFromDate:[NSDate date]];
    NSString *logEntry = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dirPath = [LOG_FILE_PATH stringByDeletingLastPathComponent];
    if (![fm fileExistsAtPath:dirPath]) {
        [fm createDirectoryAtPath:dirPath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:LOG_FILE_PATH];
    if (fh) {
        [fh seekToEndOfFile];
        [fh writeData:[logEntry dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    } else {
        [logEntry writeToFile:LOG_FILE_PATH atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

// ============================================
// СКАНИРОВАНИЕ КЛАССОВ
// ============================================
void scanClasses() {
    writeLog(@"\n=== СКАНИРОВАНИЕ КЛАССОВ ===");
    
    NSArray *classNames = @[
        @"GameManager", @"PlayerManager", @"EnemyManager",
        @"PlayerController", @"EnemyController", @"WeaponController",
        @"CameraController"
    ];
    
    int found = 0;
    for (NSString *name in classNames) {
        Class cls = objc_getClass([name UTF8String]);
        if (cls) {
            writeLog([NSString stringWithFormat:@"✅ %@", name]);
            found++;
        }
    }
    
    writeLog([NSString stringWithFormat:@"📊 Найдено: %d из %lu", found, (unsigned long)classNames.count]);
}

// ============================================
// ПЛАВАЮЩАЯ КНОПКА
// ============================================
@interface FloatButton : UIImageView
@property (nonatomic, copy) void (^actionBlock)(void);
- (void)setAction:(void (^)(void))block;
@end

@implementation FloatButton

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(20, 100, 50, 50)];
    if (self) {
        self.backgroundColor = [UIColor systemBlueColor];
        self.layer.cornerRadius = 25;
        self.layer.borderWidth = 2;
        self.layer.borderColor = [UIColor whiteColor].CGColor;
        self.userInteractionEnabled = YES;
        
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap)];
        [self addGestureRecognizer:tap];
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self addGestureRecognizer:pan];
        
        writeLog(@"🔵 Кнопка создана, frame: %@", NSStringFromCGRect(self.frame));
    }
    return self;
}

- (void)handleTap {
    writeLog(@"🔵 Кнопка нажата (жест)");
    if (self.actionBlock) {
        self.actionBlock();
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.superview];
    self.center = CGPointMake(self.center.x + t.x, self.center.y + t.y);
    [g setTranslation:CGPointZero inView:self.superview];
}

- (void)setAction:(void (^)(void))block {
    self.actionBlock = block;
}

@end

// ============================================
// ПРОЗРАЧНОЕ ОКНО
// ============================================
@interface PassthroughWindow : UIWindow
@property (nonatomic, weak) FloatButton *floatButton;
@end

@implementation PassthroughWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    // Проверяем кнопку
    if (self.floatButton && !self.floatButton.hidden && self.floatButton.alpha > 0) {
        CGPoint buttonPoint = [self convertPoint:point toView:self.floatButton];
        if ([self.floatButton pointInside:buttonPoint withEvent:event]) {
            writeLog(@"👆 Касание по кнопке");
            return self.floatButton;
        }
    }
    // Всё остальное — пропускаем в игру
    return nil;
}

@end

// ============================================
// ОСНОВНОЙ КЛАСС
// ============================================
@interface AimbotUI : NSObject
@property (nonatomic, strong) PassthroughWindow *window;
@property (nonatomic, strong) FloatButton *floatButton;
@end

@implementation AimbotUI

- (instancetype)init {
    self = [super init];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    writeLog(@"Создание интерфейса...");
    
    // Создаём окно поверх игры
    self.window = [[PassthroughWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.windowLevel = UIWindowLevelNormal + 100; // гарантированно выше игры
    self.window.backgroundColor = [UIColor clearColor];
    self.window.hidden = NO;
    writeLog(@"Окно создано, уровень: %f", self.window.windowLevel);
    
    // Создаём кнопку
    self.floatButton = [[FloatButton alloc] init];
    self.window.floatButton = self.floatButton;
    [self.window addSubview:self.floatButton];
    writeLog(@"Кнопка добавлена в окно");
    
    // Действие на нажатие
    __weak typeof(self) weakSelf = self;
    [self.floatButton setAction:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) {
            writeLog(@"\n🔵 Кнопка нажата — запуск сканирования");
            scanClasses();
            writeLog(@"✅ Сканирование завершено");
        }
    }];
    
    writeLog(@"✅ Интерфейс создан. Жми синюю кнопку.");
}

@end

// ============================================
// КОНСТРУКТОР
// ============================================
static AimbotUI *g_ui = nil;

__attribute__((constructor))
static void init() {
    writeLog(@"\n=== AIMBOT ЗАГРУЖЕН ===");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        g_ui = [[AimbotUI alloc] init];
    });
}
