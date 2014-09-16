// Taken from the commercial iOS PDF framework http://pspdfkit.com.
// Copyright (c) 2013 Peter Steinberger. All rights reserved.
// Licensed under MIT (http://opensource.org/licenses/MIT)
//
// You should only use this in debug builds. It doesn't use private API, but I wouldn't ship it.

#import <objc/runtime.h>
#import <objc/message.h>

// Compile-time selector checks.
#if DEBUG
#define PROPERTY(propName) NSStringFromSelector(@selector(propName))
#else
#define PROPERTY(propName) @#propName
#endif

__attribute__((constructor)) static void PSPDFUIKitMainThreadGuard(void) {
    @autoreleasepool {
        for (NSString *selStr in @[PROPERTY(setNeedsLayout), PROPERTY(setNeedsDisplay), PROPERTY(setNeedsDisplayInRect:)]) {
            SEL selector = NSSelectorFromString(selStr);
            SEL newSelector = NSSelectorFromString([NSString stringWithFormat:@"pspdf_%@", selStr]);
            if ([selStr hasSuffix:@":"]) {
                PSPDFReplaceMethodWithBlock(UIView.class, selector, newSelector, ^(__unsafe_unretained UIView *_self, CGRect r) {
                    // Check for window, since *some* UIKit methods are indeed thread safe.
                    // https://developer.apple.com/library/ios/#releasenotes/General/WhatsNewIniPhoneOS/Articles/iPhoneOS4.html
                    /*
                     Drawing to a graphics context in UIKit is now thread-safe. Specifically:

                     The routines used to access and manipulate the graphics context can now correctly handle contexts residing on different threads.

                     String and image drawing is now thread-safe.

                     Using color and font objects in multiple threads is now safe to do.
                     */
                    if (_self.window) PSPDFAssertIfNotMainThread();
                    ((void ( *)(id, SEL, CGRect))objc_msgSend)(_self, newSelector, r);
                });
            }else {
                PSPDFReplaceMethodWithBlock(UIView.class, selector, newSelector, ^(__unsafe_unretained UIView *_self) {
                    if (_self.window) {
                        if (!NSThread.isMainThread) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                            dispatch_queue_t queue = dispatch_get_current_queue();
#pragma clang diagnostic pop
                            // iOS 8 layouts the MFMailComposeController in a background thread on an UIKit queue.
                            // https://github.com/PSPDFKit/PSPDFKit/issues/1423
                            if (!queue || !strstr(dispatch_queue_get_label(queue), "UIKit")) {
                                PSPDFAssertIfNotMainThread();
                            }
                        }
                    }
                    ((void ( *)(id, SEL))objc_msgSend)(_self, newSelector);
                });
            }
        }
    }
}
