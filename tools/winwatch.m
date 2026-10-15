// The window-list watcher (task 091, a diagnostic, macOS): polls the window list every 2 s for N seconds and prints
// where PureNative's window is, whether it is on screen, and which normal windows are in front of it and how much of it
// they cover. A window run whose window is covered presents without vsync and measures nothing
// (tools/display_rate_check.sh --audio's guard says so from the log; this says why). It only reads the window list:
// it never moves, raises or hides a window.
//   /usr/bin/clang -fobjc-arc -O -o out/winwatch tools/winwatch.m -framework CoreGraphics -framework Foundation
//   out/winwatch 200 > out/winwatch.txt &   # beside a window run, then wait for it
// Task 091's run: `window 89586 onscreen=1 bounds=276,188 960x572 in front: Google Chrome 100%` from 2 s to the end.
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static CGRect bounds_of(NSDictionary *d) {
    CGRect r = CGRectZero;
    NSDictionary *b = d[(id)kCGWindowBounds];
    if (b) CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)b, &r);
    return r;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        const double seconds = argc > 1 ? atof(argv[1]) : 150.0;
        NSDate *start = [NSDate date];
        while (-[start timeIntervalSinceNow] < seconds) {
            const int t = (int)(-[start timeIntervalSinceNow]);
            NSArray *all = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionAll, kCGNullWindowID));
            NSArray *on = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID));
            int found = 0;
            for (NSDictionary *w in all) {
                if (![w[(id)kCGWindowOwnerName] isEqual:@"PureNative"] || [w[(id)kCGWindowLayer] intValue] != 0) continue;
                found = 1;
                const int wid = [w[(id)kCGWindowNumber] intValue];
                const CGRect r = bounds_of(w);
                NSMutableArray *front = [NSMutableArray array];
                for (NSDictionary *o in on) {
                    if ([o[(id)kCGWindowNumber] intValue] == wid) break;
                    if ([o[(id)kCGWindowLayer] intValue] != 0) continue;
                    const CGRect orr = bounds_of(o);
                    if (!CGRectIntersectsRect(orr, r)) continue;
                    const CGRect in = CGRectIntersection(orr, r);
                    const int pct = (int)(100.0 * in.size.width * in.size.height / (r.size.width * r.size.height));
                    [front addObject:[NSString stringWithFormat:@"%@ %d%%", o[(id)kCGWindowOwnerName], pct]];
                }
                printf("t=%d window %d onscreen=%d bounds=%d,%d %dx%d in front: %s\n", t, wid,
                       [w[(id)kCGWindowIsOnscreen] boolValue], (int)r.origin.x, (int)r.origin.y, (int)r.size.width,
                       (int)r.size.height, front.count ? [[front componentsJoinedByString:@", "] UTF8String] : "none");
            }
            if (!found) printf("t=%d no PureNative window\n", t);
            fflush(stdout);
            sleep(2);
        }
    }
    return 0;
}
