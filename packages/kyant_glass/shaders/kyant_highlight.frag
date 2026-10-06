// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Kyant
// Copyright 2026 xiaomanjun233 and contributors
// 基于 Kyant Backdrop 2.0.0 改编；Flutter 修改与来源见 NOTICE、docs/SOURCES.md。
// Kyant Backdrop 2.0.0 Default/Ambient highlight, Apache-2.0.
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uCorners;
uniform vec4 uColor;
uniform float uAngle;
uniform float uFalloff;
uniform float uMode;
uniform float uFloor;
out vec4 fragColor;
void main() {
  if(uMode<.5) { fragColor=uColor; return; }
  vec2 p=FlutterFragCoord().xy-uSize*.5;
  float r=p.x>=0.0?(p.y<=0.0?uCorners.y:uCorners.z):(p.y<=0.0?uCorners.x:uCorners.w);
  r=min(r*1.5,min(uSize.x,uSize.y)*.5);
  vec2 q=abs(p)-uSize*.5+r;
  vec2 n;
  if(q.x>=0.0||q.y>=0.0) {
    vec2 v=max(q,0.0); n=sign(p)*v/max(length(v),.0001);
  } else { float x=step(q.y,q.x); n=sign(p)*vec2(x,1.0-x); }
  float d=dot(n,vec2(cos(uAngle),sin(uAngle)));
  float intensity=uFloor+(1.0-uFloor)*pow(abs(d),max(uFalloff,.001));
  float a=uColor.a*intensity;
  fragColor=uMode>1.5?vec4(vec3(step(0.0,d)*a),a):uColor*intensity;
}
