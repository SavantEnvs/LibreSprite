// Fuzz harness: loads the input as a palette file through app::load_palette, the format (col, gpl or
// pal) selected by FUZZ_EXT, the extension of the staged temp file.
#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "app/app.h"
#include "app/file/palette_file.h"
#include "doc/palette.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <memory>
#include <string>
#include <unistd.h>

#ifndef FUZZ_EXT
#error "define FUZZ_EXT (palette file extension selecting the loader)"
#endif

static std::string g_path;

extern "C" int LLVMFuzzerInitialize(int*, char***)
{
  new app::App();
  const char* tmp = getenv("TMPDIR");
  g_path = std::string(tmp && *tmp ? tmp : "/tmp") + "/libresprite-fuzz-" +
           std::to_string(getpid()) + "-input." FUZZ_EXT;
  return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size)
{
  FILE* f = fopen(g_path.c_str(), "wb");
  if (!f)
    return 0;
  if (size && fwrite(data, 1, size, f) != size) {
    fclose(f);
    return 0;
  }
  fclose(f);

  std::shared_ptr<doc::Palette> pal = app::load_palette(g_path.c_str());
  return 0;
}

int app_main(int, char**) { return 0; }
