/*
 * notefe bot: the drop zone's "test" program (hero-run starts it ~20 s after the UI settles). It re-spawns itself
 * detached ("--run") so hero-run's 180 s limit does not apply, then drives the phone through the kernel's
 * kern.notefe_hid (patch 0409, boot-arg herobot=1): Home presses, home-screen page swipes, and for each app: launch it
 * (SpringBoardServices, else LSApplicationWorkspace), scroll down and up, back Home. Every step goes to the kernel log
 * as "NOTEFE BOT t=SECONDS ...", so the log's frame times (hakios-gl), CPU (TOP 5s) and crashes line up with what was
 * on screen. Plan in /private/var/herolte/bot.plan (one bundle id per line) if present, else the default list.
 */
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <signal.h>
#include <sys/sysctl.h>
#include <objc/message.h>
#include <spawn.h>
#include <sys/sysctl.h>
#include <time.h>
#include <unistd.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <errno.h>
#include <stdarg.h>
#include <CommonCrypto/CommonDigest.h>

extern void herodrm_log(const char *fmt, ...);
extern char **environ;
static struct timespec t0;

static double now(void)
{
   struct timespec t;
   clock_gettime(CLOCK_MONOTONIC, &t);
   return (t.tv_sec - t0.tv_sec) + (t.tv_nsec - t0.tv_nsec) / 1e9;
}

#define LOG(fmt, ...) herodrm_log("NOTEFE BOT t=%.1f " fmt, now(), ##__VA_ARGS__)

static int hid(const char *cmd)
{
   return sysctlbyname("kern.notefe_hid", NULL, NULL, (void *)cmd, strlen(cmd));
}

static void key(int k)
{
   char c[32];
   snprintf(c, sizeof c, "k %d 1", k); hid(c);
   usleep(80000);
   snprintf(c, sizeof c, "k %d 0", k); hid(c);
}

static void home(void) { key(3); }

/* A finger from (x0,y0) to (x1,y1) in ms milliseconds, a move every 16 ms, as the panel's own reports. */
static void swipe(int x0, int y0, int x1, int y1, int ms)
{
   char c[48];
   int steps = ms / 16 > 2 ? ms / 16 : 2;
   snprintf(c, sizeof c, "t 0 1 %d %d", x0, y0); hid(c);
   for (int i = 1; i <= steps; i++) {
      usleep(16000);
      snprintf(c, sizeof c, "t 0 1 %d %d", x0 + (x1 - x0) * i / steps, y0 + (y1 - y0) * i / steps); hid(c);
   }
   usleep(16000);
   snprintf(c, sizeof c, "t 0 0 %d %d", x1, y1); hid(c);
}

/* FrontBoard with "unlock device": SBSLaunchApplicationWithIdentifier was refused with code 7 (Locked) in boot 6. */
static int launch_fbs(NSString *bundle)
{
   static void *fbs;
   if (!fbs)
      fbs = dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_LAZY);
   Class svc = NSClassFromString(@"FBSSystemService");
   NSString *__strong *unlock = (NSString *__strong *)dlsym(fbs, "FBSOpenApplicationOptionKeyUnlockDevice");
   if (!svc || !unlock)
      return -2;
   id shared = ((id (*)(id, SEL))objc_msgSend)(svc, @selector(sharedService));
   NSDictionary *options = @{ *unlock : @YES };
   __block long code = -3;
   dispatch_semaphore_t done = dispatch_semaphore_create(0);
   ((void (*)(id, SEL, id, id, id))objc_msgSend)(shared, @selector(openApplication:options:withResult:), bundle, options,
      ^(NSError *error) {
         code = error ? (long)error.code : 0;
         if (error)
            LOG("FrontBoard %s: %s", bundle.UTF8String, error.description.UTF8String);
         dispatch_semaphore_signal(done);
      });
   dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
   return (int)code;
}

