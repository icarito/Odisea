/*
 * bspatch.c — based on Matthew Endsley's public-domain bsdiff/bspatch
 * (https://github.com/mendsley/bsdiff). Adapted to read the patch as a raw
 * stream (no bzip2): the update transport already gzips the patch, so the
 * patch format here is the uncompressed bsdiff control+diff+extra layout.
 *
 * Patch layout (this variant):
 *   header (32 bytes):
 *     magic "ODSBSDF1" (8)         -- Odisea bsdiff, format 1
 *     newsize int64 (8, LE)        -- size of the reconstructed file
 *   then three concatenated raw streams, lengths from the control entries.
 *
 * To keep the wrapper minimal we use the classic bsdiff stream layout but
 * uncompressed: a sequence of control triples and the diff/extra bytes are
 * interleaved exactly as classic bspatch expects, read sequentially.
 */

#include <stdint.h>
#include <string.h>

static int64_t offtin(const uint8_t *buf) {
	int64_t y = buf[7] & 0x7F;
	y = y * 256; y += buf[6];
	y = y * 256; y += buf[5];
	y = y * 256; y += buf[4];
	y = y * 256; y += buf[3];
	y = y * 256; y += buf[2];
	y = y * 256; y += buf[1];
	y = y * 256; y += buf[0];
	if (buf[7] & 0x80) y = -y;
	return y;
}

/*
 * Apply a patch held entirely in memory.
 *   old, oldsize   : original file bytes
 *   patch, patchsize: patch bytes (our uncompressed bsdiff layout)
 *   newbuf, newsize: output buffer (caller allocates newsize from header)
 * Returns 0 on success, non-zero on error.
 */
int odisea_bspatch(
		const uint8_t *old, int64_t oldsize,
		const uint8_t *patch, int64_t patchsize,
		uint8_t *newbuf, int64_t newsize) {

	/* header */
	if (patchsize < 16) return 1;
	if (memcmp(patch, "ODSBSDF1", 8) != 0) return 2;
	int64_t declared = offtin(patch + 8);
	if (declared != newsize) return 3;

	const uint8_t *p = patch + 16;
	const uint8_t *pend = patch + patchsize;

	int64_t oldpos = 0, newpos = 0;
	while (newpos < newsize) {
		/* control triple: ctrl[0]=diff len, ctrl[1]=extra len, ctrl[2]=oldpos seek */
		int64_t ctrl[3];
		for (int i = 0; i < 3; i++) {
			if (p + 8 > pend) return 4;
			ctrl[i] = offtin(p);
			p += 8;
		}
		if (ctrl[0] < 0 || ctrl[1] < 0) return 5;
		if (newpos + ctrl[0] > newsize) return 6;

		/* diff block: add patch bytes to old bytes */
		if (p + ctrl[0] > pend) return 7;
		for (int64_t i = 0; i < ctrl[0]; i++) {
			uint8_t ob = (oldpos + i >= 0 && oldpos + i < oldsize) ? old[oldpos + i] : 0;
			newbuf[newpos + i] = (uint8_t)(p[i] + ob);
		}
		p += ctrl[0];
		newpos += ctrl[0];
		oldpos += ctrl[0];

		if (newpos + ctrl[1] > newsize) return 8;
		/* extra block: copy patch bytes verbatim */
		if (p + ctrl[1] > pend) return 9;
		memcpy(newbuf + newpos, p, (size_t)ctrl[1]);
		p += ctrl[1];
		newpos += ctrl[1];

		oldpos += ctrl[2];
	}
	return 0;
}
