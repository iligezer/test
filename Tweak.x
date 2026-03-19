#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ===================== УПРОЩЁННАЯ КНОПКА =====================
@interface SimpleButton : UIButton
@end

@implementation SimpleButton

- (instancetype)init {
    // Координаты и размер как у тебя (x=20, y=100, ширина=50, высота=50)
    self = [super initWithFrame:CGRectMake(20, 100, 50, 50)];
    if (self) {
        self.backgroundColor = [UIColor systemBlueColor];
        self.layer.cornerRadius = 25;
        self.layer.masksToBounds = YES;
        // Используем стандартное действие addTarget (надёжнее чем жесты)
        [self addTarget:self action:@selector(buttonTapped) forControlEvents:UIControlEventTouchUpInside];
    }
    return self;
}

- (void)buttonTapped {
    NSLog(@"[Aimbot] Кнопка нажата!"); // ← появится в консоли

    // ---------- Если нужна запись в файл (раскомментируй) ----------
    /*
    NSString *logPath = @"/var/mobile/Media/aimbot_log.txt";
    NSString *logMessage = [NSString stringWithFormat:@"[%@] Кнопка нажата\n", [NSDate date]];
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:logPath];
    if (!fileHandle) {
        [[NSFileManager defaultManager] createFileAtPath:logPath contents:nil attributes:nil];
        fileHandle = [NSFileHandle fileHandleForWritingAtPath:logPath];
    }
    [fileHandle seekToEndOfFile];
    [fileHandle writeData:[logMessage dataUsingEncoding:NSUTF8StringEncoding]];
    [fileHandle closeFile];
    */

    // ---------- Показываем алерт ----------
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Aimbot"
                                                                   message:@"Кнопка работает!"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];

    // Ищем активный контроллер для показа
    UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    [rootVC presentViewController:alert animated:YES completion:nil];
}

@end

// ===================== ТОЧКА ВХОДА =====================
__attribute__((constructor))
static void init() {
    NSLog(@"[Aimbot] Твик загружается...");

    // Ждём, пока игра полностью запустится (3 секунды достаточно)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        UIWindow *mainWindow = [UIApplication sharedApplication].keyWindow;
        if (!mainWindow) {
            NSLog(@"[Aimbot] ОШИБКА: главное окно не найдено!");
            return;
        }

        SimpleButton *btn = [[SimpleButton alloc] init];
        [mainWindow addSubview:btn];
        NSLog(@"[Aimbot] Кнопка добавлена в окно: %@", mainWindow);
    });
}
