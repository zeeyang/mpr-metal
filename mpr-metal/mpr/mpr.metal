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
#include <metal_stdlib>

#include "interval.h"
#include "clause.h"
#include "opcode.h"
#include "../Common.h"

#define CHOICE_ARRAY_SIZE 256
#define SLOT_SIZE 128
#define SUBTAPE_CHUNK_SIZE 64

inline void calculate_intervals_2d(thread Interval* slots,
                                   const TapeClause clause,
                                   uint2 pos,
                                   uint2 grid_size,
                                   metal::float4x4 mat,
                                   float z)
{
    const Interval ix = {(pos.x / (float)grid_size.x - 0.5f) * 2.0f,
                   ((pos.x + 1) / (float)grid_size.x - 0.5f) * 2.0f};
    const Interval iy = {(pos.y / (float)grid_size.x - 0.5f) * 2.0f,
                   ((pos.y + 1) / (float)grid_size.x - 0.5f) * 2.0f};

    Interval ix_, iy_, iw_;
    ix_ = mat[0][0] * ix +
          mat[0][1] * iy +
          mat[0][2];
    iy_ = mat[1][0] * ix +
          mat[1][1] * iy +
          mat[1][2];
    iw_ = mat[2][0] * ix +
          mat[2][1] * iy +
          mat[2][2];

    // Projection!
    ix_ = ix_ / iw_;
    iy_ = iy_ / iw_;

    // Place tile intervals using tape[0]
    slots[clause.out] = ix_;
    slots[clause.lhs] = iy_;
    slots[clause.rhs] = {z, z};
}

inline uint32_t pos2index(uint2 pos, uint2 grid)
{
    return pos.y * grid.x + pos.x;
}

kernel void debug_tiles_2d(device int32_t* in_tiles [[buffer(BufferIndexTiles)]],
                           device TapeClause* tape [[buffer(BufferIndexTape)]],
                           constant Uniforms &uniforms [[buffer(BufferIndexUniforms)]],
                           device Atomics &atomics [[buffer(BufferIndexAtomics)]],
                           metal::texture2d<uint, metal::access::write> image [[texture(TextureIndexTiles)]],
                           uint2 grid_size [[threads_per_grid]],
                           uint2 pos [[thread_position_in_grid]])
{
    uint32_t tile_index = pos2index(pos, grid_size);
    if (in_tiles[tile_index] < 0) {
        image.write(1, pos);
    }
}

kernel void clear_tiles_2d(device int32_t* in_tiles [[buffer(BufferIndexTiles)]],
                          uint2 grid_size [[threads_per_grid]],
                          uint2 pos [[thread_position_in_grid]])
{
    uint32_t tile_index = pos2index(pos, grid_size);
    in_tiles[tile_index] = 0;
}

kernel void subdivide_tiles_2d(device int32_t* in_tiles [[buffer(BufferIndexTiles)]],
                               device int32_t* out_tiles [[buffer(BufferIndexNextTiles)]],
                               constant Uniforms &uniforms [[buffer(BufferIndexUniforms)]],
                               uint2 grid_size [[threads_per_grid]],
                               uint2 pos [[thread_position_in_grid]])
{
    uint32_t out_index = pos2index(pos, grid_size);
    uint2 prev_pos = pos / 8;
    int32_t in_index = prev_pos.y * grid_size.x / 8 + prev_pos.x;
    out_tiles[out_index] = in_tiles[in_index];
}

