// Fuzz harness: loads the input through LibreSprite's own file loader (FileOp, the same path the
// GUI and CLI use) with the format selected by FUZZ_EXT, the extension of the staged temp file.
#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "app/app.h"
#include "app/context.h"
#include "app/document.h"
#include "app/file/file.h"
#include "she/she.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <memory>
#include <string>
#include <unistd.h>

#ifdef FUZZ_SIDECAR_PNG
#include "mayhem/sheet_png.h"
#endif

#ifndef FUZZ_EXT
#error "define FUZZ_EXT (file extension selecting the loader)"
#endif

static std::string g_path;
#ifdef FUZZ_SIDECAR_PNG
static std::string g_sidecar;
#endif

extern "C" int LLVMFuzzerInitialize(int*, char***)
{
  // Non-GUI App singleton (never destroyed: ~App needs a fully initialised app): loaders consult App::instance()->isGui().
  new app::App();
  // The ico loader goes through she::instance() (SDL_image); create the system without starting a display.
  she::create_system();
  const char* tmp = getenv("TMPDIR");
  g_path = std::string(tmp && *tmp ? tmp : "/tmp") + "/libresprite-fuzz-" +
           std::to_string(getpid()) + "-input." FUZZ_EXT;
#ifdef FUZZ_SIDECAR_PNG
  // A Pixly .anim describes regions of a sprite sheet that it loads from the same path with a .png extension.
  g_sidecar = g_path.substr(0, g_path.size() - sizeof(FUZZ_EXT)) + "png";
  if (FILE* f = fopen(g_sidecar.c_str(), "wb")) {
    fwrite(kSheetPng, 1, sizeof(kSheetPng), f);
    fclose(f);
  }
#endif
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

  app::Context ctx;
  std::unique_ptr<app::Document> doc(app::load_document(&ctx, g_path.c_str()));
  return 0;
}
int app_main(int, char**) { return 0; }
