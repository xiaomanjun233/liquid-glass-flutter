#version 460 core
#include <flutter/runtime_effect.glsl>
precision highp float;
uniform vec2 uSize;
uniform vec2 uTextureSize;
uniform float uPadding;
uniform float uDensity;
uniform sampler2D uLevel0;
uniform sampler2D uLevel1;
uniform sampler2D uLevel2;
uniform sampler2D uLevel3;
out vec4 fragColor;
void main() {
  vec2 p=FlutterFragCoord().xy;
  vec2 uv=clamp((p*uDensity+uPadding)/uTextureSize,.5/uTextureSize,1.0-.5/uTextureSize);
  float level=clamp(1.0-p.y/uSize.y,0.0,1.0)*3.0;
  if(level<1.0) fragColor=mix(texture(uLevel0,uv),texture(uLevel1,uv),level);
  else if(level<2.0) fragColor=mix(texture(uLevel1,uv),texture(uLevel2,uv),level-1.0);
  else fragColor=mix(texture(uLevel2,uv),texture(uLevel3,uv),level-2.0);
}
