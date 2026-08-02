// Standalone ASTC block compressor for texture import.
//
// Bypasses Godot's built-in astcenc integration, which hardcodes block size
// 4x4 and quality MEDIUM with no per-texture-type awareness
// (editor/import/resource_importer_texture.cpp and
// modules/astcenc/image_compress_astcenc.cpp in Godot's own source). This
// tool exposes the same vendored astcenc library with configurable block
// size, quality, and the ASTCENC_FLG_MAP_NORMAL angular-error mode for
// normal maps, invoked by a custom EditorImportPlugin via OS.execute().
//
// Usage: astc_compress <in.rgba8> <w> <h> <block_x> <block_y> <quality> <mode> <out.astc>
//   mode: "color" or "normal" (normal expects X in R, Y in G of the input)
#include <astcenc.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

int main(int argc, char **argv) {
    if (argc != 9) {
        fprintf(stderr, "usage: %s in.rgba8 w h block_x block_y quality mode out.astc\n", argv[0]);
        return 1;
    }
    const char *in_path = argv[1];
    int w = atoi(argv[2]);
    int h = atoi(argv[3]);
    int block_x = atoi(argv[4]);
    int block_y = atoi(argv[5]);
    float quality = atof(argv[6]);
    bool normal_mode = strcmp(argv[7], "normal") == 0;
    const char *out_path = argv[8];

    FILE *f = fopen(in_path, "rb");
    if (!f) {
        fprintf(stderr, "astc_compress: cannot open input %s\n", in_path);
        return 1;
    }
    std::vector<uint8_t> pixels((size_t)w * h * 4);
    size_t read = fread(pixels.data(), 1, pixels.size(), f);
    fclose(f);
    if (read != pixels.size()) {
        fprintf(stderr, "astc_compress: short read on %s (%zu of %zu bytes)\n", in_path, read, pixels.size());
        return 1;
    }

    unsigned int flags = normal_mode ? ASTCENC_FLG_MAP_NORMAL : 0;

    astcenc_config config;
    astcenc_error status = astcenc_config_init(ASTCENC_PRF_LDR, block_x, block_y, 1, quality, flags, &config);
    if (status != ASTCENC_SUCCESS) {
        fprintf(stderr, "astc_compress: config init failed: %s\n", astcenc_get_error_string(status));
        return 1;
    }

    astcenc_context *context;
    status = astcenc_context_alloc(&config, 1, &context);
    if (status != ASTCENC_SUCCESS) {
        fprintf(stderr, "astc_compress: context alloc failed: %s\n", astcenc_get_error_string(status));
        return 1;
    }

    unsigned int block_count_x = (w + block_x - 1) / block_x;
    unsigned int block_count_y = (h + block_y - 1) / block_y;
    size_t comp_len = (size_t)block_count_x * block_count_y * 16;
    std::vector<uint8_t> dest(comp_len);

    astcenc_image image;
    image.dim_x = w;
    image.dim_y = h;
    image.dim_z = 1;
    image.data_type = ASTCENC_TYPE_U8;
    void *slices = pixels.data();
    image.data = &slices;

    astcenc_swizzle swizzle;
    if (normal_mode) {
        // rrrg: default ASTC normal-map channel ordering (X duplicated into
        // R/G/B, Y into A) - matches ASTCENC_FLG_MAP_NORMAL's expectation.
        swizzle = { ASTCENC_SWZ_R, ASTCENC_SWZ_R, ASTCENC_SWZ_R, ASTCENC_SWZ_G };
    } else {
        swizzle = { ASTCENC_SWZ_R, ASTCENC_SWZ_G, ASTCENC_SWZ_B, ASTCENC_SWZ_A };
    }

    status = astcenc_compress_image(context, &image, &swizzle, dest.data(), comp_len, 0);
    astcenc_context_free(context);
    if (status != ASTCENC_SUCCESS) {
        fprintf(stderr, "astc_compress: compression failed: %s\n", astcenc_get_error_string(status));
        return 1;
    }

    FILE *out = fopen(out_path, "wb");
    if (!out) {
        fprintf(stderr, "astc_compress: cannot open output %s\n", out_path);
        return 1;
    }
    fwrite(dest.data(), 1, dest.size(), out);
    fclose(out);
    return 0;
}
