#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>

// ========== ТВОИ АДРЕСА ==========
#define BASE_ADDR 0x1042c4000
#define RVA_Camera_main 0x10871faf8
#define RVA_WorldToScreen 0x10871ed5c
#define RVA_GetPosition 0x108792ed0

// ========== ТИПЫ ФУНКЦИЙ ==========
typedef void *(*t_get_main_camera)();
typedef void *(*t_world_to_screen)(void *camera, void *worldPos);
typedef void *(*t_get_position)(void *transform);

static t_get_main_camera Camera_main = NULL;
static t_world_to_screen WorldToScreen = NULL;
static t_get_position GetPosition = NULL;

static NSMutableString *logText = nil;
static UIWindow *logWindow = nil;
static BOOL espEnabled = NO;

// ========== ПОИСК В ПАМЯТИ ==========
typedef struct {
    uint64_t address;
    float health;
    float position[3];
    int team;
    bool isAlive;
} PlayerData;

void scanMemoryForPlayers() {
    [logText setString:@""];
    [self addLog:@"🔍 СКАНИРОВАНИЕ ПАМЯТИ..."];
    
    // Получаем информацию о памяти процесса
    mach_port_t task = mach_task_self();
    vm_address_t address = 0;
    vm_size_t size = 0;
    vm_region_flavor_t flavor = VM_REGION_BASIC_INFO;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT;
    struct vm_region_basic_info info;
    
    int playerCount = 0;
    
    while (vm_region(task, &address, &size, flavor, (vm_region_info_t)&info, &count, &info) == KERN_SUCCESS) {
        // Ищем регионы с данными (rw-)
        if (info.protection & VM_PROT_READ && info.protection & VM_PROT_WRITE) {
            // Читаем память в поисках паттернов
            uint8_t *buffer = malloc(size);
            vm_size_t data_read;
            
            if (vm_read_overwrite(task, address, size, (vm_address_t)buffer, &data_read) == KERN_SUCCESS) {
                // Ищем значения здоровья (обычно float от 0 до 100)
                for (int i = 0; i < data_read - 8; i += 4) {
                    float *f = (float*)&buffer[i];
                    if (*f >= 0 && *f <= 100 && *f == (int)*f) { // Похоже на здоровье
                        // Проверяем, что рядом есть координаты
                        float *x = (float*)&buffer[i - 12];
                        float *y = (float*)&buffer[i - 8];
                        float *z = (float*)&buffer[i - 4];
                        
                        if (x && y && z && 
                            *x >= -10000 && *x <= 10000 &&
                            *y >= -10000 && *y <= 10000 &&
                            *z >= -10000 && *z <= 10000) {
                            
                            [self addLog:[NSString stringWithFormat:@"Найден игрок: адрес 0x%llx, здоровье %.1f, позиция (%.1f, %.1f, %.1f)", 
                                         address + i, *f, *x, *y, *z]];
                            playerCount++;
                        }
                    }
                }
            }
            free(buffer);
        }
        address += size;
    }
    
    [self addLog:[NSString stringWithFormat:@"Найдено игроков: %d", playerCount]];
    [self showLogWindow];
}

// ========== ЛОГИРОВАНИЕ ==========
void addLog(NSString *text) {
    if (!logText) logText = [[NSMutableString alloc] init];
    [logText appendFormat:@"%@\n", text];
    NSLog(@"%@", text);
}