kernel void eval_tiles_2d(device int32_t* in_tiles [[buffer(BufferIndexTiles)]],
                          device TapeClause* tape [[buffer(BufferIndexTape)]],
                          constant Uniforms &uniforms [[buffer(BufferIndexUniforms)]],
                          device Atomics &atomics [[buffer(BufferIndexAtomics)]],
                          uint2 grid_size [[threads_per_grid]],
                          uint2 pos [[thread_position_in_grid]])
{
    uint32_t tile_index = pos2index(pos, grid_size);
    if (in_tiles[tile_index] < 0) {
        // Filled tiles are maked as -1, empty tiles are -2
        return;
    }

    Interval slots[SLOT_SIZE];
    int32_t tape_cursor = in_tiles[tile_index];
    calculate_intervals_2d(slots, tape[tape_cursor], pos, grid_size, uniforms.projectionMatrix, 0);

    uint32_t choices[CHOICE_ARRAY_SIZE] = {0};
    int choice_index = 0;
    bool has_any_choice = false;

    while (1) {
        const TapeClause d = tape[++tape_cursor];
        if (!d.op) {
            break;
        }
        switch (d.op) {
            case mpr::GPU_OP_JUMP: tape_cursor += JUMP_TARGET(&d); continue;
#define lhs slots[d.lhs]
#define rhs slots[d.rhs]
#define imm d.imm
#define out slots[d.out]
            case mpr::GPU_OP_SQUARE_LHS: out = square(lhs); break;
            case mpr::GPU_OP_SQRT_LHS:   out = sqrt(lhs); break;
            case mpr::GPU_OP_NEG_LHS:    out = -lhs; break;
            case mpr::GPU_OP_SIN_LHS:    out = sin(lhs); break;
            case mpr::GPU_OP_COS_LHS:    out = cos(lhs); break;
            case mpr::GPU_OP_ASIN_LHS:   out = asin(lhs); break;
            case mpr::GPU_OP_ACOS_LHS:   out = acos(lhs); break;
            case mpr::GPU_OP_ATAN_LHS:   out = atan(lhs); break;
            case mpr::GPU_OP_EXP_LHS:    out = exp(lhs); break;
            case mpr::GPU_OP_ABS_LHS:    out = abs(lhs); break;
            case mpr::GPU_OP_LOG_LHS:    out = log(lhs); break;

            // Commutative opcodes
            case mpr::GPU_OP_ADD_LHS_IMM: out = lhs + imm; break;
            case mpr::GPU_OP_ADD_LHS_RHS: out = lhs + rhs; break;
            case mpr::GPU_OP_MUL_LHS_IMM: out = lhs * imm; break;
            case mpr::GPU_OP_MUL_LHS_RHS: out = lhs * rhs; break;

#define CHOICE(f, a, b) {                                               \
    int c = 0;                                                          \
    out = f(a, b, c);                                                   \
    if (choice_index < CHOICE_ARRAY_SIZE * 16) {                        \
        choices[choice_index / 16] |= (c << ((choice_index % 16) * 2)); \
    }                                                                   \
    choice_index++;                                                     \
    has_any_choice |= (c != 0);                                         \
    break;                                                              \
}
            case mpr::GPU_OP_MIN_LHS_IMM: CHOICE(min, lhs, imm);
            case mpr::GPU_OP_MIN_LHS_RHS: CHOICE(min, lhs, rhs);
            case mpr::GPU_OP_MAX_LHS_IMM: CHOICE(max, lhs, imm);
            case mpr::GPU_OP_MAX_LHS_RHS: CHOICE(max, lhs, rhs);

            // Non-commutative opcodes
            case mpr::GPU_OP_SUB_LHS_IMM: out = lhs - imm; break;
            case mpr::GPU_OP_SUB_IMM_RHS: out = imm - rhs; break;
            case mpr::GPU_OP_SUB_LHS_RHS: out = lhs - rhs; break;
            case mpr::GPU_OP_DIV_LHS_IMM: out = lhs / imm; break;
            case mpr::GPU_OP_DIV_IMM_RHS: out = imm / rhs; break;
            case mpr::GPU_OP_DIV_LHS_RHS: out = lhs / rhs; break;

            case mpr::GPU_OP_COPY_IMM: out = Interval(imm); break;
            case mpr::GPU_OP_COPY_LHS: out = lhs; break;
            case mpr::GPU_OP_COPY_RHS: out = rhs; break;

            default: assert(false);
        }
#undef lhs
#undef rhs
#undef imm
#undef out
    }

    // Check the result
    const TapeClause out_clause = tape[tape_cursor];

    // Empty
    if (slots[out_clause.out].lower() > 0.0f) {
        in_tiles[tile_index] = -2;
        return;
    }

    // Masked
