//
//  interval.h
/*
Reference implementation for
"Massively Parallel Rendering of Complex Closed-Form Implicit Surfaces"
(SIGGRAPH 2020)

This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this file,
You can obtain one at http://mozilla.org/MPL/2.0/.

Copyright (C) 2019-2020  Matt Keeter
Metal port by Zee Yang (C) 2021
*/
#pragma once
#include <simd/simd.h>

struct Interval {
    simd::float2 v;
    inline Interval() { /* YOLO */ }
    inline explicit Interval(float f) : v(simd::float2{f, f}) {}
    inline Interval(float a, float b) : v(simd::float2{a, b}) {}
    inline float upper() const { return v.y; }
    inline float lower() const { return v.x; }

    inline static Interval X(thread const Interval& x) { return x; }
    inline static Interval Y(thread const Interval& y) { return y; }
    inline static Interval Z(thread const Interval& z) { return z; }

    inline float mid() const;
    inline float rad() const;
    inline float width() const;
};

Interval operator-(thread const Interval& x);

Interval operator+(thread const Interval& x, thread const Interval&);
Interval operator+(thread const Interval& x, thread const float& y);
Interval operator+(thread const float& y, thread const Interval& x);

Interval operator*(thread const Interval& x, thread const Interval& y);
Interval operator*(thread const Interval& x, thread const float& y);
Interval operator*(thread const float& x, thread const Interval& y);

Interval operator/(thread const Interval& x, thread const Interval&);
Interval operator/(thread const Interval& x, thread const float& y);
Interval operator/(thread const float& x, thread const Interval& y);

Interval min(thread const Interval& x, thread const Interval& y, thread int& choice);
Interval min(thread const Interval& x, thread const float& y, thread int& choice);
Interval max(thread const Interval& x, thread const Interval& y, thread int& choice);
Interval max(thread const Interval& x, thread const float& y, thread int& choice);

Interval square(thread const Interval& x);
Interval abs(thread const Interval& x);
float square(thread const float& x);

Interval operator-(thread const Interval& x, thread const Interval& y);
Interval operator-(thread const Interval& x, thread const float& y);
Interval operator-(thread const float& x, thread const Interval& y);
Interval sqrt(thread const Interval& x);
Interval acos(thread const Interval& x);
Interval asin(thread const Interval& x);
Interval atan(thread const Interval& x);
Interval exp(thread const Interval& x);
Interval fmod(thread const Interval& x, thread const Interval& y);
Interval cos(thread const Interval& x);
Interval sin(thread const Interval& x);
Interval log(thread const Interval& x);