static int launch(NSString *bundle)
{
   if (launch_fbs(bundle) == 0)
      return 0;
   static int (*sbs)(CFStringRef, Boolean);
   static int tried;
   if (!tried) {
      tried = 1;
      void *h = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_LAZY);
      sbs = h ? (int (*)(CFStringRef, Boolean))dlsym(h, "SBSLaunchApplicationWithIdentifier") : NULL;
   }
   if (sbs) {
      int r = sbs((__bridge CFStringRef)bundle, false);
      if (r == 0)
         return 0;
      LOG("SBSLaunchApplicationWithIdentifier %s -> %d, trying LSApplicationWorkspace", bundle.UTF8String, r);
   }
   Class ws = NSClassFromString(@"LSApplicationWorkspace");
   id w = [ws performSelector:@selector(defaultWorkspace)];
   BOOL ok = [w respondsToSelector:@selector(openApplicationWithBundleID:)] &&
             ((BOOL (*)(id, SEL, id))objc_msgSend)(w, @selector(openApplicationWithBundleID:), bundle);
   return ok ? 0 : -1;
}

/*
 * Location Services' master switch: locationd (user mobile) reads LocationServicesEnabledIn8.0 from com.apple.locationd;
 * Setup.app turns it on, and this port skips Setup ("location disabled system-wide", boot 6). Set it, restart locationd.
 */
static void enable_location(void)
{
   CFStringRef key = CFSTR("LocationServicesEnabledIn8.0"), domain = CFSTR("com.apple.locationd");
   CFPropertyListRef was = CFPreferencesCopyValue(key, domain, CFSTR("mobile"), kCFPreferencesAnyHost);
   if (was && CFEqual(was, kCFBooleanTrue)) {
      LOG("location services: already on");
      CFRelease(was);
      return;
   }
   if (was)
      CFRelease(was);
   CFPreferencesSetValue(key, kCFBooleanTrue, domain, CFSTR("mobile"), kCFPreferencesAnyHost);
   Boolean ok = CFPreferencesSynchronize(domain, CFSTR("mobile"), kCFPreferencesAnyHost);
   int mib[3] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL };
   size_t size = 0;
   sysctl(mib, 3, NULL, &size, NULL, 0);
   struct kinfo_proc *procs = malloc(size);
   int killed = 0;
   if (procs && sysctl(mib, 3, procs, &size, NULL, 0) == 0) {
      for (size_t i = 0; i < size / sizeof(*procs); i++)
         if (strcmp(procs[i].kp_proc.p_comm, "locationd") == 0)
            killed += kill(procs[i].kp_proc.p_pid, SIGTERM) == 0;
   }
   free(procs);
   LOG("location services: switched on (synchronize %d), locationd restarted %d", ok, killed);
}

static int kill_named(const char *name)
{
   int mib[3] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL }, killed = 0;
   size_t size = 0;
   sysctl(mib, 3, NULL, &size, NULL, 0);
   struct kinfo_proc *procs = malloc(size);
   if (procs && sysctl(mib, 3, procs, &size, NULL, 0) == 0)
      for (size_t i = 0; i < size / sizeof(*procs); i++)
         if (strcmp(procs[i].kp_proc.p_comm, name) == 0)
            killed += kill(procs[i].kp_proc.p_pid, SIGTERM) == 0;
   free(procs);
   return killed;
}

/*
 * Note FE 0435: BlueTool picks its boot script by MGCopyAnswer("WifiVendor"), which MobileGestalt reads from an
 * AppleOLYHAL service we do not have ("Manufacturer is -1", "No WiFi", exit). A cached answer in CacheExtra stops that
 * (guacamole's mgtool setstr); the key is base64(MD5("MGCopyAnswer" + name)) cut to 22 characters. Our module is Murata.
 */
#define MG_CACHE @"/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist"
static NSString *mg_key(const char *name)
{
   char in[128];
   unsigned char md[CC_MD5_DIGEST_LENGTH];
   snprintf(in, sizeof in, "MGCopyAnswer%s", name);
   CC_MD5(in, (CC_LONG)strlen(in), md);
   NSString *b = [[NSData dataWithBytes:md length:sizeof md] base64EncodedStringWithOptions:0];
   return [b substringToIndex:22];
}

static void mg_set_value(const char *name, id value);
static void mg_set_string(const char *name, NSString *value)
{
   mg_set_value(name, value);
}

