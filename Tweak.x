#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ===== ФУНКЦИЯ ПОКАЗА РЕЗУЛЬТАТОВ =====
void showResultWindow(NSString *text) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = nil;
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *ws = (UIWindowScene *)scene;
                for (UIWindow *w in ws.windows) {
                    if (w.isKeyWindow) {
                        keyWindow = w;
                        break;
                    }
                }
            }
            if (keyWindow) break;
        }
        
        if (!keyWindow) return;
        
        UIWindow *resultWindow = [[UIWindow alloc] initWithFrame:CGRectMake(20, 100, keyWindow.frame.size.width - 40, 400)];
        resultWindow.windowLevel = UIWindowLevelAlert + 2;
        resultWindow.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
        resultWindow.layer.cornerRadius = 15;
        resultWindow.hidden = NO;
        
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, resultWindow.frame.size.width, 40)];
        title.text = @"🎯 РЕЗУЛЬТАТ";
        title.textColor = [UIColor whiteColor];
        title.textAlignment = NSTextAlignmentCenter;
        title.font = [UIFont boldSystemFontOfSize:18];
        [resultWindow addSubview:title];
        
        UITextView *textView = [[UITextView alloc] initWithFrame:CGRectMake(10, 60, resultWindow.frame.size.width - 20, 260)];
        textView.backgroundColor = [UIColor blackColor];
        textView.textColor = [UIColor greenColor];
        textView.font = [UIFont fontWithName:@"Courier" size:12];
        textView.text = text;
        textView.editable = NO;
        textView.selectable = YES;
        [resultWindow addSubview:textView];
        
        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        closeBtn.frame = CGRectMake(resultWindow.frame.size.width/2 - 50, 340, 100, 40);
        [closeBtn setTitle:@"Закрыть" forState:UIControlStateNormal];
        closeBtn.backgroundColor = [UIColor systemBlueColor];
        [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        closeBtn.layer.cornerRadius = 8;
        [closeBtn addTarget:resultWindow action:@selector(setHidden:) forControlEvents:UIControlEventTouchUpInside];
        [resultWindow addSubview:closeBtn];
        
        [resultWindow makeKeyAndVisible];
    });
}

// ===== ГЛАВНАЯ ФУНКЦИЯ ВКЛЮЧЕНИЯ АИМБОТА =====
NSString* enableAimbot() {
    NSMutableString *log = [NSMutableString stringWithString:@"🔧 ВКЛЮЧЕНИЕ АИМБОТА\n\n"];
    
    // Путь к папке с данными приложений
    NSString *dataPath = @"/var/mobile/Containers/Data/Application/";
    NSFileManager *fm = [NSFileManager defaultManager];
    
    // Ищем папку игры
    NSArray *apps = [fm contentsOfDirectoryAtPath:dataPath error:nil];
    NSString *prefsPath = nil;
    
    for (NSString *appId in apps) {
        NSString *libPath = [dataPath stringByAppendingPathComponent:appId];
        libPath = [libPath stringByAppendingPathComponent:@"Library/Preferences"];
        NSString *plistPath = [libPath stringByAppendingPathComponent:@"com.gamedevltd.modernstrikeonline.plist"];
        
        if ([fm fileExistsAtPath:plistPath]) {
            prefsPath = plistPath;
            [log appendFormat:@"📂 Найден файл настроек:\n%@\n", plistPath];
            break;
        }
    }
    
    if (!prefsPath) {
        [log appendString:@"❌ Файл настроек не найден!"];
        return log;
    }
    
    // Читаем текущие настройки
    NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:prefsPath];
    if (!prefs) {
        prefs = [NSMutableDictionary dictionary];
        [log appendString:@"📝 Создан новый файл настроек\n"];
    }
    
    // Сохраняем старые значения
    NSNumber *oldAutoAim = prefs[@"AutoAim"];
    NSNumber *oldAutoShoot = prefs[@"AutoShoot"];
    NSNumber *oldNoAds = prefs[@"DoNotShowAds"];
    
    [log appendString:@"\n📊 ТЕКУЩИЕ НАСТРОЙКИ:\n"];
    [log appendFormat:@"AutoAim: %@\n", oldAutoAim ? oldAutoAim : @"(не задано)"];
    [log appendFormat:@"AutoShoot: %@\n", oldAutoShoot ? oldAutoShoot : @"(не задано)"];
    [log appendFormat:@"DoNotShowAds: %@\n", oldNoAds ? oldNoAds : @"(не задано)"];
    
    // УСТАНАВЛИВАЕМ НОВЫЕ ЗНАЧЕНИЯ (из найденных файлов)
    prefs[@"AutoAim"] = @(1);      // Включаем аимбот
    prefs[@"AutoShoot"] = @(1);    // Включаем авто-стрельбу
    prefs[@"DoNotShowAds"] = @(1); // Отключаем рекламу
    prefs[@"Max"] = @(9);           // Открываем все уровни
    prefs[@"SelectedLevel"] = @(8); // Последний уровень
    
    // Разблокируем всё оружие (из CustomWeaponSelector.cs)
    for (int i = 0; i < 10; i++) {
        prefs[[NSString stringWithFormat:@"WeaponUnlocked%d", i]] = @(0);
    }
    
    // Сохраняем
    BOOL saved = [prefs writeToFile:prefsPath atomically:YES];
    
    if (saved) {
        [log appendString:@"\n✅ НАСТРОЙКИ УСПЕШНО СОХРАНЕНЫ!\n"];
        [log appendString:@"\n🎯 AutoAim = 1 (аимбот включен)"];
        [log appendString:@"\n🔫 AutoShoot = 1 (авто-стрельба)"];
        [log appendString:@"\n🚫 DoNotShowAds = 1 (рекламы нет)"];
        [log appendString:@"\n🔓 Все уровни открыты"];
        [log appendString:@"\n🔓 Все оружие разблокировано"];
        [log appendString:@"\n\n⚠️ ПЕРЕЗАПУСТИТЕ ИГРУ для применения!"];
    } else {
        [log appendString:@"\n❌ ОШИБКА СОХРАНЕНИЯ!"];
    }
    
    return log;
}

