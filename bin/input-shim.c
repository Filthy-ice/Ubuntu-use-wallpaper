// LD_PRELOAD: make every wl_surface of this process input-transparent.
// The wallpaper renderer window must never intercept clicks.
#include <stdio.h>
#include <execinfo.h>
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <wayland-client-core.h>
#include <wayland-client.h>
#include <wayland-client-protocol.h>
#include <wayland-util.h>

struct wl_interface;
struct wl_object_mirror { const struct wl_interface *interface; uint32_t id; };
struct wl_proxy_mirror { struct wl_object_mirror object; };

typedef struct wl_proxy *(*marshal_array_fn)(struct wl_proxy *, uint32_t,
                                             const struct wl_interface *,
                                             uint32_t, uint32_t,
                                             union wl_argument *);
static marshal_array_fn real_array;
static marshal_array_fn real(void) {
    if (!real_array)
        real_array = (marshal_array_fn)dlsym(RTLD_NEXT, "wl_proxy_marshal_array_flags");
    return real_array;
}

struct wl_proxy *wl_proxy_marshal_flags(struct wl_proxy *proxy, uint32_t opcode,
                                        const struct wl_interface *interface,
                                        uint32_t version, uint32_t flags, ...) {
    marshal_array_fn fn = real();
    if (!fn) return NULL;

    static int first_surface = 1;  /* only the toplevel: CEF creates later surfaces */
    if (first_surface && interface == &wl_compositor_interface && opcode == WL_COMPOSITOR_CREATE_SURFACE) {
        first_surface = 0;
        union wl_argument new_id[1] = {{.n = (int32_t)version}};
        struct wl_proxy *surface = fn(proxy, opcode, interface, version, flags, new_id);
        if (!surface) return NULL;
        union wl_argument region_new[1] = {{.n = (int32_t)version}};
        struct wl_proxy *region = fn(proxy, WL_COMPOSITOR_CREATE_REGION,
                                     &wl_region_interface, version, 0, region_new);
        union wl_argument region_arg[1] = {{.o = (struct wl_object *)region}};
        fn(surface, WL_SURFACE_SET_INPUT_REGION, NULL, version, 0, region_arg);
        return surface;
    }

    const struct wl_interface *piface =
        ((const struct wl_proxy_mirror *)proxy)->object.interface;
    const char *sig = "";
    if (piface && opcode < (uint32_t)piface->method_count)
        sig = piface->methods[opcode].signature;

    if (getenv("SHIMDBG")) {
        fprintf(stderr, "[shim] call %s.%u\n", piface?piface->name:"?", opcode);
    }
    if (0 && strcmp(sig, "usun") == 0) {
        fprintf(stderr, "[shim] %s.%u sig=usun iface-class=%s\n", piface?piface->name:"?", opcode, wl_proxy_get_class(proxy));
    }
    union wl_argument args[16];
    memset(args, 0, sizeof(args));
    va_list ap;
    va_start(ap, flags);
    int count = 0;
    for (const char *c = sig; *c && count < 16; c++, count++) {
        switch (*c) {
        case 'i': args[count].i = va_arg(ap, int32_t); break;
        case 'u': args[count].u = va_arg(ap, uint32_t); break;
        case 'f': args[count].f = va_arg(ap, int32_t); break;
        case 'h': args[count].h = va_arg(ap, int32_t); break;
        case 's': args[count].s = va_arg(ap, const char *); break;
        case 'o': args[count].o = va_arg(ap, void *); break;
        case 'n': args[count].n = va_arg(ap, int32_t); break;
        case 'a': args[count].a = va_arg(ap, struct wl_array *); break;
        default: break;
        }
    }
    va_end(ap);
    if (getenv("SHIMDBG") && strcmp(sig, "usun") == 0) {
        fprintf(stderr, "[shim]   name=%u iname=%s ver=%u\n", args[0].u, args[1].s ? args[1].s : "(null)", args[2].u);
    }
    if (getenv("SHIMDBG") && strcmp(sig, "usun") == 0 && !args[1].s) {
        void *bt[8]; int n = backtrace(bt, 8);
        fprintf(stderr, "[shim] NULL iface-name bind, backtrace:\n");
        backtrace_symbols_fd(bt, n, 2);
    }
    return fn(proxy, opcode, interface, version, flags, args);
}