static void mg_set_value(const char *name, id value)
{
   NSMutableDictionary *cache = [NSMutableDictionary dictionaryWithContentsOfFile:MG_CACHE];
   if (!cache) {
      LOG("mobilegestalt: no cache file, %s not set", name);
      return;
   }
   NSMutableDictionary *extra = [cache[@"CacheExtra"] mutableCopy] ?: [NSMutableDictionary dictionary];
   NSString *k = mg_key(name);
   id old = extra[k];
   if ([old isEqual:value]) {
      LOG("mobilegestalt: %s already %s", name, [value description].UTF8String);
      return;
   }
   extra[k] = value;
   cache[@"CacheExtra"] = extra;
   struct stat st;
   int have = stat(MG_CACHE.fileSystemRepresentation, &st) == 0;
   BOOL ok = [cache writeToFile:MG_CACHE atomically:YES];
   if (have)
      chown(MG_CACHE.fileSystemRepresentation, st.st_uid, st.st_gid), chmod(MG_CACHE.fileSystemRepresentation, st.st_mode & 07777);
   LOG("mobilegestalt: %s = %s (key %s, was %s): %s", name, [value description].UTF8String, k.UTF8String,
       old ? [old description].UTF8String : "unset", ok ? "written" : "NOT written");
}

static int kill_named_sig(const char *name, int sig)
{
   int mib[3] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL }, killed = 0;
   size_t size = 0;
   sysctl(mib, 3, NULL, &size, NULL, 0);
   struct kinfo_proc *procs = malloc(size);
   if (procs && sysctl(mib, 3, procs, &size, NULL, 0) == 0)
      for (size_t i = 0; i < size / sizeof(*procs); i++)
         if (strcmp(procs[i].kp_proc.p_comm, name) == 0)
            killed += kill(procs[i].kp_proc.p_pid, sig) == 0;
   free(procs);
   return killed;
}

/*
 * duetexpertd logged "After unrecognized frame in .../streams/predictionContext/local/N, skipping ahead" 981,345 times
 * in boot 7 (logd at 70-110 % CPU): a damaged Biome stream file. It is a prediction cache; it is removed once and
 * duetexpertd restarted (it makes a new one).
 */
static void clean_biome(void)
{
   NSString *dir = @"/private/var/mobile/Library/DuetExpertCenter/streams/predictionContext/local";
   NSFileManager *fm = NSFileManager.defaultManager;
   NSArray *files = [fm contentsOfDirectoryAtPath:dir error:nil];
   int removed = 0;
   for (NSString *f in files)
      removed += [fm removeItemAtPath:[dir stringByAppendingPathComponent:f] error:nil];
   int k = removed ? kill_named("duetexpertd") : 0;
   LOG("biome: %d damaged prediction stream file(s) removed, duetexpertd restarted %d", removed, k);
}

/*
 * Brightness (Note FE 0418): BackBoardServices' own call, as the Control Center slider uses, so the kernel log shows what
 * CoreBrightness then sets on the display (NOTEFE BRIGHT lines).
 */
static void brightness_test(void)
{
   void *h = dlopen("/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices", RTLD_NOW);
   void (*set)(float, int) = h ? (void (*)(float, int))dlsym(h, "BKSDisplayBrightnessSet") : NULL;
   float (*get)(void) = h ? (float (*)(void))dlsym(h, "BKSDisplayBrightnessGetCurrent") : NULL;
   if (!set || !get) {
      LOG("brightness: BackBoardServices calls missing");
      return;
   }
   LOG("brightness: now %.2f", get());
   float steps[] = { 0.3f, 0.8f, 0.5f };
   for (int i = 0; i < 3; i++) {
      set(steps[i], 1);
      sleep(2);
      LOG("brightness: set %.2f, now %.2f", steps[i], get());
   }
}


/* 0457: a line to the drop zone's cam.progress, synced: it survives the watchdog's reset when the kernel log does not */
static void progress(const char *fmt, ...)
{
   char line[200];
   va_list ap;
   va_start(ap, fmt);
   vsnprintf(line, sizeof line, fmt, ap);
   va_end(ap);
   int fd = open("/private/var/herolte/cam.progress", O_WRONLY | O_CREAT | O_APPEND, 0644);
   if (fd >= 0) {
      dprintf(fd, "%.1f %s\n", now(), line);
      fsync(fd);
      close(fd);
   }
   sync();
}