// ===== ПЛАВАЮЩАЯ КНОПКА =====
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
    }
    return self;
}

- (void)handleTap {
    if (self.actionBlock) self.actionBlock();
}

- (void)setAction:(void (^)(void))block {
    self.actionBlock = block;
}

@end

// ===== ОКНО, ПРОПУСКАЮЩЕЕ КАСАНИЯ =====
@interface PassthroughWindow : UIWindow
@property (nonatomic, weak) FloatButton *floatButton;
@property (nonatomic, weak) UIView *menuView;
@end

@implementation PassthroughWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.floatButton && !self.floatButton.hidden) {
        CGPoint buttonPoint = [self convertPoint:point toView:self.floatButton];
        if ([self.floatButton pointInside:buttonPoint withEvent:event]) {
            return self.floatButton;
        }
    }
    if (self.menuView && !self.menuView.hidden) {
        CGPoint menuPoint = [self convertPoint:point toView:self.menuView];
        if ([self.menuView pointInside:menuPoint withEvent:event]) {
            return [self.menuView hitTest:menuPoint withEvent:event];
        }
    }
    return nil;
}

@end

// ===== UI ТВИКА =====
@interface AimbotUI : NSObject
@property (nonatomic, strong) PassthroughWindow *window;
@property (nonatomic, strong) FloatButton *floatButton;
@property (nonatomic, strong) UIView *menuView;
@property (nonatomic, assign) BOOL menuVisible;
@end

@implementation AimbotUI

- (instancetype)init {
    self = [super init];
    if (self) [self setupUI];
    return self;
}

- (void)setupUI {
    self.window = [[PassthroughWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.windowLevel = UIWindowLevelAlert + 1;
    self.window.backgroundColor = [UIColor clearColor];
    self.window.hidden = NO;
    
    self.floatButton = [[FloatButton alloc] init];
    self.window.floatButton = self.floatButton;
    [self.window addSubview:self.floatButton];
    
    __weak typeof(self) weakSelf = self;
    [self.floatButton setAction:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) {
            [strongSelf toggleMenu];
        }
    }];
    
    [self buildMenu];
}

- (void)buildMenu {
    self.menuView = [[UIView alloc] initWithFrame:CGRectMake(80, 160, 260, 220)];
    self.menuView.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
    self.menuView.layer.cornerRadius = 15;
    self.menuView.layer.borderWidth = 1;
    self.menuView.layer.borderColor = [UIColor grayColor].CGColor;
    self.menuView.hidden = YES;
    self.window.menuView = self.menuView;
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, 260, 40)];
    title.text = @"🎯 MODERN STRIKE AIMBOT";
    title.textColor = [UIColor whiteColor];
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:16];
    [self.menuView addSubview:title];
    
    // Кнопка включения аимбота
    UIButton *aimbotBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    aimbotBtn.frame = CGRectMake(30, 60, 200, 50);
    [aimbotBtn setTitle:@"🎯 ВКЛЮЧИТЬ АИМБОТ" forState:UIControlStateNormal];
    aimbotBtn.backgroundColor = [UIColor systemGreenColor];
    [aimbotBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    aimbotBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    aimbotBtn.layer.cornerRadius = 8;
    [aimbotBtn addTarget:self action:@selector(enableAimbotAction) forControlEvents:UIControlEventTouchUpInside];
    [self.menuView addSubview:aimbotBtn];
    
    // Кнопка закрытия
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(30, 130, 200, 50);
    [closeBtn setTitle:@"❌ ЗАКРЫТЬ МЕНЮ" forState:UIControlStateNormal];
    closeBtn.backgroundColor = [UIColor systemRedColor];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    closeBtn.layer.cornerRadius = 8;
    [closeBtn addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    [self.menuView addSubview:closeBtn];
    
    [self.window addSubview:self.menuView];
}

- (void)toggleMenu {
    self.menuVisible = !self.menuVisible;
    self.menuView.hidden = !self.menuVisible;
}

- (void)enableAimbotAction {
    NSString *result = enableAimbot();
    showResultWindow(result);
}

@end

// ===== ТОЧКА ВХОДА =====
static AimbotUI *g_ui = nil;

__attribute__((constructor))
static void init() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        g_ui = [[AimbotUI alloc] init];
        NSLog(@"[Aimbot] Твик загружен!");
    });
}