//    if (DIMENSION == 3) {
//        const int4 pos = unpack(in_tiles[tile_index].position, tiles_per_side);
//        if (image[pos.w] > pos.z) {
//            in_tiles[tile_index].position = -1;
//            return;
//        }
//    }

    // Filled
    if (slots[out_clause.out].upper() < 0.0f) {
        in_tiles[tile_index] = -1;
        return;
    }

    if (!has_any_choice) {
        return;
    }

    ////////////////////////////////////////////////////////////////////////////
    // Tape pushing!
    // Use this array to track which slots are active
    int active[128];
    for (unsigned i=0; i < 128; ++i) {
        active[i] = false;
    }
    active[out_clause.out] = true;

    // Claim a chunk of tape
    int32_t out_index = metal::atomic_fetch_add_explicit(&atomics.tapeIndex, SUBTAPE_CHUNK_SIZE, metal::memory_order_relaxed);
    int32_t out_offset = SUBTAPE_CHUNK_SIZE;

    // If we've run out of tape, then immediately return
//    if (out_index + out_offset >= NUM_SUBTAPES * SUBTAPE_CHUNK_SIZE) {
//        return;
//    }

    // Write out the end of the tape, which is the same as the ending
    // of the previous tape (0 opcode, with i_out as the last slot)
    out_offset--;
    tape[out_index + out_offset] = out_clause;

    while (1) {
        auto d = tape[--tape_cursor];
        if (!d.op) {
            break;
        }
        if (d.op == mpr::GPU_OP_JUMP) {
            tape_cursor += JUMP_TARGET(&d);
            continue;
        }

        const bool has_choice = d.op >= mpr::GPU_OP_MIN_LHS_IMM && d.op <= mpr::GPU_OP_MAX_LHS_RHS;
        choice_index -= has_choice;

        if (!active[d.out]) {
            continue;
        }

        assert(!has_choice || choice_index >= 0);

        const int choice = (has_choice && choice_index < CHOICE_ARRAY_SIZE * 16)
            ? ((choices[choice_index / 16] >>
              ((choice_index % 16) * 2)) & 3)
            : 0;

        // If we're about to write a new piece of data to the tape,
        // (and are done with the current chunk), then we need to
        // add another link to the linked list.
        --out_offset;
        if (out_offset == 0) {
            const int32_t prev_index = out_index;

            out_index = metal::atomic_fetch_add_explicit(&atomics.tapeIndex, SUBTAPE_CHUNK_SIZE, metal::memory_order_relaxed);
            out_offset = SUBTAPE_CHUNK_SIZE;

            // Later exit if we claimed a chunk that exceeds the tape array
//            if (out_index + out_offset >= NUM_SUBTAPES * SUBTAPE_CHUNK_SIZE) {
//                return;
//            }
            --out_offset;

            // Forward-pointing link
            auto jumpClause = TapeClause{mpr::GPU_OP_JUMP};
            auto delta = (int32_t)prev_index -
                                  (int32_t)(out_index + out_offset);
            JUMP_TARGET(&jumpClause) = delta;
            tape[out_index + out_offset] = jumpClause;

            // Backward-pointing link
            auto backClause = TapeClause{mpr::GPU_OP_JUMP};
            JUMP_TARGET(&backClause) = -delta;
            tape[prev_index] = backClause;

            // We've written the jump, so adjust the offset again
            --out_offset;
        }

        active[d.out] = false;
        if (choice == 0) {
            if (d.lhs) {
                active[d.lhs] = true;
            }
            if (d.rhs) {
                active[d.rhs] = true;
            }
        } else if (choice == 1 /* LHS */) {
            // The non-immediate is always the LHS in commutative ops, and
            // min/max (the only clauses that produce a choice) are commutative
            active[d.lhs] = true;
            if (d.lhs == d.out) {
                ++out_offset;
                continue;
            } else {
                d.op = mpr::GPU_OP_COPY_LHS;
            }
        } else if (choice == 2 /* RHS */) {
            if (d.rhs) {
                active[d.rhs] = true;
                if (d.rhs == d.out) {
                    ++out_offset;
                    continue;
                } else {
                    d.op = mpr::GPU_OP_COPY_RHS;
                }
            } else {
                d.op = mpr::GPU_OP_COPY_IMM;
            }
        }
        tape[out_index + out_offset] = d;
    }

    // Write the beginning of the tape
    out_offset--;
    tape[out_index + out_offset] = tape[tape_cursor];

    // Record the beginning of the tape in the output tile
    in_tiles[tile_index] = out_index + out_offset;
}

