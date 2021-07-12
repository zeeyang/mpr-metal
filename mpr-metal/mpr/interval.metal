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
#include "interval.h"
#include <metal_stdlib>

inline float Interval::mid() const {
    return lower() / 2.0f + upper() / 2.0f;
}

inline float Interval::rad() const {
    const float m = mid();
    return metal::max(m - lower(), upper() - m);
}

inline float Interval::width() const {
    return upper() - lower();
}

////////////////////////////////////////////////////////////////////////////////

Interval operator-(thread const Interval& x) {
    return {-x.upper(), -x.lower()};
}

////////////////////////////////////////////////////////////////////////////////

Interval operator+(thread const Interval& x, thread const Interval& y) {
    return {x.lower() + y.lower(), x.upper() + y.upper()};
}

Interval operator+(thread const Interval& x, thread const float& y) {
    return {x.lower() + y, x.upper() + y};
}

Interval operator+(thread const float& y, thread const Interval& x) {
    return x + y;
}

//////////////////////////////////////////////////////////////////////////////

Interval operator*(thread const Interval& x, thread const Interval& y) {
    if (x.lower() < 0.0f) {
        if (x.upper() > 0.0f) {
            if (y.lower() < 0.0f) {
                if (y.upper() > 0.0f) { // M * M
                    return { metal::min(x.lower() * y.upper(), x.upper() * y.lower()),
                        metal::max(x.lower() * y.lower(), x.upper() * y.upper()) };
                } else { // M * N
                    return { x.upper() * y.lower(), x.lower() * y.lower() };
                }
            } else {
                if (y.upper() > 0.0f) { // M * P
                    return { x.lower() * y.upper(), x.upper() * y.upper() };
                } else { // M * Z
                    return {0.0f, 0.0f};
                }
            }
        } else {
            if (y.lower() < 0.0f) {
                if (y.upper() > 0.0f) { // N * M
                    return { x.lower() * y.upper(), x.lower() * y.lower() };
                } else { // N * N
                    return { x.upper() * y.upper(), x.lower() * y.lower() };
                }
            } else {
                if (y.upper() > 0.0f) { // N * P
                    return { x.lower() * y.upper(), x.upper() * y.lower() };
                } else { // N * Z
                    return { 0.0f, 0.0f };
                }
            }
        }
    } else {
        if (x.upper() > 0.0f) {
            if (y.lower() < 0.0f) {
                if (y.upper() > 0.0f) { // P * M
                    return { x.upper() * y.lower(), x.upper() * y.upper()};
                } else {// P * N
                    return { x.upper() * y.lower(), x.lower() * y.upper()};
                }
            } else {
                if (y.upper() > 0.0f) { // P * P
                    return { x.lower() * y.lower(), x.upper() * y.upper()};
                } else {// P * Z
                    return { 0.0f, 0.0f };
                }
            }
        } else { // Z * ?
            return {0.0f, 0.0f};
        }
    }
}

Interval operator*(thread const Interval& x, thread const float& y) {
    if (y < 0.0f) {
        return {x.upper() * y, x.lower() * y};
    } else {
        return {x.lower() * y, x.upper() * y};
    }
}

Interval operator*(thread const float& x, thread const Interval& y) {
    return y * x;
}

////////////////////////////////////////////////////////////////////////////////

Interval operator/(thread const Interval& x, thread const Interval& y) {
    if (y.lower() <= 0.0f && y.upper() >= 0.0f) {
        return {-INFINITY, INFINITY};
    } else if (x.upper() < 0.0f) {
        if (y.upper() < 0.0f) {
            return {x.upper() / y.lower(), x.lower() / y.upper()};
        } else {
            return {x.lower() / y.lower(), x.upper() / y.upper()};
        }
    } else if (x.lower() < 0.0f) {
        if (y.upper() < 0.0f) {
            return {x.upper() / y.upper(), x.lower() / y.upper()};
        } else {
            return {x.lower() / y.lower(), x.upper() / y.lower()};
        }
    } else {
        if (y.upper() < 0.0f) {
            return {x.upper() / y.upper(), x.lower() / y.lower()};
        } else {
            return {x.lower() / y.upper(), x.upper() / y.lower()};
        }
    }
}

Interval operator/(thread const Interval& x, thread const float& y) {
    if (y < 0.0f) {
        return {x.upper() / y, x.lower() / y};
    } else if (y > 0.0f) {
        return {x.lower() / y, x.upper() / y};
    } else {
        return {-INFINITY, INFINITY};
    }
}

Interval operator/(thread const float& x, thread const Interval& y) {
    return Interval(x) / y;
}

////////////////////////////////////////////////////////////////////////////////

Interval min(thread const Interval& x, thread const Interval& y, thread int& choice) {
    if (x.upper() < y.lower()) {
        choice = 1;
        return x;
    } else if (y.upper() < x.lower()) {
        choice = 2;
        return y;
    }
    return {metal::min(x.lower(), y.lower()), metal::min(x.upper(), y.upper())};
}

