#!/usr/bin/env python3
"""Note FE: Panfrost's disk shader cache keys itself on the ELF build-id; Mach-O has none. On Apple platforms use the
LC_UUID of the image that holds the driver (new for every build, so a rebuilt Mesa never reads an old cache).
   patch-pan-disk-cache.py MESA_DIR   (idempotent)"""
import sys, os
p = os.path.join(sys.argv[1], 'src/gallium/drivers/panfrost/pan_disk_cache.c')
s = open(p).read()
if 'notefe_image_uuid' in s:
    sys.exit(0)
old = '''   const struct build_id_note *note =
      build_id_find_nhdr_for_addr(panfrost_disk_cache_init);
   assert(note && build_id_length(note) == 20); /* sha1 */

   const uint8_t *id_sha1 = build_id_data(note);
   assert(id_sha1);

   char timestamp[41];
   _mesa_sha1_format(timestamp, id_sha1);
'''
assert s.count(old) == 1
s = s.replace(old, '''#ifdef __APPLE__
   char timestamp[41];
   if (!notefe_image_uuid(timestamp))
      return;
#else
''' + old + '''#endif
''')
helper = '''
#ifdef __APPLE__
#include <dlfcn.h>
#include <mach-o/loader.h>
/* Note FE: the image's LC_UUID as 32 hex digits (instead of the ELF build-id). */
static bool
notefe_image_uuid(char out[41])
{
   Dl_info info;
   if (!dladdr((const void *)panfrost_disk_cache_init, &info) || !info.dli_fbase)
      return false;
   const struct mach_header_64 *mh = info.dli_fbase;
   const struct load_command *lc = (const struct load_command *)(mh + 1);
   for (uint32_t i = 0; i < mh->ncmds; i++) {
      if (lc->cmd == LC_UUID) {
         const uint8_t *u = ((const struct uuid_command *)lc)->uuid;
         for (int j = 0; j < 16; j++)
            snprintf(out + 2 * j, 3, "%02x", u[j]);
         return true;
      }
      lc = (const struct load_command *)((const char *)lc + lc->cmdsize);
   }
   return false;
}
#endif
'''
anchor = '/**\n * Initialize the on-disk shader cache.\n */'
assert s.count(anchor) == 1
s = s.replace(anchor, helper + '\n' + anchor)
open(p, 'w').write(s)
print('patched', p)
