#include <stdint.h>
#include <stdio.h>
#include <string.h>

#if defined(_WIN32)
#define EXPORT __declspec(dllexport)
#else
#define EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

extern "C" {

// Writes a chunk of bytes to a specific offset in a file.
// Returns 1 on success, 0 on failure.
EXPORT int WriteChunk(const char* filePath, const uint8_t* data, int length, int64_t offset) {
    if (filePath == nullptr || data == nullptr || length <= 0) {
        return 0; // Invalid arguments
    }

    FILE* file = fopen(filePath, "r+b"); // Open for read/write. File must exist or use fallback
    if (file == nullptr) {
        // If it doesn't exist, create it.
        file = fopen(filePath, "wb");
        if (file == nullptr) return 0;
    }

    if (fseek(file, offset, SEEK_SET) != 0) {
        fclose(file);
        return 0; // Seek failed
    }

    size_t written = fwrite(data, 1, length, file);
    fclose(file);

    return (written == length) ? 1 : 0;
}

}
