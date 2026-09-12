// bindsmith fixture: a small C API exercising every construct the C driver
// maps — structs (by value and by pointer), an opaque handle, an enum, a
// typedef, a function-pointer callback, a global, macros and a variadic
// function. Kept ANSI-C so any libclang can parse it without flags.
#ifndef GEOMETRY_H
#define GEOMETRY_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Library version as MAJOR * 100 + MINOR.
#define GEOMETRY_VERSION 102
#define GEOMETRY_PI 3.14159
#define GEOMETRY_NAME "geometry"

/// A point in the plane.
typedef struct Point {
  double x;
  double y;
} Point;

/// An axis-aligned rectangle.
typedef struct {
  Point origin;
  double width;
  double height;
} Rect;

/// Kinds of shape the library can measure.
typedef enum {
  SHAPE_CIRCLE = 0, // Measured by its radius.
  SHAPE_SQUARE = 1,
  SHAPE_TRIANGLE = 2,
} Shape;

/// Opaque scene handle; create with geometry_scene_new, free with
/// geometry_scene_free.
typedef struct GeometryScene GeometryScene;

/// Identifier of a shape inside a scene.
typedef uint32_t geometry_id;

/// Called once per shape by geometry_scene_each.
typedef void (*geometry_visitor)(geometry_id id, Shape shape, void *user_data);

/// Euclidean distance between two points.
double geometry_distance(Point a, Point b);

/// Area of the rectangle.
double geometry_rect_area(const Rect *rect);

/// Scales the point in place.
void geometry_scale(Point *point, double factor);

/// Human-readable name of the shape; the string is owned by the library.
const char *geometry_shape_name(Shape shape);

// An empty scene; free it with geometry_scene_free.
GeometryScene *geometry_scene_new(void);
void geometry_scene_free(GeometryScene *scene);
/// Adds [shape] at [at] in [scene].
/// @param scene The scene to add to.
/// @param shape The shape to add.
/// @param at Where to place it.
/// @returns The new shape id.
geometry_id geometry_scene_add(GeometryScene *scene, Shape shape, Point at);
int32_t geometry_scene_count(const GeometryScene *scene);
void geometry_scene_each(const GeometryScene *scene, geometry_visitor visitor,
                         void *user_data);

/// Formats a message; variadic functions are bound only through explicit
/// argument-type lists.
int geometry_log(const char *format, ...);

/// Number of shapes a scene can hold.
extern const int32_t geometry_max_shapes;

#ifdef __cplusplus
}
#endif

#endif
