/*
 * libheroapp.dylib, in every application while it is in the drop zone (bsd/dev/herolte_gl.c). Two things:
 *
 * An application killed by an Objective-C exception (Photos) leaves only "abort" in the log: the exception's name and
 * reason go there first.
 *
 * OpenGL ES exists in backboardd alone. Anywhere else EAGLContext is Darwin's, over a Metal that is not there, with no
 * functions behind it, and CoreImage on it jumps to address 0 (Settings and Messages, from MobileIcons). So no context
 * is given, as on a device that cannot make one.
 *
 * Note FE additions (gracerlte/heroapp, built by gracerlte/build-heroapp.sh):
 *  - iOS 16's CoreImage has no CPU renderer left: kCIContextUseSoftwareRenderer, or no Metal, sends initWithOptions: to
 *    +internalGLContextWithOptions:, which builds a CI::GLContext over the function table of an EAGLContext that does
 *    not exist and jumps to 0 (Messages, Settings: MobileIcons' _MI_sharedIconCompositorContext). That method now answers
 *    nil, so -initWithOptions: returns nil as on a device without a GPU, and callers take their no-context path.
 *  - Uncaught exceptions also log their first return addresses and the shared cache's slide, for gracerlte/symbolize.py.
 */
#include <dlfcn.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>

extern void herodrm_log(const char *format, ...);
extern void NSSetUncaughtExceptionHandler(void (*handler)(id));
extern const char *getprogname(void);

static const char *
text_of(id object)
{
   id string = object ? ((id (*)(id, SEL))objc_msgSend)(object, sel_registerName("description")) : nil;
   const char *text = string ? ((const char *(*)(id, SEL))objc_msgSend)(string, sel_registerName("UTF8String")) : NULL;
   return text ? text : "(none)";
}

extern const void *_dyld_get_shared_cache_range(unsigned long *length);

static void
uncaught(id exception)
{
   id name = ((id (*)(id, SEL))objc_msgSend)(exception, sel_registerName("name"));
   id reason = ((id (*)(id, SEL))objc_msgSend)(exception, sel_registerName("reason"));
   herodrm_log("%s: uncaught %s: %s", getprogname(), text_of(name), text_of(reason));
   /* Note FE: where it was thrown. Unslid = address - slide, for gracerlte/dsc-re.py fn / symbolize.py. */
   unsigned long length = 0;
   const char *cache = (const char *)_dyld_get_shared_cache_range(&length);
   unsigned long slide = cache ? (unsigned long)cache - 0x180000000ul : 0;
   id frames = ((id (*)(id, SEL))objc_msgSend)(exception, sel_registerName("callStackReturnAddresses"));
   unsigned long count = frames ? ((unsigned long (*)(id, SEL))objc_msgSend)(frames, sel_registerName("count")) : 0;
   char line[600];
   int used = 0;
   for (unsigned long i = 0; i < count && i < 24 && used < (int)sizeof(line) - 24; i++) {
      id number = ((id (*)(id, SEL, unsigned long))objc_msgSend)(frames, sel_registerName("objectAtIndex:"), i);
      unsigned long a = ((unsigned long (*)(id, SEL))objc_msgSend)(number, sel_registerName("unsignedLongValue"));
      used += snprintf(line + used, sizeof(line) - used, " %#lx", a - slide);
   }
   herodrm_log("%s: thrown at (unslid, slide %#lx):%s", getprogname(), slide, used ? line : " ?");
}

/* Note FE: no OpenGL ES CoreImage context outside backboardd (see the top of this file). */
static id
no_ci_gl_context(id self, SEL command, id options)
{
   (void)self;
   (void)command;
   (void)options;
   static int said;
   if (!said++) {
      herodrm_log("%s: CoreImage asked for an OpenGL ES context: none (no GPU here)", getprogname());
   }
   return nil;
}

