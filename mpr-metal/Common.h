#ifndef ShaderTypes_h
#define ShaderTypes_h

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#define ATOMIC_INT metal::atomic_int
#else
#import <Foundation/Foundation.h>
#import "mpr.h"
#define ATOMIC_INT int32_t
#endif

#include <simd/simd.h>

typedef NS_ENUM(int32_t, BufferIndex)
{
    BufferIndexTape         = 0,
    BufferIndexTiles        = 1,
    BufferIndexNextTiles    = 2,
    BufferIndexUniforms     = 3,
    BufferIndexAtomics      = 4
};

typedef NS_ENUM(int32_t, VertexAttribute)
{
    VertexAttributePosition = 0,
};

typedef NS_ENUM(int32_t, TextureIndex)
{
    TextureIndexTiles = 0,
};

typedef struct
{
    matrix_float4x4 projectionMatrix;
} Uniforms;

typedef struct
{
    ATOMIC_INT tapeIndex;
} Atomics;

#endif