Interval min(thread const Interval& x, thread const float& y, thread int& choice) {
    if (x.upper() < y) {
        choice = 1;
        return x;
    } else if (y < x.lower()) {
        choice = 2;
        return Interval(y);
    }
    return {metal::min(x.lower(), y), metal::min(x.upper(), y)};
}

////////////////////////////////////////////////////////////////////////////////

Interval max(thread const Interval& x, thread const Interval& y, thread int& choice) {
    if (x.lower() > y.upper()) {
        choice = 1;
        return x;
    } else if (y.lower() > x.upper()) {
        choice = 2;
        return y;
    }
    return {metal::max(x.lower(), y.lower()), metal::max(x.upper(), y.upper())};
}

Interval max(thread const Interval& x, thread const float& y, thread int& choice) {
    if (x.lower() > y) {
        choice = 1;
        return x;
    } else if (y > x.upper()) {
        choice = 2;
        return Interval(y);
    }
    return {metal::max(x.lower(), y), metal::max(x.upper(), y)};
}

//////////////////////////////////////////////////////////////////////////////

Interval square(thread const Interval& x) {
    if (x.upper() < 0.0f) {
        return {x.upper() * x.upper(), x.lower() * x.lower()};
    } else if (x.lower() > 0.0f) {
        return {x.lower() * x.lower(), x.upper() * x.upper()};
    } else if (-x.lower() > x.upper()) {
        return {0.0f, x.lower() * x.lower()};
    } else {
        return {0.0f, x.upper() * x.upper()};
    }
}

Interval abs(thread const Interval& x) {
    if (x.lower() >= 0.0f) {
        return x;
    } else if (x.upper() < 0.0f) {
        return -x;
    } else {
        return {0.0f, metal::max(-x.lower(), x.upper())};
    }
}

float square(thread const float& x) {
    return x * x;
}

//////////////////////////////////////////////////////////////////////////////

Interval operator-(thread const Interval& x, thread const Interval& y) {
    return { x.lower() - y.upper(), x.upper() - y.lower() };
}

Interval operator-(thread const Interval& x, thread const float& y) {
    return { x.lower() - y, x.upper() - y };
}

Interval operator-(thread const float& x, thread const Interval& y) {
    return { x - y.upper(), x - y.lower() };
}

Interval sqrt(thread const Interval& x) {
    if (x.upper() < 0.0f) {
        return { NAN, NAN };
    } else if (x.lower() <= 0.0f) {
        return { 0.0f, metal::sqrt(x.upper()) };
    } else {
        return { metal::sqrt(x.lower()), metal::sqrt(x.upper()) };
    }
}

Interval acos(thread const Interval& x) {
    if (x.upper() < -1.0f || x.lower() > 1.0f) {
        return { NAN, NAN };
    } else {
        return { metal::acos(x.upper()), metal:: acos(x.lower()) };
    }
}

Interval asin(thread const Interval& x) {
    if (x.upper() < -1.0f || x.lower() > 1.0f) {
        return {NAN, NAN};
    } else {
        return { metal::asin(x.lower()), metal::asin(x.upper()) };
    }
}

Interval atan(thread const Interval& x) {
    return { metal::atan(x.lower()), metal::atan(x.upper()) };
}

Interval exp(thread const Interval& x) {
    return { metal::exp(x.lower()), metal::exp(x.upper()) };
}

Interval fmod(thread const Interval& x, thread const Interval& y) {
    // Caveats from the Boost Interval library also apply here:
    //  This is only useful for clamping trig functions
    const float yb = x.lower() < 0.0f ? y.lower() : y.upper();
    const float n = metal::floor(x.lower() / yb);
    return x - n * y;
}

static constant float pi_f_l = 13176794.0f/(1<<22);
static constant float pi_f_u = 13176795.0f/(1<<22);
Interval cos(thread const Interval& x) {

    const Interval pi{pi_f_l, pi_f_u};
    const Interval pi2 = pi * 2.0f;

    return Interval{-1.0f, 1.0f};

    Interval tmp = fmod(x, pi2);

    // We are covering a full period!
    if (tmp.width() >= pi2.lower()) {
        return Interval{-1.0f, 1.0f};
    }

    if (tmp.lower() >= pi.upper()) {
        return -cos(tmp - pi);
    }

    // Use double precision, since there aren't _ru / _rd primitives
    const float l = tmp.lower();
    const float u = tmp.lower();
    if (u <= pi.lower()) {
        return { metal::cos(u), metal::cos(l) };
    } else if (u <= pi2.lower()) {
        float m = metal::min(pi2.lower() - u, l);
        return { -1.0f, metal::cos(m) };
    } else {
        return {-1.0f, 1.0f};
    }
}

Interval sin(thread const Interval& x) {
    return cos(x - Interval{ M_PI_F, M_PI_F } / 2.0f);
}

Interval log(thread const Interval& x) {
    if (x.upper() < 0.0f) {
        return { NAN, NAN };
    } else if (x.lower() <= 0.0f) {
        return { 0.0f, metal::log(x.upper()) };
    } else {
        return { metal::log(x.lower()), metal::log(x.upper()) };
    }
}
