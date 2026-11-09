// Oracle helper: loads each argv file through LibreSprite's own loader and prints what it decoded.
#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "app/app.h"
#include "app/context.h"
#include "app/document.h"
#include "app/file/file.h"
#include "she/she.h"
#include "doc/cel.h"
#include "doc/image.h"
#include "doc/layer.h"
#include "doc/primitives.h"
#include "doc/sprite.h"

#include <cinttypes>
#include <cstdio>
#include <memory>

int app_main(int, char**) { return 0; }

int main(int argc, char** argv)
{
  new app::App();
  she::create_system();
  int rc = 0;
  for (int i = 1; i < argc; ++i) {
    app::Context ctx;
    std::unique_ptr<app::Document> doc(app::load_document(&ctx, argv[i]));
    if (!doc) {
      printf("%s LOAD-FAILED\n", argv[i]);
      rc = 1;
      continue;
    }
    doc::Sprite* sprite = doc->sprite();
    doc::Layer* layer = sprite->folder()->getFirstLayer();
    std::shared_ptr<doc::Cel> cel = layer ? layer->cel(0) : nullptr;
    doc::Image* image = cel ? cel->image() : nullptr;
    printf("%s %dx%d frames=%d format=%d", argv[i], sprite->width(), sprite->height(),
           int(sprite->totalFrames()), int(sprite->pixelFormat()));
    if (image && image->width() > 8 && image->height() > 8)
      printf(" px0=%08" PRIx32 " px1=%08" PRIx32, uint32_t(doc::get_pixel(image, 0, 0)),
             uint32_t(doc::get_pixel(image, 8, 8)));
    printf("\n");
  }
  return rc;
}
