#import <Foundation/Foundation.h>

// The settings-only diagnostic profile excludes uYouPlus.xm, which normally
// provides this bundle accessor.
NSBundle *uYouPlusBundle(void) {
    static NSBundle *bundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *path = [[NSBundle mainBundle] pathForResource:@"uYouPlus"
                                                         ofType:@"bundle"];
        bundle = path ? [NSBundle bundleWithPath:path] : [NSBundle mainBundle];
    });
    return bundle;
}
