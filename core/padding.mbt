// The map's padding as MapLibre GL JS 6.16.0's `EdgeInsets` (src/geo/edge_insets.ts) and the camera state's
// center point (src/geo/camera_state.ts), BSD-3-Clause, Copyright (c) 2020 MapLibre contributors; see NOTICE.

///|
/// Space kept free along the viewport's edges, in CSS pixels: around a box
/// fitted to the screen, or the map's own (`Transform::with_padding`).
#derive(Debug, Eq)
pub(all) struct Padding {
  top : Double
  right : Double
  bottom : Double
  left : Double
}

///|
pub fn Padding::uniform(p : Double) -> Padding {
  { top: p, right: p, bottom: p, left: p, }
}

///|
/// No padding on any side.
pub fn Padding::none() -> Padding {
  Padding::uniform(0.0)
}

///|
/// Whether every side is a finite number of pixels, 0 or more (what MapLibre's
/// `EdgeInsets` takes).
pub fn Padding::valid(self : Padding) -> Bool {
  let ok = (v : Double) => v >= 0.0 && !v.is_inf()
  ok(self.top) && ok(self.right) && ok(self.bottom) && ok(self.left)
}

///|
/// The padding `k` (0 to 1) of the way from `self` to `to`, as MapLibre's
/// `EdgeInsets.interpolate`.
pub fn Padding::toward(self : Padding, to : Padding, k : Double) -> Padding {
  let mix = (a : Double, b : Double) => a + k * (b - a)
  {
    top: mix(self.top, to.top),
    right: mix(self.right, to.right),
    bottom: mix(self.bottom, to.bottom),
    left: mix(self.left, to.left),
  }
}

///|
/// The screen point a `width` x `height` viewport draws its center at: the
/// middle of what the padding leaves, kept on screen (MapLibre's
/// `EdgeInsets.getCenter`).
pub fn Padding::center(
  self : Padding,
  width : Double,
  height : Double,
) -> (Double, Double) {
  let clamp = (v : Double, max : Double) => {
    @cmp.maximum(0.0, @cmp.minimum(max, v))
  }
  (
    clamp((self.left + width - self.right) / 2.0, width),
    clamp((self.top + height - self.bottom) / 2.0, height),
  )
}

///|
/// `Padding::center` from the middle of the viewport (MapLibre's `centerOffset`).
fn center_offset(
  width : Double,
  height : Double,
  padding : Padding,
) -> (Double, Double) {
  let (x, y) = padding.center(width, height)
  (x - width / 2.0, y - height / 2.0)
}

///|
/// MapLibre's projection matrix for a `width` x `height` viewport under
/// `padding`: the perspective's principal point moved to the padded center, so
/// the vanishing point follows it.
pub fn Padding::perspective(
  self : Padding,
  width : Double,
  height : Double,
  near : Double,
  far : Double,
) -> Mat4 {
  let offset = center_offset(width, height, self)
  let p = Mat4::perspective(FIELD_OF_VIEW, width / height, near, far)
  p.m[8] = -offset.0 * 2.0 / width
  p.m[9] = offset.1 * 2.0 / height
  p
}

///|
/// The fit padding and the map padding MapLibre's `cameraForBounds` fits with:
/// `padding` on top of the map's `own`, or with `absolute` in its place.
pub fn fit_paddings(
  own : Padding,
  padding : Padding,
  absolute : Bool,
) -> (Padding, Padding) {
  if absolute {
    (Padding::none(), padding)
  } else {
    (padding, own)
  }
}
