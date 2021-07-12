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

namespace mpr {

enum Opcode {
    GPU_OP_INVALID = 0,
    GPU_OP_JUMP, // meta-op to jump to a new point in the tape

    GPU_OP_SQUARE_LHS,  // 2
    GPU_OP_SQRT_LHS,    // 3
    GPU_OP_NEG_LHS,     // 4
    GPU_OP_SIN_LHS,     // 5
    GPU_OP_COS_LHS,     // 6
    GPU_OP_ASIN_LHS,    // 7
    GPU_OP_ACOS_LHS,    // 8
    GPU_OP_ATAN_LHS,    // 9
    GPU_OP_EXP_LHS,     // 10
    GPU_OP_ABS_LHS,     // 11
    GPU_OP_LOG_LHS,     // 12

    // Commutative opcodes
    GPU_OP_ADD_LHS_IMM, // 13
    GPU_OP_ADD_LHS_RHS, // 14
    GPU_OP_MUL_LHS_IMM, // 15
    GPU_OP_MUL_LHS_RHS, // 16
    GPU_OP_MIN_LHS_IMM, // 17
    GPU_OP_MIN_LHS_RHS, // 18
    GPU_OP_MAX_LHS_IMM, // 19
    GPU_OP_MAX_LHS_RHS, // 20

    // Non-commutative opcodes
    GPU_OP_SUB_LHS_IMM, // 21
    GPU_OP_SUB_IMM_RHS, // 22
    GPU_OP_SUB_LHS_RHS, // 23
    GPU_OP_DIV_LHS_IMM, // 24
    GPU_OP_DIV_IMM_RHS, // 25
    GPU_OP_DIV_LHS_RHS, // 26

    // Copy-only opcodes (used after pushing)
    GPU_OP_COPY_IMM,    // 27
    GPU_OP_COPY_LHS,    // 28
    GPU_OP_COPY_RHS,    // 29
};
}