void calculate_pixels(thread float2* slots,
                      const uint32_t in_tile,
                      const TapeClause clause,
                      metal::float4x4 mat,
                      uint2 grid_size,
                      uint2 pos)
{
    // Each tile is executed by 32 threads (one for each pair of voxels).
    //
    // This is different from the eval_tiles_i function, which evaluates one
    // tile per thread, because the tiles are already expanded by 64x by the
    // time they're stored in the in_tiles list.

    const int32_t px = pos.x;
    const int32_t py_a = pos.y / 4 * 8 + pos.y % 4;

    const float size_recip = 1.0f / grid_size.x;

    const float fx = ((px + 0.5f) * size_recip - 0.5f) * 2.0f;
    const float fy_a = ((py_a + 0.5f) * size_recip - 0.5f) * 2.0f;

    // Otherwise, calculate the X/Y/Z values
    const float fw_a = mat[2][0] * fx + mat[2][1] * fy_a + mat[2][2];
    slots[clause.out].x = (mat[0][0] * fx + mat[0][1] * fy_a + mat[0][2]) / fw_a;
    slots[clause.lhs].x = (mat[1][0] * fx + mat[1][1] * fy_a + mat[1][2]) / fw_a;
    slots[clause.rhs].x = (mat[2][0] * fx + mat[2][1] * fy_a + mat[2][2]) / fw_a;

    // Do the same calculation for the second pixel
    const int32_t py_b = py_a + 4;
    const float fy_b = ((py_b + 0.5f) * size_recip - 0.5f) * 2.0f;
    const float fw_b = mat[2][0] * fx + mat[2][1] * fy_b + mat[2][2];

    slots[clause.out].y = (mat[0][0] * fx + mat[0][1] * fy_b + mat[0][2]) / fw_b;
    slots[clause.lhs].y = (mat[1][0] * fx + mat[1][1] * fy_b + mat[1][2]) / fw_b;
    slots[clause.rhs].y = (mat[2][0] * fx + mat[2][1] * fy_b + mat[2][2]) / fw_b;

//    slots[pixel_index * 3 + 2] = float2(z, z);
}