static id
no_context(id self, SEL command, unsigned long api)
{
   (void)self;
   (void)command;
   (void)api;
   herodrm_log("%s: no EAGLContext given", getprogname());
   return nil;
}

static id
no_shared_context(id self, SEL command, unsigned long api, id sharegroup)
{
   (void)sharegroup;
   return no_context(self, command, api);
}

/*
 * CoreImage's default context is CI::GLContext whatever the system has: it fills a table of OpenGL ES's functions, empty
 * here, and calls glDisable(GL_DEPTH_TEST) through it. Every CIContext is asked for CoreImage's software renderer instead.
 */
static id (*ci_init_original)(id, SEL, id);
static id ci_software_key;

static id
ci_init(id self, SEL command, id options)
{
   id all = ((id (*)(id, SEL))objc_msgSend)((id)objc_getClass("NSMutableDictionary"), sel_registerName("dictionary"));
   if (options != nil) {
      ((void (*)(id, SEL, id))objc_msgSend)(all, sel_registerName("addEntriesFromDictionary:"), options);
   }
   id yes = ((id (*)(id, SEL, signed char))objc_msgSend)((id)objc_getClass("NSNumber"), sel_registerName("numberWithBool:"), 1);
   ((void (*)(id, SEL, id, id))objc_msgSend)(all, sel_registerName("setObject:forKey:"), yes, ci_software_key);
   return ci_init_original(self, command, all);
}

/*
 * Photos asserts that its data source has one section, and with no library it has none. Only that failure is let by, as a
 * test of what comes after it; every other goes on to the original, with its text already made.
 */
static void (*assert_original)(id, SEL, SEL, id, id, long, id, ...);

static void
assert_failed(id self, SEL command, SEL method, id object, id file, long line, id format, ...)
{
   va_list arguments;
   va_start(arguments, format);
   id text = ((id (*)(id, SEL, id, va_list))objc_msgSend)(
      ((id (*)(id, SEL))objc_msgSend)((id)objc_getClass("NSString"), sel_registerName("alloc")),
      sel_registerName("initWithFormat:arguments:"), format, arguments);
   va_end(arguments);
   if (strstr(text_of(text), "numberOfSections == 1") != NULL) {
      herodrm_log("%s: assertion let by: %s", getprogname(), text_of(text));
      return;
   }
   id percent = ((id (*)(id, SEL, const char *))objc_msgSend)((id)objc_getClass("NSString"),
      sel_registerName("stringWithUTF8String:"), "%@");
   assert_original(self, command, method, object, file, line, percent, text);
}

/*
 * PosterBoard's previews of the home screen use CARenderer with a Metal queue, and there is none: drawn into a bitmap
 * instead (as FiiO JM21's libhakios.poster, MIT, by the same way).
 */
typedef struct { double x, y, w, h; } hero_rect;
typedef struct { double w, h; } hero_size;
extern void UIGraphicsBeginImageContextWithOptions(hero_size size, bool opaque, double scale);
extern void *UIGraphicsGetCurrentContext(void);
extern id UIGraphicsGetImageFromCurrentImageContext(void);
extern void UIGraphicsEndImageContext(void);
extern void CGContextTranslateCTM(void *context, double x, double y);

static id
preview_for_view(id self, SEL command, id view)
{
   (void)self;
   (void)command;
   if (view == nil)
      return nil;
   hero_rect bounds = ((hero_rect (*)(id, SEL))objc_msgSend)(view, sel_registerName("bounds"));
   if (bounds.w <= 0 || bounds.h <= 0)
      return nil;
   UIGraphicsBeginImageContextWithOptions((hero_size){ bounds.w, bounds.h }, false, 2.0);
   void *context = UIGraphicsGetCurrentContext();
   if (context != NULL) {
      CGContextTranslateCTM(context, -bounds.x, -bounds.y);
      id layer = ((id (*)(id, SEL))objc_msgSend)(view, sel_registerName("layer"));
      ((void (*)(id, SEL, void *))objc_msgSend)(layer, sel_registerName("renderInContext:"), context);
   }
   id image = UIGraphicsGetImageFromCurrentImageContext();
   UIGraphicsEndImageContext();
   return image;
}

