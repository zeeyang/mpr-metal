#include <metal_stdlib>
#include <simd/simd.h>

#import "Common.h"

using namespace metal;

typedef struct
{
    float4 position [[position]];
    float2 uv;
} Vertex;

vertex Vertex vertexShader(constant float4* vertices [[buffer(0)]],
                           uint id [[vertex_id]])
{
    return {
      .position = vertices[id],
      .uv = (vertices[id].xy + float2(1)) / float2(2)
    };
}

fragment float4 fragmentShader(Vertex in [[stage_in]],
                               texture2d<uint> generation [[texture(0)]])
{
    constexpr sampler smplr(coord::normalized,
                            address::clamp_to_zero,
                            filter::nearest);
    uint cell = generation.sample(smplr, in.uv).r;
    return float4(cell);
}
