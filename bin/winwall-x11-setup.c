#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/extensions/shape.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>

static int match(Display *d, Window w, long pid, int depth) {
    Atom pidAtom = XInternAtom(d, "_NET_WM_PID", True);
    Atom type; int fmt; unsigned long n, after; unsigned char *data = NULL;
    int found = 0;
    if (pidAtom != None && XGetWindowProperty(d, w, pidAtom, 0, 1, False, XA_CARDINAL,
            &type, &fmt, &n, &after, &data) == Success && data && n == 1) {
        found = (long)(*(unsigned long *)data) == pid;
        XFree(data);
    }
    if (!found) {
        char *name = NULL;
        if (XFetchName(d, w, &name) && name) {
            if (strstr(name, "wallpaperengine") || strstr(name, "Wallpaperengine") ||
                strstr(name, "Winwall Desktop")) found = 1;
            XFree(name);
        }
    }
    if (found) return 1;
    if (depth <= 0) return 0;
    Window root, parent, *children = NULL; unsigned int count = 0;
    if (XQueryTree(d, w, &root, &parent, &children, &count)) {
        for (unsigned int i = 0; i < count; i++)
            if (match(d, children[i], pid, depth - 1)) { found = 1; break; }
        if (children) XFree(children);
    }
    return found;
}

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: %s <pid> [timeout_ms]\n", argv[0]); return 2; }
    long pid = strtol(argv[1], NULL, 10);
    int timeout = argc > 2 ? atoi(argv[2]) : 8000;
    Display *d = XOpenDisplay(NULL);
    if (!d) { fprintf(stderr, "cannot open display\n"); return 1; }
    Atom typeAtom = XInternAtom(d, "_NET_WM_WINDOW_TYPE", False);
    Atom desktopAtom = XInternAtom(d, "_NET_WM_WINDOW_TYPE_DESKTOP", False);
    Window root = DefaultRootWindow(d);
    Window target = None;
    struct timespec start, now;
    timespec_get(&start, TIME_UTC);
    while (1) {
        Window r, p, *kids = NULL; unsigned int n = 0;
        if (XQueryTree(d, root, &r, &p, &kids, &n)) {
            for (unsigned int i = 0; i < n; i++) {
                if (match(d, kids[i], pid, 2)) { target = kids[i]; break; }
            }
            if (kids) XFree(kids);
        }
        if (target != None) break;
        timespec_get(&now, TIME_UTC);
        long elapsed = (now.tv_sec - start.tv_sec) * 1000 + (now.tv_nsec - start.tv_nsec) / 1000000;
        if (elapsed > timeout) { fprintf(stderr, "window for pid %ld not found\n", pid); XCloseDisplay(d); return 3; }
        usleep(100000);
    }
    XChangeProperty(d, target, typeAtom, XA_ATOM, 32, PropModeReplace,
                    (unsigned char *)&desktopAtom, 1);
    XShapeCombineRectangles(d, target, ShapeInput, 0, 0, NULL, 0, ShapeSet, Unsorted);
    XSync(d, False);
    printf("configured 0x%lx\n", target);
    XCloseDisplay(d);
    return 0;
}
