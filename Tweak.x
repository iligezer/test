#import <UIKit/UIKit.h>

%hook UIViewController
- (void)viewDidLoad {
    %orig;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Aimbot" message:@"Loaded!" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
%end
