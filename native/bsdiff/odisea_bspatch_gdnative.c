/*
 * GDNative wrapper for odisea_bspatch (Godot 3.x C API).
 * Exposes a NativeScript class "OdiseaBspatch" with one method:
 *   apply(old_path: String, patch_path: String, out_path: String) -> int
 * Returns 0 on success, negative on I/O error, positive on patch error.
 *
 * All paths are OS-globalized paths (use ProjectSettings.globalize_path in GD).
 */

#include <gdnative_api_struct.gen.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int odisea_bspatch(const uint8_t *old, int64_t oldsize,
                   const uint8_t *patch, int64_t patchsize,
                   uint8_t *newbuf, int64_t newsize);

static const godot_gdnative_core_api_struct *api = NULL;
static const godot_gdnative_ext_nativescript_api_struct *nativescript_api = NULL;

/* Read a whole file into a malloc'd buffer. Returns size, or -1 on error. */
static int64_t read_file(const char *path, uint8_t **out) {
	FILE *f = fopen(path, "rb");
	if (!f) return -1;
	fseek(f, 0, SEEK_END);
	long sz = ftell(f);
	fseek(f, 0, SEEK_SET);
	if (sz < 0) { fclose(f); return -1; }
	uint8_t *buf = (uint8_t *)malloc(sz > 0 ? sz : 1);
	if (!buf) { fclose(f); return -1; }
	size_t rd = fread(buf, 1, (size_t)sz, f);
	fclose(f);
	if ((long)rd != sz) { free(buf); return -1; }
	*out = buf;
	return sz;
}

/* Read a little-endian int64 from a patch header at offset 8. */
static int64_t patch_newsize(const uint8_t *patch, int64_t patchsize) {
	if (patchsize < 16) return -1;
	if (memcmp(patch, "ODSBSDF1", 8) != 0) return -1;
	int64_t y = patch[15] & 0x7F;
	for (int i = 14; i >= 8; i--) { y = y * 256; y += patch[i]; }
	if (patch[15] & 0x80) y = -y;
	return y;
}

static godot_string gd_string(const char *s) {
	godot_string gs;
	api->godot_string_new(&gs);
	api->godot_string_parse_utf8(&gs, s);
	return gs;
}

/* Convert a godot_string method-arg to a C string the caller must free. */
static char *gd_to_cstr(const godot_string *gs) {
	godot_char_string cs = api->godot_string_utf8(gs);
	const char *data = api->godot_char_string_get_data(&cs);
	size_t len = strlen(data);
	char *out = (char *)malloc(len + 1);
	memcpy(out, data, len + 1);
	api->godot_char_string_destroy(&cs);
	return out;
}

static godot_variant apply_patch(godot_object *obj, void *method_data,
                                 void *user_data, int num_args,
                                 godot_variant **args) {
	(void)obj; (void)method_data; (void)user_data;
	godot_variant ret;
	int rc = -100;
	if (num_args >= 3) {
		godot_string s_old = api->godot_variant_as_string(args[0]);
		godot_string s_patch = api->godot_variant_as_string(args[1]);
		godot_string s_out = api->godot_variant_as_string(args[2]);
		char *old_path = gd_to_cstr(&s_old);
		char *patch_path = gd_to_cstr(&s_patch);
		char *out_path = gd_to_cstr(&s_out);

		uint8_t *old_buf = NULL, *patch_buf = NULL, *new_buf = NULL;
		int64_t oldsize = read_file(old_path, &old_buf);
		int64_t patchsize = read_file(patch_path, &patch_buf);
		if (oldsize >= 0 && patchsize >= 0) {
			int64_t newsize = patch_newsize(patch_buf, patchsize);
			if (newsize >= 0) {
				new_buf = (uint8_t *)malloc(newsize > 0 ? newsize : 1);
				if (new_buf) {
					rc = odisea_bspatch(old_buf, oldsize, patch_buf, patchsize, new_buf, newsize);
					if (rc == 0) {
						FILE *of = fopen(out_path, "wb");
						if (of) {
							size_t wr = fwrite(new_buf, 1, (size_t)newsize, of);
							fclose(of);
							if ((int64_t)wr != newsize) rc = -101;
						} else {
							rc = -102;
						}
					}
				} else { rc = -103; }
			} else { rc = -104; }
		} else { rc = -105; }

		if (old_buf) free(old_buf);
		if (patch_buf) free(patch_buf);
		if (new_buf) free(new_buf);
		free(old_path); free(patch_path); free(out_path);
		api->godot_string_destroy(&s_old);
		api->godot_string_destroy(&s_patch);
		api->godot_string_destroy(&s_out);
	}
	api->godot_variant_new_int(&ret, rc);
	return ret;
}

/* --- GDNative boilerplate --- */

void GDN_EXPORT godot_gdnative_init(godot_gdnative_init_options *o) {
	api = o->api_struct;
	for (unsigned int i = 0; i < api->num_extensions; i++) {
		if (api->extensions[i]->type == GDNATIVE_EXT_NATIVESCRIPT) {
			nativescript_api = (const godot_gdnative_ext_nativescript_api_struct *)api->extensions[i];
		}
	}
}

void GDN_EXPORT godot_gdnative_terminate(godot_gdnative_terminate_options *o) {
	(void)o;
	api = NULL;
	nativescript_api = NULL;
}

static godot_object *ctor(godot_object *obj, void *method_data) {
	(void)obj; (void)method_data;
	return NULL;
}
static void dtor(godot_object *obj, void *method_data, void *user_data) {
	(void)obj; (void)method_data; (void)user_data;
}

void GDN_EXPORT godot_nativescript_init(void *desc) {
	godot_instance_create_func create = { ctor, NULL, NULL };
	godot_instance_destroy_func destroy = { dtor, NULL, NULL };
	nativescript_api->godot_nativescript_register_class(
		desc, "OdiseaBspatch", "Reference", create, destroy);

	godot_instance_method m = { apply_patch, NULL, NULL };
	godot_method_attributes attr = { GODOT_METHOD_RPC_MODE_DISABLED };
	nativescript_api->godot_nativescript_register_method(
		desc, "OdiseaBspatch", "apply", attr, m);
}
