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
#include <cstdint>
#include "opcode.h"

namespace mpr {

const char* gpu_op_str(uint8_t op);

}   // namespace mpr
