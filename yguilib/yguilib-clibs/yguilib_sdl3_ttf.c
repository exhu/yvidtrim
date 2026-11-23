#include "yguilib_sdl3_ttf.h"

#include <SDL3/SDL.h>
#include <SDL3_ttf/SDL_ttf.h>
#include <SDL3_ttf/SDL_textengine.h>
#include <stdbool.h>

static bool s_ttf_initialized = false;

int yguilib_sdl3_ttf_init(void) {
  if (!s_ttf_initialized) {
    if (!TTF_Init()) {
      return -1;
    }
    s_ttf_initialized = true;
  }
  return 0;
}

const char *yguilib_sdl3_ttf_get_error(void) {
  return SDL_GetError();
}

void yguilib_sdl3_ttf_quit(void) {
  if (s_ttf_initialized) {
    TTF_Quit();
    s_ttf_initialized = false;
  }
}

yguilib_sdl3_ttf_Font *yguilib_sdl3_ttf_open_font(
  const char *file,
  float pt_size
) {
  if (!file || pt_size <= 0.0f) {
    return NULL;
  }
  if (!s_ttf_initialized && yguilib_sdl3_ttf_init() != 0) {
    return NULL;
  }
  TTF_Font *font = TTF_OpenFont(file, pt_size);
  return (yguilib_sdl3_ttf_Font *)font;
}

yguilib_sdl3_ttf_Font *yguilib_sdl3_ttf_open_font_from_mem(
  const void *data,
  size_t size,
  float pt_size
) {
  if (!data || size == 0 || pt_size <= 0.0f) {
    return NULL;
  }
  if (!s_ttf_initialized && yguilib_sdl3_ttf_init() != 0) {
    return NULL;
  }
  SDL_IOStream *io = SDL_IOFromConstMem(data, size);
  if (!io) {
    return NULL;
  }
  TTF_Font *font = TTF_OpenFontIO(io, true, pt_size);
  return (yguilib_sdl3_ttf_Font *)font;
}

void yguilib_sdl3_ttf_close_font(yguilib_sdl3_ttf_Font *font) {
  if (font) {
    TTF_CloseFont((TTF_Font *)font);
  }
}

int yguilib_sdl3_ttf_set_font_size(
  yguilib_sdl3_ttf_Font *font,
  float pt_size
) {
  if (!font || pt_size <= 0.0f) {
    return -1;
  }
  if (!TTF_SetFontSize((TTF_Font *)font, pt_size)) {
    return -1;
  }
  return 0;
}

int yguilib_sdl3_ttf_get_font_height(const yguilib_sdl3_ttf_Font *font) {
  if (!font) {
    return 0;
  }
  return TTF_GetFontHeight((const TTF_Font *)font);
}

int yguilib_sdl3_ttf_set_font_outline(
  yguilib_sdl3_ttf_Font *font,
  int outline
) {
  if (!font || outline < 0) {
    return -1;
  }
  if (!TTF_SetFontOutline((TTF_Font *)font, outline)) {
    return -1;
  }
  return 0;
}

int yguilib_sdl3_ttf_get_font_outline(const yguilib_sdl3_ttf_Font *font) {
  if (!font) {
    return 0;
  }
  return TTF_GetFontOutline((const TTF_Font *)font);
}

int yguilib_sdl3_ttf_get_font_ascent(const yguilib_sdl3_ttf_Font *font) {
  if (!font) {
    return 0;
  }
  return TTF_GetFontAscent((const TTF_Font *)font);
}

int yguilib_sdl3_ttf_get_font_descent(const yguilib_sdl3_ttf_Font *font) {
  if (!font) {
    return 0;
  }
  return TTF_GetFontDescent((const TTF_Font *)font);
}

int yguilib_sdl3_ttf_get_font_line_skip(const yguilib_sdl3_ttf_Font *font) {
  if (!font) {
    return 0;
  }
  return TTF_GetFontLineSkip((const TTF_Font *)font);
}

int yguilib_sdl3_ttf_get_text_size(
  const yguilib_sdl3_ttf_Font *font,
  const char *text,
  size_t length,
  int *w,
  int *h
) {
  if (!font || !text) {
    return -1;
  }
  if (length == 0) {
    if (w) {
      *w = 0;
    }
    if (h) {
      *h = 0;
    }
    return 0;
  }
  if (!TTF_GetStringSize((TTF_Font *)font, text, length, w, h)) {
    return -1;
  }
  return 0;
}

