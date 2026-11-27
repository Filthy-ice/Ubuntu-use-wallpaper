#include <X11/Xlib.h>
#include <X11/extensions/shape.h>
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv) {
    Display *d = XOpenDisplay(NULL);
    if (!d) { fprintf(stderr, "cannot open display\n"); return 1; }
    Window w = (Window)strtoul(argv[1], NULL, 0);
    int n = 0, o = 0;
    XShapeGetRectangles(d, w, ShapeInput, &n, &o);
    printf("input_rects=%d\n", n);
    return 0;
}
