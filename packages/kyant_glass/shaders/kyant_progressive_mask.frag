#include <flutter/runtime_effect.glsl>
uniform vec2 uTextureSize;
uniform vec3 uTextureToLocalY;
uniform vec2 uRamp;
uniform sampler2D uContent;
out vec4 fragColor;
void main() {
  vec2 p=FlutterFragCoord().xy;
  float y=dot(uTextureToLocalY,vec3(p,1.0));
  float t=clamp((y-uRamp.x)/max(.0001,uRamp.y-uRamp.x),0.0,1.0);
  float alpha=1.0-t*t*(3.0-2.0*t);
  vec2 uv=p/uTextureSize;
  #if defined(IMPELLER_TARGET_OPENGLES) && !defined(IMPELLER_OPENGLES_UNFLIPPED_DEPRECATED)
  uv.y=1.0-uv.y;
  #endif
  fragColor=texture(uContent,clamp(uv,.5/uTextureSize,1.0-.5/uTextureSize))*alpha;
}