void showLogWindow() {
    if (logWindow) {
        logWindow.hidden = NO;
        return;
    }
    
    logWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    logWindow.windowLevel = UIWindowLevelAlert + 2;
    logWindow.backgroundColor = [UIColor colorWithWhite:0 alpha:0.9];
    
    UITextView *textView = [[UITextView alloc] initWithFrame:CGRectMake(20, 60, logWindow.bounds.size.width-40, logWindow.bounds.size.height-150)];
    textView.backgroundColor = [UIColor blackColor];
    textView.textColor = [UIColor greenColor];
    textView.font = [UIFont fontWithName:@"Courier" size:12];
    textView.text = logText;
    textView.editable = NO;
    [logWindow addSubview:textView];
    
    UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    copyBtn.frame = CGRectMake(20, logWindow.bounds.size.height-80, 100, 40);
    copyBtn.backgroundColor = [UIColor systemBlueColor];
    copyBtn.layer.cornerRadius = 10;
    [copyBtn setTitle:@"📋 Копировать" forState:UIControlStateNormal];
    [copyBtn addTarget:[ButtonHandler class] action:@selector(copyLog) forControlEvents:UIControlEventTouchUpInside];
    [logWindow addSubview:copyBtn];
    
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(logWindow.bounds.size.width-120, logWindow.bounds.size.height-80, 100, 40);
    closeBtn.backgroundColor = [UIColor systemRedColor];
    closeBtn.layer.cornerRadius = 10;
    [closeBtn setTitle:@"❌ Закрыть" forState:UIControlStateNormal];
    [closeBtn addTarget:[ButtonHandler class] action:@selector(closeLogWindow) forControlEvents:UIControlEventTouchUpInside];
    [logWindow addSubview:closeBtn];
    
    [logWindow makeKeyAndVisible];
}

// ========== КЛАСС-ОБРАБОТЧИК ==========
@interface ButtonHandler : NSObject
+ (void)showMenu;
+ (void)copyLog;
+ (void)closeLogWindow;
+ (void)scanMemory;
+ (UIViewController*)topViewController;
+ (UIWindow*)mainWindow;
@end

@implementation ButtonHandler

+ (void)showMenu {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Memory Scanner"
                                                                   message:@""
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"🔍 Сканировать память"
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *a){
        scanMemoryForPlayers();
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"ESP %@", espEnabled ? @"✅" : @"❌"]
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *a){
        espEnabled = !espEnabled;
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"📋 Показать лог"
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *a){
        showLogWindow();
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Отмена"
                                               style:UIAlertActionStyleCancel
                                             handler:nil]];
    
    [[self topViewController] presentViewController:alert animated:YES completion:nil];
}

+ (void)copyLog {
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    pasteboard.string = logText;
}

+ (void)closeLogWindow {
    logWindow.hidden = YES;
}

+ (UIViewController*)topViewController {
    UIWindow *window = [self mainWindow];
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

+ (UIWindow*)mainWindow {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            for (UIWindow *window in ((UIWindowScene*)scene).windows) {
                if (window.isKeyWindow) return window;
            }
        }
    }
    return nil;
}

@end

// ========== ESP VIEW ==========
@interface ESPView : UIView
@end

@implementation ESPView
- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    if (!espEnabled) return;
    
    // Пока просто точка
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(ctx, [UIColor redColor].CGColor);
    CGContextFillEllipseInRect(ctx, CGRectMake(100, 100, 10, 10));
}
@end

// ========== ИНИЦИАЛИЗАЦИЯ ==========
__attribute__((constructor))
static void init() {
    @autoreleasepool {
        logText = [[NSMutableString alloc] init];
        
        Camera_main = (t_get_main_camera)(BASE_ADDR + (RVA_Camera_main - 0x1042c4000));
        WorldToScreen = (t_world_to_screen)(BASE_ADDR + (RVA_WorldToScreen - 0x1042c4000));
        GetPosition = (t_get_position)(BASE_ADDR + (RVA_GetPosition - 0x1042c4000));
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            UIWindow *mainWindow = [ButtonHandler mainWindow];
            if (!mainWindow) return;
            
            UIButton *menuBtn = [UIButton buttonWithType:UIButtonTypeSystem];
            menuBtn.frame = CGRectMake(20, 150, 60, 60);
            menuBtn.backgroundColor = [UIColor systemBlueColor];
            menuBtn.layer.cornerRadius = 30;
            [menuBtn setTitle:@"M" forState:UIControlStateNormal];
            [menuBtn addTarget:[ButtonHandler class] action:@selector(showMenu) forControlEvents:UIControlEventTouchUpInside];
            [mainWindow addSubview:menuBtn];
            
            overlayWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
            overlayWindow.windowLevel = UIWindowLevelAlert + 1;
            overlayWindow.backgroundColor = [UIColor clearColor];
            overlayWindow.userInteractionEnabled = NO;
            
            ESPView *espView = [[ESPView alloc] initWithFrame:[UIScreen mainScreen].bounds];
            [overlayWindow addSubview:espView];
            [overlayWindow makeKeyAndVisible];
        });
    }
}