kernel void eval_pixels(device int32_t* in_tiles [[buffer(BufferIndexTiles)]],
                        device TapeClause* tape [[buffer(BufferIndexTape)]],
                        constant Uniforms &uniforms [[buffer(BufferIndexUniforms)]],
                        metal::texture2d<uint, metal::access::write> image [[texture(TextureIndexTiles)]],
                        uint2 grid_size [[threads_per_grid]],
                        uint2 pos [[thread_position_in_grid]])
{
    // Each tile is executed by 32 threads (one for each pair of voxels, so
    // we can do all of our load/stores as float2s and make memory happier).
    //
    // This is different from the eval_tiles_i function, which evaluates one
    // tile per thread, because the tiles are already expanded by 64x by the
    // time they're stored in the in_tiles list.
    uint2 tile_pos = pos / uint2(8, 4);
    uint py_a = pos.y / 4 * 8 + pos.y % 4;
    uint py_b = py_a + 4;
    const int32_t tile_index = (tile_pos.y * grid_size.x / 8 + tile_pos.x);
    if (in_tiles[tile_index] == -1) {
        // Filled tile
        image.write(1, uint2(pos.x, py_a));
        image.write(1, uint2(pos.x, py_b));
        return;
    } else if (in_tiles[tile_index] == -2) {
        // Empty space
        return;
    }

    float2 slots[128];

    // Pick out the tape based on the pointer stored in the tiles list
    int32_t tape_cursor = in_tiles[tile_index];
    calculate_pixels(slots, in_tiles[tile_index], tape[tape_cursor], uniforms.projectionMatrix, grid_size, pos);

    while (1) {
        const TapeClause d = tape[++tape_cursor];
        if (!d.op) {
            break;
        }
        switch (d.op) {
            case mpr::GPU_OP_JUMP: tape_cursor += JUMP_TARGET(&d); continue;

#define lhs slots[d.lhs]
#define rhs slots[d.rhs]
#define imm d.imm
#define out slots[d.out]

            case mpr::GPU_OP_SQUARE_LHS: out = float2(lhs.x * lhs.x, lhs.y * lhs.y); break;
            case mpr::GPU_OP_SQRT_LHS: out = float2(metal::sqrt(lhs.x), metal::sqrt(lhs.y)); break;
            case mpr::GPU_OP_NEG_LHS: out = float2(-lhs.x, -lhs.y); break;
            case mpr::GPU_OP_SIN_LHS: out = float2(metal::sin(lhs.x), metal::sin(lhs.y)); break;
            case mpr::GPU_OP_COS_LHS: out = float2(metal::cos(lhs.x), metal::cos(lhs.y)); break;
            case mpr::GPU_OP_ASIN_LHS: out = float2(metal::asin(lhs.x), metal::asin(lhs.y)); break;
            case mpr::GPU_OP_ACOS_LHS: out = float2(metal::acos(lhs.x), metal::acos(lhs.y)); break;
            case mpr::GPU_OP_ATAN_LHS: out = float2(metal::atan(lhs.x), metal::atan(lhs.y)); break;
            case mpr::GPU_OP_EXP_LHS: out = float2(metal::exp(lhs.x), metal::exp(lhs.y)); break;
            case mpr::GPU_OP_ABS_LHS: out = float2(metal::fabs(lhs.x), metal::fabs(lhs.y)); break;
            case mpr::GPU_OP_LOG_LHS: out = float2(metal::log(lhs.x), metal::log(lhs.y)); break;

            // Commutative opcodes
            case mpr::GPU_OP_ADD_LHS_IMM: out = float2(lhs.x + imm, lhs.y + imm); break;
            case mpr::GPU_OP_ADD_LHS_RHS: out = float2(lhs.x + rhs.x, lhs.y + rhs.y); break;
            case mpr::GPU_OP_MUL_LHS_IMM: out = float2(lhs.x * imm, lhs.y * imm); break;
            case mpr::GPU_OP_MUL_LHS_RHS: out = float2(lhs.x * rhs.x, lhs.y * rhs.y); break;
            case mpr::GPU_OP_MIN_LHS_IMM: out = float2(metal::min(lhs.x, imm), metal::min(lhs.y, imm)); break;
            case mpr::GPU_OP_MIN_LHS_RHS: out = float2(metal::min(lhs.x, rhs.x), metal::min(lhs.y, rhs.y)); break;
            case mpr::GPU_OP_MAX_LHS_IMM: out = float2(metal::max(lhs.x, imm), metal::max(lhs.y, imm)); break;
            case mpr::GPU_OP_MAX_LHS_RHS: out = float2(metal::max(lhs.x, rhs.x), metal::max(lhs.y, rhs.y)); break;

            // Non-commutative opcodes
            case mpr::GPU_OP_SUB_LHS_IMM: out = float2(lhs.x - imm, lhs.y - imm); break;
            case mpr::GPU_OP_SUB_IMM_RHS: out = float2(imm - rhs.x, imm - rhs.y); break;
            case mpr::GPU_OP_SUB_LHS_RHS: out = float2(lhs.x - rhs.x, lhs.y - rhs.y); break;

            case mpr::GPU_OP_DIV_LHS_IMM: out = float2(lhs.x / imm, lhs.y / imm); break;
            case mpr::GPU_OP_DIV_IMM_RHS: out = float2(imm / rhs.x, imm / rhs.y); break;
            case mpr::GPU_OP_DIV_LHS_RHS: out = float2(lhs.x / rhs.x, lhs.y / rhs.y); break;

            case mpr::GPU_OP_COPY_IMM: out = float2(imm, imm); break;
            case mpr::GPU_OP_COPY_LHS: out = float2(lhs.x, lhs.y); break;
            case mpr::GPU_OP_COPY_RHS: out = float2(rhs.x, rhs.y); break;

#undef lhs
#undef rhs
#undef imm
#undef out
        }
    }

    // Check the result
    const TapeClause out_clause = tape[tape_cursor];
    const uint8_t i_out = out_clause.out;

    if (slots[i_out].y < 0.0f) {
        image.write(2, ushort2(pos.x, py_b));
    }
    if (slots[i_out].x < 0.0f) {
        image.write(1, ushort2(pos.x, py_a));
    }
}
