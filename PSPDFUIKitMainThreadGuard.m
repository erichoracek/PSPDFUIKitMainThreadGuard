#import <objc/runtime.h>
#import <objc/message.h>
#import <QuartzCore/QuartzCore.h>

// You should only use this in debug builds. It doesn't use private API, but I wouldn't ship it.
#ifdef DEBUG

static void PSPDFSwizzleMethod(Class c, SEL orig, SEL new) {
    Method origMethod = class_getInstanceMethod(c, orig);
    Method newMethod = class_getInstanceMethod(c, new);
    if (class_addMethod(c, orig, method_getImplementation(newMethod), method_getTypeEncoding(newMethod))) {
        class_replaceMethod(c, new, method_getImplementation(origMethod), method_getTypeEncoding(origMethod));
    }else {
        method_exchangeImplementations(origMethod, newMethod);
    }
}

void PSPDFReplaceMethod(Class c, SEL orig, SEL newSel, IMP impl) {
    Method method = class_getInstanceMethod(c, orig);
    if (!class_addMethod(c, newSel, impl, method_getTypeEncoding(method))) {
        PSPDFLogError(@"Failed to add method: %@ on %@", NSStringFromSelector(newSel), c);
    }else PSPDFSwizzleMethod(c, orig, newSel);
}

///////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Tracks down calls to UIKit from a Thread other than Main

static void PSPDFAssertIfNotMainThread(void) {
    PSPDFAssert([NSThread isMainThread], @"\nERROR: All calls to UIKit need to happen on the main thread. You have a bug in your code. Use dispatch_async(dispatch_get_main_queue(), ^{ ... }); if you're unsure what thread you're in.\n\nBreak on PSPDFAssertIfNotMainThread to find out where.\n\nStacktrace: %@", [NSThread callStackSymbols]);
}

// This installs a small guard that checks for the most common threading-errors in UIKit.
// This won't really slow down performance but still only is compiled in DEBUG versions of PSPDFKit.
// @note No private API is used here.
__attribute__((constructor)) static void PSPDFUIKitMainThreadGuard(void) {
    @autoreleasepool {
        for (NSString *selector in @[PROPERTY(setNeedsLayout), PROPERTY(setNeedsDisplay), PROPERTY(setNeedsDisplayInRect:)]) {
            SEL newSelector = NSSelectorFromString([NSString stringWithFormat:@"pspdf_%@", selector]);
            for (Class theClass in @[UIView.class, CALayer.class]) {
                if ([selector hasSuffix:@":"]) {
                    PSPDFReplaceMethod(theClass, NSSelectorFromString(selector), newSelector, imp_implementationWithBlock(^(UIView *_self, CGRect r) {
                        PSPDFAssertIfNotMainThread();
                        ((void ( *)(id, SEL, CGRect))objc_msgSend)(_self, newSelector, r);
                    }));
                }else {
                    PSPDFReplaceMethod(theClass, NSSelectorFromString(selector), newSelector, imp_implementationWithBlock(^(UIView *_self) {
                        PSPDFAssertIfNotMainThread();
                        ((void ( *)(id, SEL))objc_msgSend)(_self, newSelector);
                    }));
                }
            }
        }
    }
}
#endif