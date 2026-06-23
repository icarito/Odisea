/*
 * bsdiff_gen.c — patch GENERATOR (host/CI only, not shipped in the game).
 * Classic Colin Percival bsdiff with embedded qsufsort (public domain), but
 * emitting our uncompressed ODSBSDF1 layout (the transport gzips the patch):
 *
 *   "ODSBSDF1" (8)  newsize int64-LE (8)
 *   then, repeated: ctrl[0],ctrl[1],ctrl[2] (3x int64 off-format), diff bytes,
 *   extra bytes — exactly what odisea_bspatch() reads.
 *
 * Usage: bsdiff_gen <oldfile> <newfile> <patchfile>
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void split(int64_t *I, int64_t *V, int64_t start, int64_t len, int64_t h) {
	int64_t i, j, k, x, tmp, jj, kk;
	if (len < 16) {
		for (k = start; k < start + len; k += j) {
			j = 1; x = V[I[k] + h];
			for (i = 1; k + i < start + len; i++) {
				if (V[I[k + i] + h] < x) { x = V[I[k + i] + h]; j = 0; }
				if (V[I[k + i] + h] == x) { tmp = I[k + j]; I[k + j] = I[k + i]; I[k + i] = tmp; j++; }
			}
			for (i = 0; i < j; i++) V[I[k + i]] = k + j - 1;
			if (j == 1) I[k] = -1;
		}
		return;
	}
	x = V[I[start + len / 2] + h];
	jj = 0; kk = 0;
	for (i = start; i < start + len; i++) {
		if (V[I[i] + h] < x) jj++;
		if (V[I[i] + h] == x) kk++;
	}
	jj += start; kk += jj;
	i = start; j = 0; k = 0;
	while (i < jj) {
		if (V[I[i] + h] < x) i++;
		else if (V[I[i] + h] == x) { tmp = I[i]; I[i] = I[jj + j]; I[jj + j] = tmp; j++; }
		else { tmp = I[i]; I[i] = I[kk + k]; I[kk + k] = tmp; k++; }
	}
	while (jj + j < kk) {
		if (V[I[jj + j] + h] == x) j++;
		else { tmp = I[jj + j]; I[jj + j] = I[kk + k]; I[kk + k] = tmp; k++; }
	}
	if (jj > start) split(I, V, start, jj - start, h);
	for (i = 0; i < kk - jj; i++) V[I[jj + i]] = kk - 1;
	if (jj == kk - 1) I[jj] = -1;
	if (start + len > kk) split(I, V, kk, start + len - kk, h);
}

static void qsufsort(int64_t *I, int64_t *V, const uint8_t *old, int64_t oldsize) {
	int64_t buckets[256];
	int64_t i, h, len;
	for (i = 0; i < 256; i++) buckets[i] = 0;
	for (i = 0; i < oldsize; i++) buckets[old[i]]++;
	for (i = 1; i < 256; i++) buckets[i] += buckets[i - 1];
	for (i = 255; i > 0; i--) buckets[i] = buckets[i - 1];
	buckets[0] = 0;
	for (i = 0; i < oldsize; i++) I[++buckets[old[i]]] = i;
	I[0] = oldsize;
	for (i = 0; i < oldsize; i++) V[i] = buckets[old[i]];
	V[oldsize] = 0;
	for (i = 1; i < 256; i++) if (buckets[i] == buckets[i - 1] + 1) I[buckets[i]] = -1;
	I[0] = -1;
	for (h = 1; I[0] != -(oldsize + 1); h += h) {
		len = 0;
		for (i = 0; i < oldsize + 1;) {
			if (I[i] < 0) { len -= I[i]; i -= I[i]; }
			else {
				if (len) I[i - len] = -len;
				len = V[I[i]] + 1 - i;
				split(I, V, i, len, h);
				i += len; len = 0;
			}
		}
		if (len) I[i - len] = -len;
	}
	for (i = 0; i < oldsize + 1; i++) I[V[i]] = i;
}

static int64_t matchlen(const uint8_t *a, int64_t alen, const uint8_t *b, int64_t blen) {
	int64_t i;
	for (i = 0; (i < alen) && (i < blen); i++) if (a[i] != b[i]) break;
	return i;
}

static int64_t search(const int64_t *I, const uint8_t *old, int64_t oldsize,
                      const uint8_t *newp, int64_t newsize, int64_t st, int64_t en, int64_t *pos) {
	int64_t x, y;
	if (en - st < 2) {
		x = matchlen(old + I[st], oldsize - I[st], newp, newsize);
		y = matchlen(old + I[en], oldsize - I[en], newp, newsize);
		if (x > y) { *pos = I[st]; return x; }
		else { *pos = I[en]; return y; }
	}
	x = st + (en - st) / 2;
	if (memcmp(old + I[x], newp, (size_t)((oldsize - I[x] < newsize ? oldsize - I[x] : newsize))) < 0)
		return search(I, old, oldsize, newp, newsize, x, en, pos);
	else
		return search(I, old, oldsize, newp, newsize, st, x, pos);
}

static void offtout(int64_t x, uint8_t *buf) {
	int64_t y = x < 0 ? -x : x;
	for (int i = 0; i < 8; i++) { buf[i] = (uint8_t)(y % 256); y /= 256; }
	if (x < 0) buf[7] |= 0x80;
}

int main(int argc, char **argv) {
	if (argc != 4) { fprintf(stderr, "usage: %s old new patch\n", argv[0]); return 1; }
	FILE *f;
	uint8_t *old, *newp;
	int64_t oldsize, newsize;

	f = fopen(argv[1], "rb"); if (!f) return 2;
	fseek(f, 0, SEEK_END); oldsize = ftell(f); fseek(f, 0, SEEK_SET);
	old = malloc(oldsize + 1); fread(old, 1, oldsize, f); fclose(f);

	f = fopen(argv[2], "rb"); if (!f) return 3;
	fseek(f, 0, SEEK_END); newsize = ftell(f); fseek(f, 0, SEEK_SET);
	newp = malloc(newsize + 1); fread(newp, 1, newsize, f); fclose(f);

	int64_t *I = malloc((oldsize + 1) * sizeof(int64_t));
	int64_t *V = malloc((oldsize + 1) * sizeof(int64_t));
	qsufsort(I, V, old, oldsize);
	free(V);

	FILE *pf = fopen(argv[3], "wb"); if (!pf) return 4;
	fwrite("ODSBSDF1", 1, 8, pf);
	uint8_t hb[8]; offtout(newsize, hb); fwrite(hb, 1, 8, pf);

	int64_t scan = 0, pos = 0, len = 0, lastscan = 0, lastpos = 0, lastoffset = 0;
	uint8_t buf[8];
	while (scan < newsize) {
		int64_t oldscore = 0;
		for (int64_t scsf = scan += len; scan < newsize; scan++) {
			len = search(I, old, oldsize, newp + scan, newsize - scan, 0, oldsize, &pos);
			for (; scsf < scan + len; scsf++)
				if ((scsf + lastoffset < oldsize) && (old[scsf + lastoffset] == newp[scsf])) oldscore++;
			if (((len == oldscore) && (len != 0)) || (len > oldscore + 8)) break;
			if ((scan + lastoffset < oldsize) && (old[scan + lastoffset] == newp[scan])) oldscore--;
		}
		if ((len != oldscore) || (scan == newsize)) {
			int64_t s = 0, Sf = 0, lenf = 0;
			for (int64_t i = 0; (lastscan + i < scan) && (lastpos + i < oldsize);) {
				if (old[lastpos + i] == newp[lastscan + i]) s++;
				i++;
				if (s * 2 - i > Sf * 2 - lenf) { Sf = s; lenf = i; }
			}
			int64_t lenb = 0;
			if (scan < newsize) {
				int64_t sb = 0, Sb = 0;
				for (int64_t i = 1; (scan >= lastscan + i) && (pos >= i); i++) {
					if (old[pos - i] == newp[scan - i]) sb++;
					if (sb * 2 - i > Sb * 2 - lenb) { Sb = sb; lenb = i; }
				}
			}
			if (lastscan + lenf > scan - lenb) {
				int64_t overlap = (lastscan + lenf) - (scan - lenb);
				int64_t ss = 0, Ss = 0, lens = 0;
				for (int64_t i = 0; i < overlap; i++) {
					if (newp[lastscan + lenf - overlap + i] == old[lastpos + lenf - overlap + i]) ss++;
					if (newp[scan - lenb + i] == old[pos - lenb + i]) ss--;
					if (ss > Ss) { Ss = ss; lens = i + 1; }
				}
				lenf += lens - overlap; lenb -= lens;
			}
			offtout(lenf, buf); fwrite(buf, 1, 8, pf);
			offtout((scan - lenb) - (lastscan + lenf), buf); fwrite(buf, 1, 8, pf);
			offtout((pos - lenb) - (lastpos + lenf), buf); fwrite(buf, 1, 8, pf);
			/* diff block */
			for (int64_t i = 0; i < lenf; i++) { uint8_t d = newp[lastscan + i] - old[lastpos + i]; fwrite(&d, 1, 1, pf); }
			/* extra block */
			for (int64_t i = 0; i < (scan - lenb) - (lastscan + lenf); i++) fwrite(&newp[lastscan + lenf + i], 1, 1, pf);
			lastscan = scan - lenb; lastpos = pos - lenb; lastoffset = pos - scan;
		}
	}
	fclose(pf);
	free(I); free(old); free(newp);
	return 0;
}
