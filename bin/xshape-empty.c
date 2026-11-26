#include <X11/Xlib.h>
#include <X11/extensions/shape.h>
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: %s <xid>\n", argv[0]); return 2; }
    Display *d = XOpenDisplay(NULL);
    if (!d) { fprintf(stderr, "cannot open display\n"); return 1; }
    Window w = (Window)strtoul(argv[1], NULL, 0);
    XShapeCombineRectangles(d, w, ShapeInput, 0, 0, NULL, 0, ShapeSet, Unsorted);
    XSync(d, False);
    XCloseDisplay(d);
    return 0;
}