yguilib_sdl3_ttf_Surface *yguilib_sdl3_ttf_render_text_blended(
  yguilib_sdl3_ttf_Font *font,
  const char *text,
  size_t length,
  uint8_t r,
  uint8_t g,
  uint8_t b,
  uint8_t a
) {
  if (!font || !text || length == 0) {
    return NULL;
  }
  SDL_Color fg = {r, g, b, a};
  SDL_Surface *surf = TTF_RenderText_Blended(
    (TTF_Font *)font,
    text,
    length,
    fg
  );
  if (!surf) {
    return NULL;
  }
  if (surf->format != SDL_PIXELFORMAT_RGBA32) {
    SDL_Surface *converted = SDL_ConvertSurface(
      surf,
      SDL_PIXELFORMAT_RGBA32
    );
    SDL_DestroySurface(surf);
    if (!converted) {
      return NULL;
    }
    surf = converted;
  }
  return (yguilib_sdl3_ttf_Surface *)surf;
}

int yguilib_sdl3_ttf_get_surface_size(
  const yguilib_sdl3_ttf_Surface *surface,
  int *w,
  int *h
) {
  if (!surface) {
    return -1;
  }
  const SDL_Surface *surf = (const SDL_Surface *)surface;
  if (w) {
    *w = surf->w;
  }
  if (h) {
    *h = surf->h;
  }
  return 0;
}

int yguilib_sdl3_ttf_get_surface_pitch(
  const yguilib_sdl3_ttf_Surface *surface
) {
  if (!surface) {
    return 0;
  }
  return ((const SDL_Surface *)surface)->pitch;
}

const void *yguilib_sdl3_ttf_get_surface_pixels(
  const yguilib_sdl3_ttf_Surface *surface
) {
  if (!surface) {
    return NULL;
  }
  return ((const SDL_Surface *)surface)->pixels;
}

void yguilib_sdl3_ttf_destroy_surface(yguilib_sdl3_ttf_Surface *surface) {
  if (surface) {
    SDL_DestroySurface((SDL_Surface *)surface);
  }
}

static int s_engine_sentinel;

static bool SDLCALL layout_create_text(void *userdata, TTF_Text *text) {
  (void)userdata;
  text->internal->engine_text = &s_engine_sentinel;
  return true;
}

static void SDLCALL layout_destroy_text(void *userdata, TTF_Text *text) {
  (void)userdata;
  (void)text;
}

static TTF_TextEngine *layout_engine(void) {
  static TTF_TextEngine engine;
  static bool initialized = false;
  if (!initialized) {
    SDL_INIT_INTERFACE(&engine);
    engine.CreateText = layout_create_text;
    engine.DestroyText = layout_destroy_text;
    initialized = true;
  }
  return &engine;
}

int yguilib_sdl3_ttf_layout_text(
  yguilib_sdl3_ttf_Font *font,
  const char *text,
  size_t length,
  yguilib_sdl3_ttf_GlyphQuad *out,
  int cap,
  int *w,
  int *h
) {
  if (!font || !text || cap < 0 || (cap > 0 && !out)) {
    return -1;
  }
  if (w) {
    *w = 0;
  }
  if (h) {
    *h = 0;
  }
  if (length == 0) {
    return 0;
  }
  TTF_Text *t = TTF_CreateText(
    layout_engine(),
    (TTF_Font *)font,
    text,
    length
  );
  if (!t) {
    return -1;
  }
  int tw = 0;
  int th = 0;
  if (t->internal->needs_layout_update && !TTF_GetTextSize(t, &tw, &th)) {
    TTF_DestroyText(t);
    return -1;
  }
  int count = 0;
  for (int i = 0; i < t->internal->num_ops; i++) {
    const TTF_DrawOperation *op = &t->internal->ops[i];
    if (op->cmd != TTF_DRAW_COMMAND_COPY ||
        op->copy.glyph_font != (TTF_Font *)font) {
      continue;
    }
    if (count < cap) {
      yguilib_sdl3_ttf_GlyphQuad *q = &out[count];
      q->glyph_index = op->copy.glyph_index;
      q->src_x = op->copy.src.x;
      q->src_y = op->copy.src.y;
      q->src_w = op->copy.src.w;
      q->src_h = op->copy.src.h;
      q->dst_x = op->copy.dst.x;
      q->dst_y = op->copy.dst.y;
      q->dst_w = op->copy.dst.w;
      q->dst_h = op->copy.dst.h;
    }
    count++;
  }
  if (w) {
    *w = t->internal->w;
  }
  if (h) {
    *h = t->internal->h;
  }
  TTF_DestroyText(t);
  return count;
}

yguilib_sdl3_ttf_Surface *yguilib_sdl3_ttf_render_glyph(
  yguilib_sdl3_ttf_Font *font,
  uint32_t glyph_index
) {
  if (!font) {
    return NULL;
  }
  SDL_Surface *surf = TTF_GetGlyphImageForIndex(
    (TTF_Font *)font,
    glyph_index,
    NULL
  );
  if (!surf) {
    return NULL;
  }
  SDL_Surface *converted = SDL_ConvertSurface(surf, SDL_PIXELFORMAT_RGBA32);
  SDL_DestroySurface(surf);
  return (yguilib_sdl3_ttf_Surface *)converted;
}
