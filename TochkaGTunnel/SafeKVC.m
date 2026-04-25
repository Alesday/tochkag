#import <Foundation/Foundation.h>

id _Nullable safeValueForKeyPath(id _Nonnull obj, NSString * _Nonnull keyPath) {
    @try {
        return [obj valueForKeyPath:keyPath];
    } @catch (NSException *e) {
        return nil;
    }
}
