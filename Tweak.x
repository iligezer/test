#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// Путь для сохранения логов (тот, который ты просил)
#define LOG_FILE_PATH @"/var/mobile/Documents/modern/aimbot_log.txt"

// Функция для записи в лог (и в консоль, и в файл)
void writeLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    NSLog(@"[Aimbot] %@", message);
    
    // Добавляем timestamp
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    NSString *timestamp = [formatter stringFromDate:[NSDate date]];
    NSString *logEntry = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];
    
    // Сохраняем в файл
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *dirPath = [LOG_FILE_PATH stringByDeletingLastPathComponent];
    
    // Создаем папку, если её нет
    if (![fileManager fileExistsAtPath:dirPath]) {
        [fileManager createDirectoryAtPath:dirPath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    // Добавляем запись в конец файла
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:LOG_FILE_PATH];
    if (fileHandle) {
        [fileHandle seekToEndOfFile];
        [fileHandle writeData:[logEntry dataUsingEncoding:NSUTF8StringEncoding]];
        [fileHandle closeFile];
    } else {
        [logEntry writeToFile:LOG_FILE_PATH atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

// Интерфейс для плавающей кнопки (как в H5GG)
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
        self.image = nil; // убираем иконку, если её нет
        
        // Добавляем тап для обработки нажатия
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap)];
        [self addGestureRecognizer:tap];
        
        // Добавляем перетаскивание
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self addGestureRecognizer:pan];
    }
    return self;
}

- (void)handleTap {
    writeLog(@"Button tapped");
    if (self.actionBlock) {
        self.actionBlock();
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self.superview];
    self.center = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:self.superview];
}

- (void)setAction:(void (^)(void))block {
    self.actionBlock = block;
}

@end

// ============================================
// НОВЫЙ КЛАСС: ПРОЗРАЧНОЕ ОКНО (пропускает нажатия)
// ============================================
@interface PassthroughWindow : UIWindow
@property (nonatomic, weak) FloatButton *floatButton;
@property (nonatomic, weak) UIView *menuView;
@end

@implementation PassthroughWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    // 1. Находим стандартную view, в которую попал удар
    UIView *hitView = [super hitTest:point withEvent:event];
    
    // 2. Если мы вообще не попали ни во что, сразу возвращаем nil
    if (!hitView) {
        return nil;
    }
    
    // 3. Смотрим, является ли эта view нашей кнопкой или меню (или их сабвью)
    if (self.floatButton && (hitView == self.floatButton || [self.floatButton isDescendantOfView:hitView])) {
        return hitView;
    }
    if (self.menuView && (hitView == self.menuView || [self.menuView isDescendantOfView:hitView])) {
        return hitView;
    }
    
    // 4. Иначе (мы попали в пустую область окна) — возвращаем nil
    //    Это заставит iOS искать получателя касания в окнах ниже (игра)
    return nil;
}

@end

// ============================================
// ОСНОВНОЙ КЛАСС УПРАВЛЕНИЯ
// ============================================
@interface AimbotUI : NSObject
@property (nonatomic, strong) PassthroughWindow *window;  // ← ИЗМЕНЕНО: теперь PassthroughWindow
@property (nonatomic, strong) FloatButton *floatButton;
@property (nonatomic, strong) UIView *menuView;
@property (nonatomic, assign) BOOL menuVisible;
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
    writeLog(@"Setting up UI");
    
    // ========================================
    // 1. Создаем прозрачное окно (ИЗМЕНЕНО)
    // ========================================
    self.window = [[PassthroughWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.windowLevel = UIWindowLevelAlert + 1;
    self.window.backgroundColor = [UIColor clearColor];
    self.window.userInteractionEnabled = YES;
    self.window.hidden = NO;
    
    // ========================================
    // 2. Создаем плавающую кнопку
    // ========================================
    self.floatButton = [[FloatButton alloc] init];
    
    // Связываем кнопку с окном (чтобы hitTest мог её найти)
    self.window.floatButton = self.floatButton;
    [self.window addSubview:self.floatButton];
    
    // Устанавливаем действие для кнопки (weakSelf для избежания retain cycle)
    __weak typeof(self) weakSelf = self;
    [self.floatButton setAction:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) {
            [strongSelf toggleMenu];
        }
    }];
    
    // ========================================
    // 3. Создаем меню
    // ========================================
    self.menuView = [[UIView alloc] initWithFrame:CGRectMake(80, 160, 220, 200)];
    self.menuView.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.9];
    self.menuView.layer.cornerRadius = 10;
    self.menuView.layer.borderWidth = 1;
    self.menuView.layer.borderColor = [UIColor whiteColor].CGColor;
    self.menuView.hidden = YES;
    
    // Связываем меню с окном
    self.window.menuView = self.menuView;
    [self.window addSubview:self.menuView];
    
    // Заголовок
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, 220, 30)];
    titleLabel.text = @"Aimbot Menu";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.menuView addSubview:titleLabel];
    
    // Кнопка "Test"
    UIButton *testBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    testBtn.frame = CGRectMake(20, 50, 180, 40);
    [testBtn setTitle:@"Test Scan" forState:UIControlStateNormal];
    testBtn.backgroundColor = [UIColor lightGrayColor];
    [testBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    testBtn.layer.cornerRadius = 5;
    [testBtn addTarget:self action:@selector(testScan) forControlEvents:UIControlEventTouchUpInside];
    [self.menuView addSubview:testBtn];
    
    // Кнопка "Close"
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(20, 100, 180, 40);
    [closeBtn setTitle:@"Close Menu" forState:UIControlStateNormal];
    closeBtn.backgroundColor = [UIColor lightGrayColor];
    [closeBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    closeBtn.layer.cornerRadius = 5;
    [closeBtn addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    [self.menuView addSubview:closeBtn];
    
    writeLog(@"UI setup complete");
}

- (void)toggleMenu {
    self.menuVisible = !self.menuVisible;
    self.menuView.hidden = !self.menuVisible;
    writeLog(self.menuVisible ? @"Menu opened" : @"Menu closed");
}

- (void)testScan {
    writeLog(@"Test scan started");
    
    // Список классов для поиска (из Project.Game.dll)
    NSArray *classesToScan = @[
        @"GameManager",
        @"PlayerController",
        @"PlayerManager",
        @"EnemyController",
        @"WeaponController",
        @"CameraController"
    ];
    
    int found = 0;
    for (NSString *className in classesToScan) {
        Class cls = objc_getClass([className UTF8String]);
        if (cls) {
            writeLog([NSString stringWithFormat:@"✅ Found: %@", className]);
            found++;
        } else {
            writeLog([NSString stringWithFormat:@"❌ Not found: %@", className]);
        }
    }
    
    writeLog([NSString stringWithFormat:@"Test complete. Found %d/%lu classes", found, (unsigned long)classesToScan.count]);
}

@end

// ============================================
// КОНСТРУКТОР
// ============================================
static AimbotUI *g_ui = nil;

__attribute__((constructor))
static void init() {
    writeLog(@"=== AIMBOT TWEAK LOADED ===");
    
    // Ждем загрузки UI
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        g_ui = [[AimbotUI alloc] init];
    });
}
