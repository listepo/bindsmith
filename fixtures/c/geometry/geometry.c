// Implementation of geometry.h, built into a shared library by
// `packages/bindsmith/test/emit/facade_c_test.dart` so the generated facade
// can be called for real: an arena copy or a UTF-8 conversion that is subtly
// wrong still compiles, and only a call catches it.
#include "geometry.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define GEOMETRY_CAPACITY 8

struct GeometryScene {
  geometry_id next;
  int32_t count;
  Shape shapes[GEOMETRY_CAPACITY];
  Point at[GEOMETRY_CAPACITY];
};

const int32_t geometry_max_shapes = GEOMETRY_CAPACITY;

double geometry_distance(Point a, Point b) {
  double dx = a.x - b.x;
  double dy = a.y - b.y;
  return sqrt(dx * dx + dy * dy);
}

double geometry_rect_area(const Rect *rect) {
  return rect->width * rect->height;
}

void geometry_scale(Point *point, double factor) {
  point->x *= factor;
  point->y *= factor;
}

const char *geometry_shape_name(Shape shape) {
  switch (shape) {
    case SHAPE_CIRCLE:
      return "circle";
    case SHAPE_SQUARE:
      return "square";
    case SHAPE_TRIANGLE:
      return "triangle";
  }
  return "unknown";
}

GeometryScene *geometry_scene_new(void) {
  GeometryScene *scene = calloc(1, sizeof(GeometryScene));
  if (scene != NULL) scene->next = 1;
  return scene;
}

void geometry_scene_free(GeometryScene *scene) { free(scene); }

geometry_id geometry_scene_add(GeometryScene *scene, Shape shape, Point at) {
  if (scene->count == GEOMETRY_CAPACITY) return 0;
  scene->shapes[scene->count] = shape;
  scene->at[scene->count] = at;
  scene->count++;
  return scene->next++;
}

int32_t geometry_scene_count(const GeometryScene *scene) {
  return scene->count;
}

void geometry_scene_each(const GeometryScene *scene, geometry_visitor visitor,
                         void *user_data) {
  for (int32_t i = 0; i < scene->count; i++) {
    visitor((geometry_id)(i + 1), scene->shapes[i], user_data);
  }
}

// Returns the length the format alone would print, so a caller can check that
// the string really crossed the boundary.
int geometry_log(const char *format, ...) {
  return (int)strlen(format);
}