static void run(void)
{
   clock_gettime(CLOCK_MONOTONIC, &t0);
   char state[8] = "";
   size_t len = sizeof state;
   int r = sysctlbyname("kern.notefe_hid", state, &len, NULL, 0);
   LOG("start: kern.notefe_hid %s (%d), uid %d", r == 0 ? state : "missing", r, getuid());
   if (r != 0 || strncmp(state, "on", 2) != 0) {
      LOG("no synthetic input (herobot=1 not on the boot line): apps are launched but not scrolled");
   }
   /* Note FE 0432/0433: Bluetooth (NOTEFE BT lines in the kernel log): level from bt.level in the drop zone (default 2,
    * read only; 5 = UART loopback, chip power, HCI version), then the chip off again (6). */
   int bt = 2;
   NSString *lv = [NSString stringWithContentsOfFile:@"/private/var/herolte/bt.level" encoding:NSUTF8StringEncoding error:nil];
   if (lv.intValue >= 1 && lv.intValue <= 8)
      bt = lv.intValue;
   if (bt == 8) {      /* Note FE 0435: what BlueTool and bluetoothd look for besides the kernel controls */
      symlink("/dev/null", "/dev/cu.bluetooth");      /* bluetoothd: "No valid serial port found" without one */
      symlink("/dev/null", "/dev/uart.bluetooth");
      mkdir("/usr/share/firmware/bluetooth", 0755);
      static const unsigned char standin[] = { 0x4e, 0xfc, 0x04, 0xff, 0xff, 0xff, 0xff };   /* one Launch_RAM record */
      const char *names[] = { "Apollo_OS_MUR", "Apollo_OS_USI", "Pegasus_OS_MUR", "Pegasus_OS_USI", "Hercules_OS_MUR",
                              "Hercules_OS_USI", "Yoda_OS_MUR", "Yoda_OS_USI", "Tuborg_OS_MUR", "Tuborg_OS_USI" };
      const char *builds[] = { "5146", "5147", "5157", "5158", "5153", "5154", "5167", "5168", "5161", "5162" };
      int made = 0;
      for (int i = 0; i < 10; i++) {
         char path[160];
         snprintf(path, sizeof path, "/usr/share/firmware/bluetooth/BCM4357B1_19.1.282.%s_%s_20210524.hcd", builds[i], names[i]);
         if (access(path, F_OK) == 0) { made++; continue; }
         FILE *f = fopen(path, "wb");
         if (f) { fwrite(standin, 1, sizeof standin, f); fclose(f); made++; }
      }
      LOG("bluetooth: /dev links, %d stand-in BlueTool patch files", made);
      mg_set_string("WifiVendor", @"Murata");
   }
   if (bt >= 7) {      /* Note FE 0434: the chip's patch from the drop zone into the kernel first */
      NSData *fw = [NSData dataWithContentsOfFile:@"/private/var/herolte/bt-murata.hcd"];
      LOG("bluetooth patch file: %lu bytes, %s", (unsigned long)fw.length,
          fw.length && sysctlbyname("kern.notefe_bt_fw", NULL, NULL, (void *)fw.bytes, fw.length) == 0 ? "loaded" : "NOT loaded");
   }
   LOG("bluetooth level %d: %s", bt, sysctlbyname("kern.notefe_bt", NULL, NULL, &bt, sizeof bt) == 0 ? "logged" : "refused");
   if (bt == 8) {      /* the transport stays up: give bluetoothd time, then report */
      /* bluetoothd starts (and gives up on BlueTool) before the bot runs: SIGKILL, so launchd's KeepAlive
         (SuccessfulExit false) starts it again now that the transport and the answer are there. */
      LOG("bluetooth: bluetoothd restarted (%d)", kill_named_sig("bluetoothd", SIGKILL));
      LOG("bluetooth transport up: waiting 150 s for BlueTool / bluetoothd (two bridge reports)");
      sleep(150);
      LOG("bluetooth: 150 s done");
   } else if (bt >= 4) {
      int off = 6;
      LOG("bluetooth off: %s", sysctlbyname("kern.notefe_bt", NULL, NULL, &off, sizeof off) == 0 ? "ok" : "refused");
   }
   /* Note FE 0437: camera stage from cam.level (0 = none), kern.notefe_cam; NOTEFE CAM lines in the kernel log. */
   int cam = [NSString stringWithContentsOfFile:@"/private/var/herolte/cam.level" encoding:NSUTF8StringEncoding error:nil].intValue;
   /* 0455: camera options from cam.opts ("tp=2 mode=1 ..."): kern.notefe_cam_<name> each */
   NSString *opts = [NSString stringWithContentsOfFile:@"/private/var/herolte/cam.opts" encoding:NSUTF8StringEncoding error:nil];
   for (NSString *kv in [opts componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]) {
      NSArray *p = [kv componentsSeparatedByString:@"="];
      if (p.count != 2)
         continue;
      char name[64];
      snprintf(name, sizeof name, "kern.notefe_cam_%s", [p[0] UTF8String]);
      unsigned v = (unsigned)[p[1] intValue];
      LOG("camera option %s = %u: %s", name, v, sysctlbyname(name, NULL, NULL, &v, sizeof v) == 0 ? "set" : "refused");
   }
   if (cam >= 1)
      progress("level %d: asking", cam);
   if (cam >= 1 && cam <= 7)
      LOG("camera level %d: %s", cam, sysctlbyname("kern.notefe_cam", NULL, NULL, &cam, sizeof cam) == 0 ? "logged" : "refused");
   if (cam == 8) {     /* 0458: /dev/hakios-camera, then the Camera app for 15 s (mediaserverd's capture device, libnotefecam) */
      int seven = 7;
      LOG("camera device: %s", sysctlbyname("kern.notefe_cam", NULL, NULL, &seven, sizeof seven) == 0 ? "made" : "refused");
      /* 0461: mediaserverd lists its capture sources once, at its start (csu_getBackings: "Created 0 in-memory
       * sources" before the device existed): restart it now that /dev/hakios-camera is there */
      LOG("camera device: mediaserverd restarted (%d)", kill_named_sig("mediaserverd", SIGKILL));
      sleep(8);
      /* 0460: the cameras in MobileGestalt's cache (the answers computed at first boot said none) */
      mg_set_value("still-camera", @YES);
      mg_set_value("front-facing-camera", @YES);
      mg_set_value("rear-facing-camera", @YES);
      void *mg = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY);
      CFTypeRef (*mga)(CFStringRef, void *) = mg ? (CFTypeRef (*)(CFStringRef, void *))dlsym(mg, "MGCopyAnswer") : NULL;
      const char *keys[] = { "still-camera", "front-facing-camera", "rear-facing-camera", "video-camera" };
      for (int i = 0; mga && i < 4; i++) {
         CFTypeRef v = mga(CFStringCreateWithCString(NULL, keys[i], kCFStringEncodingUTF8), NULL);
         LOG("camera app: MobileGestalt %s = %s", keys[i], v ? [[(__bridge id)v description] UTF8String] : "(nil)");
      }
      sleep(20);
      progress("camera app: launching");
      LOG("camera app: launch %d", launch(@"com.apple.camera"));
      sleep(8);
      LOG("camera app: launch again %d", launch(@"com.apple.camera"));
      int camwait = [NSString stringWithContentsOfFile:@"/private/var/herolte/cam.wait" encoding:NSUTF8StringEncoding error:nil].intValue;
      sleep(camwait > 0 ? camwait : 15);
      progress("camera app: done");
      home();
      sleep(2);
   }
   /* Note FE: Control Center timing (cc.test = N cycles a pass): back-to-back opens (bottom-edge flick, 1 s, Home), then
    * one slow 1.5 s drag; a second pass 150 s later (cc.late = 1) to tell the boot's busy start from steady state.
    * "cc pass" / "cc done" lines bracket the A5XELTE FB windows. */
   int cc = [NSString stringWithContentsOfFile:@"/private/var/herolte/cc.test" encoding:NSUTF8StringEncoding error:nil].intValue;
   int cclate = [NSString stringWithContentsOfFile:@"/private/var/herolte/cc.late" encoding:NSUTF8StringEncoding error:nil].intValue;
   for (int pass = 0; cc > 0 && pass < (cclate ? 2 : 1); pass++) {
      if (pass == 1) {
         LOG("cc: waiting 150 s for the second pass");
         sleep(150);
      }
      home();
      sleep(2);
      LOG("cc pass %d: %d flicks", pass, cc);
      for (int i = 0; i < cc; i++) {
         swipe(720, 2550, 720, 1300, 250);
         sleep(1);
         home();
         usleep(700000);
      }
      LOG("cc pass %d: slow drag", pass);
      swipe(720, 2550, 720, 1300, 1500);
      sleep(1);
      home();
      sleep(1);
      LOG("cc done %d", pass);
      sleep(5);
   }
   if (cam == 7) {     /* 0456: /dev/hakios-camera as a reader sees it: 30 frames, the last kept for the Mac */
      progress("device: opening");
      int fd = open("/dev/hakios-camera", O_RDWR);
      progress("device: open returned %d (errno %d)", fd, fd < 0 ? errno : 0);
      if (fd < 0) {
         LOG("camera device: open failed (%d)", errno);
      } else {
         size_t cap = 256 + 1630 * 980;
         NSMutableData *buf = [NSMutableData dataWithLength:cap];
         ssize_t got = 0;
         int frames = 0;
         double t1 = now();
         for (int i = 0; i < 30; i++) {
            progress("device: read %d", i);
            got = read(fd, buf.mutableBytes, cap);
            const uint32_t *r = (const uint32_t *)((const char *)buf.mutableBytes + 100);
            progress("device: read %d -> %zd (slot %u, active %u, frame %u)", i, got, got > 120 ? r[0] : 0, got > 120 ? r[1] : 0,
                     got > 120 ? r[2] : 0);
            if (got <= 0) {
               LOG("camera device: read %d failed (%zd, errno %d)", i, got, errno);
               break;
            }
            frames++;
         }
         double t2 = now();
         const uint64_t *seq = (const uint64_t *)((const char *)buf.bytes + 40);
         LOG("camera device: %d frames in %.2f s (%.1f a second), the last %zd bytes, sequence %llu", frames, t2 - t1,
             frames / (t2 - t1 + 1e-9), got, got > 48 ? *seq : 0);
         if (got > 0) {
            [[buf subdataWithRange:NSMakeRange(0, (NSUInteger)got)] writeToFile:@"/private/var/herolte/cam.dev" atomically:YES];
            sync();
         }
         progress("device: %d frames, closing", frames);
         close(fd);
         progress("device: closed");
      }
   }
   if (cam >= 5) {     /* 0450: the picture to the drop zone, for hfs-read.py on the Mac */
      size_t len = 0;
      if (sysctlbyname("kern.notefe_cam_pic", NULL, &len, NULL, 0) == 0 && len) {
         NSMutableData *pic = [NSMutableData dataWithLength:len];
         if (sysctlbyname("kern.notefe_cam_pic", pic.mutableBytes, &len, NULL, 0) == 0) {
            BOOL ok = [pic writeToFile:@"/private/var/herolte/cam.raw8" atomically:YES];
            sync();
            LOG("camera picture: %zu bytes %s /private/var/herolte/cam.raw8", len, ok ? "written to" : "NOT written to");
         }
      } else {
         LOG("camera picture: none");
      }
   }
   /* Note FE 0437: the fail-safe's one-shot test (wdt.test = 1, boot line notefe_wdt=2): a marker first, synced, so the
    * boot after (if the watchdog's reset comes back to iOS rather than TWRP) does not stop the kicks again. */
   int wdt_test = [NSString stringWithContentsOfFile:@"/private/var/herolte/wdt.test" encoding:NSUTF8StringEncoding error:nil].intValue;
   if (wdt_test >= 1) {      /* each test number has its own marker (the drop zone never deletes files) */
      char marker[64];
      snprintf(marker, sizeof marker, "/private/var/herolte/wdt.tested%d", wdt_test);
      if (access(marker, F_OK) == 0) {
         LOG("watchdog test %d: already done once, skipped", wdt_test);
      } else {
         int fd = open(marker, O_WRONLY | O_CREAT | O_TRUNC, 0644);
         if (fd >= 0) {
            write(fd, "1\n", 2);
            fsync(fd);
            close(fd);
            sync();
            int one = 1;
            LOG("watchdog test: kicks stopped (%s); the watchdog should reset into TWRP now",
                sysctlbyname("kern.notefe_wdt_stop", NULL, NULL, &one, sizeof one) == 0 ? "ok" : "refused");
            sleep(120);
            LOG("watchdog test: still running 120 s later: NO RESET");
         } else {
            LOG("watchdog test: marker not written, test skipped");
         }
      }
   }
   NSArray *apps = [NSArray arrayWithObjects:@"com.apple.Preferences", @"com.apple.MobileSMS", @"com.apple.mobilenotes",
                      @"com.apple.mobilesafari", @"com.apple.mobilecal", @"com.apple.MobileAddressBook", @"com.apple.weather",
                      @"com.apple.Music", @"com.apple.mobileslideshow", @"com.apple.podcasts", @"com.apple.tv",
                      @"com.apple.iBooks", nil];     /* not a literal: NSConstantArray may not exist on iOS 16 */
   NSString *plan = [NSString stringWithContentsOfFile:@"/private/var/herolte/bot.plan" encoding:NSUTF8StringEncoding error:nil];
   if (plan.length) {
      NSMutableArray *list = [NSMutableArray array];
      for (NSString *l in [plan componentsSeparatedByString:@"\n"])
         if ([l stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].length && ![l hasPrefix:@"#"])
            [list addObject:[l stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]];
      apps = list;
   }
   /* Note FE: quick mode (bot.quick in the drop zone, QUICK=1 write-drop.sh) for feature tests: no apps, no swipes,
    * just the tests above, then straight back to TWRP. */
   if ([[NSString stringWithContentsOfFile:@"/private/var/herolte/bot.quick" encoding:NSUTF8StringEncoding error:nil] intValue] == 1) {
      LOG("quick mode: feature tests only");
      sleep(3);
      LOG("done");
      /* Note FE: bot.stay = 1 (STAY=1 write-drop.sh): leave the phone in iOS for the owner (no recovery). */
      if ([[NSString stringWithContentsOfFile:@"/private/var/herolte/bot.stay" encoding:NSUTF8StringEncoding error:nil] intValue] == 1) {
         LOG("stay mode: the phone stays in iOS");
         return;
      }
      LOG("asking for recovery: %s", hid("r 0") == 0 ? "ok (in 12 s)" : "refused (older kernel: herotwrp timer)");
      return;
   }
   enable_location();
   clean_biome();
   home();
   sleep(2);
   int first = 1;
   for (NSString *app in apps) {
      double start = now();
      int lr = launch(app);
      LOG("launch %s -> %d", app.UTF8String, lr);
      if (lr != 0)
         continue;
      sleep(7);
      LOG("scroll %s", app.UTF8String);
      swipe(720, 1900, 720, 700, 300); sleep(1);
      swipe(720, 1900, 720, 700, 300); sleep(1);
      swipe(720, 700, 720, 1900, 300); sleep(2);
      home();
      LOG("home after %s (%.1f s in the app)", app.UTF8String, now() - start);
      sleep(3);
      if (first) {
         first = 0;      /* unlocked by the first launch: now the home screen's pages */
         LOG("home screen: 4 page swipes");
         for (int i = 0; i < 2; i++) {
            swipe(1200, 1300, 240, 1300, 250); sleep(2);
            swipe(240, 1300, 1200, 1300, 250); sleep(2);
         }
      }
   }
   brightness_test();
   LOG("app switcher: double Home");
   key(3); usleep(150000); key(3); sleep(3); home(); sleep(2);
   LOG("done");
   /* Note FE 0416: back to TWRP 20 s after the run (idle frames, the logs' flush), not at the herotwrp timer. */
   sleep(8);
   LOG("asking for recovery: %s", hid("r 0") == 0 ? "ok (in 12 s)" : "refused (older kernel: herotwrp timer)");
}

int main(int argc, char **argv)
{
   @autoreleasepool {
      if (argc > 1 && strcmp(argv[1], "--run") == 0) {
         run();
         return 0;
      }
      /* hero-run waits for this process and kills it after 180 s: the work goes to a detached copy. */
      char *args[] = { argv[0], "--run", NULL };
      pid_t pid;
      posix_spawnattr_t a;
      posix_spawnattr_init(&a);
      posix_spawnattr_setflags(&a, POSIX_SPAWN_SETSID);
      int e = posix_spawn(&pid, argv[0], NULL, &a, args, environ);
      herodrm_log("NOTEFE BOT: started detached, pid %d, error %d", pid, e);
      return e;
   }
}
