// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Kyant
// Copyright 2026 xiaomanjun233 and contributors
// 基于 Kyant Backdrop 2.0.0 改编；Flutter 修改与来源见 NOTICE、docs/SOURCES.md。
// Kyant Backdrop 2.0.0 optics, Apache-2.0. GLSL adaptation; see NOTICE.
#include <flutter/runtime_effect.glsl>
uniform vec2 uTextureSize;
uniform vec2 uSize;
uniform vec4 uCorners;
uniform vec3 uLocalToTexture0;
uniform vec3 uLocalToTexture1;
uniform vec3 uTextureToLocal0;
uniform vec3 uTextureToLocal1;
uniform vec2 uSourceSize;
uniform vec4 uLens;
uniform float uFilterInput;
uniform sampler2D uContent;
out vec4 fragColor;
vec2 unit(vec2 v) { float d=length(v); return d>.0001?v/d:vec2(0); }
float radiusAt(vec2 p) {
  return min(p.x>=0.0?(p.y<=0.0?uCorners.y:uCorners.z)
    :(p.y<=0.0?uCorners.x:uCorners.w),min(uSize.x,uSize.y)*.5);
}
float sdRect(vec2 p,float r) {
  vec2 q=abs(p)-uSize*.5+r;
  return length(max(q,0.0))-r+min(max(q.x,q.y),0.0);
}
vec2 gradRect(vec2 p,float r) {
  vec2 q=abs(p)-uSize*.5+r;
  if(q.x>=0.0||q.y>=0.0) return sign(p)*unit(max(q,0.0));
  float x=step(q.y,q.x); return sign(p)*vec2(x,1.0-x);
}
vec4 sampleLocal(vec2 p) {
  vec3 h=vec3(p,1);
  vec2 texel=vec2(dot(uLocalToTexture0,h),dot(uLocalToTexture1,h));
  vec2 extent=uFilterInput>.5?uTextureSize:uSourceSize;
  vec2 uv=texel/extent;
  #if defined(IMPELLER_TARGET_OPENGLES) && !defined(IMPELLER_OPENGLES_UNFLIPPED_DEPRECATED)
  if(uFilterInput>.5) uv.y=1.0-uv.y;
  #endif
  vec2 inset=.5/extent;
  return texture(uContent,clamp(uv,inset,1.0-inset));
}
void main() {
  vec2 p=FlutterFragCoord().xy;
  if(uFilterInput>.5) {
    vec3 h=vec3(p,1);
    p=vec2(dot(uTextureToLocal0,h),dot(uTextureToLocal1,h));
  }
  vec2 centered=p-uSize*.5;
  float radius=radiusAt(centered);
  float sd=sdRect(centered,radius);
  if(uLens.x<=0.0||uLens.y<=0.0||-sd>=uLens.x) {
    fragColor=sampleLocal(p); return;
  }
  float x=clamp(1.0+min(sd,0.0)/uLens.x,0.0,1.0);
  float d=-(1.0-sqrt(max(0.0,1.0-x*x)))*uLens.y;
  vec2 direction=unit(gradRect(centered,min(radius*1.5,min(uSize.x,uSize.y)*.5))
    +uLens.w*unit(centered));
  vec2 refracted=p+d*direction;
  if(uLens.z==0.0) { fragColor=sampleLocal(refracted); return; }
  vec2 shift=d*direction*uLens.z*centered.x*centered.y/max(uSize.x*uSize.y*.25,.0001);
  vec4 red=sampleLocal(refracted+shift);
  vec4 orange=sampleLocal(refracted+shift*(2.0/3.0));
  vec4 yellow=sampleLocal(refracted+shift*(1.0/3.0));
  vec4 green=sampleLocal(refracted);
  vec4 cyan=sampleLocal(refracted-shift*(1.0/3.0));
  vec4 blue=sampleLocal(refracted-shift*(2.0/3.0));
  vec4 purple=sampleLocal(refracted-shift);
  fragColor=vec4((red.r+orange.r+yellow.r)/3.5+purple.r/7.0,
    orange.g/7.0+(yellow.g+green.g+cyan.g)/3.5,
    (cyan.b+blue.b+purple.b)/3.0,
    (red.a+orange.a+yellow.a+green.a+cyan.a+blue.a+purple.a)/7.0);
}