__attribute__((constructor)) static void
install(void)
{
   if (strcmp(getprogname(), "PosterBoard") == 0) {
      dlopen("/System/Library/PrivateFrameworks/PosterBoard.framework/PosterBoard", RTLD_LAZY);
      Method preview = class_getInstanceMethod(objc_getClass("PBFHomeScreenPreviewImageBuilder"), sel_registerName("_imageForView:"));
      if (preview != NULL) {
         method_setImplementation(preview, (IMP)preview_for_view);
      }
      herodrm_log("PosterBoard: home preview in a bitmap: %d", preview != NULL);
   }
   /* Note FE 0458: the front camera's capture device (gracerlte/camera, libnotefecam.dylib) in mediaserverd only */
   /* only with the drop zone's cam.media = 1 (write-drop.sh CAMMEDIA=1; 0 by default, so the everyday setup is as before) */
   char flag = '0';
   int ff = open("/private/var/herolte/cam.media", O_RDONLY);
   if (ff >= 0) {
      read(ff, &flag, 1);
      close(ff);
   }
   if (flag == '1' && strcmp(getprogname(), "mediaserverd") == 0 && access("/private/var/herolte/lib/libnotefecam.dylib", F_OK) == 0) {
      void *cam = dlopen("/private/var/herolte/lib/libnotefecam.dylib", RTLD_NOW);
      herodrm_log("mediaserverd: libnotefecam %s", cam ? "loaded" : dlerror());
   }
   NSSetUncaughtExceptionHandler(uncaught);
   dlopen("/System/Library/Frameworks/OpenGLES.framework/OpenGLES", RTLD_LAZY);
   Class context = objc_getClass("EAGLContext");
   if (context != Nil) {
      method_setImplementation(class_getInstanceMethod(context, sel_registerName("initWithAPI:")), (IMP)no_context);
      method_setImplementation(class_getInstanceMethod(context, sel_registerName("initWithAPI:sharegroup:")),
                               (IMP)no_shared_context);
   }
   Method properties = context != Nil ? class_getInstanceMethod(context, sel_registerName("initWithAPI:properties:")) : NULL;
   if (properties != NULL) {
      method_setImplementation(properties, (IMP)no_shared_context);
   }
   void *core_image = dlopen("/System/Library/Frameworks/CoreImage.framework/CoreImage", RTLD_LAZY);
   id *key = core_image ? dlsym(core_image, "kCIContextUseSoftwareRenderer") : NULL;
   Method init = class_getInstanceMethod(objc_getClass("CIContext"), sel_registerName("initWithOptions:"));
   if (key != NULL && init != NULL) {
      ci_software_key = *key;
      ci_init_original = (id (*)(id, SEL, id))method_setImplementation(init, (IMP)ci_init);
   }
   Method ci_gl = core_image ? class_getClassMethod(objc_getClass("CIContext"), sel_registerName("internalGLContextWithOptions:")) : NULL;
   if (ci_gl != NULL) {
      method_setImplementation(ci_gl, (IMP)no_ci_gl_context);
   }
   herodrm_log("%s: libheroapp (Note FE): CoreImage %s, GL context %s", getprogname(),
               ci_init_original ? "in software" : "as it was", ci_gl ? "refused" : "as it was");
   Method assertion = class_getInstanceMethod(objc_getClass("NSAssertionHandler"),
      sel_registerName("handleFailureInMethod:object:file:lineNumber:description:"));
   if (assertion != NULL) {
      assert_original = (void (*)(id, SEL, SEL, id, id, long, id, ...))method_setImplementation(assertion, (IMP)assert_failed);
   }
}
