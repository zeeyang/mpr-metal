# `mpr-metal`
See original MPR paper by Matt Keeter: 
[Massively Parallel Rendering of Complex Closed-Form Implicit Surfaces](https://mattkeeter.com/research/mpr). 
Also see [reference implementation in CUDA ](https://github.com/mkeeter/mpr).

This is a Metal port of MPR, with following goals:
- Explore MPR implementations outside of CUDA (it's easier to port Metal -> WebGPU than from CUDA)
- Benchmark framerate and energy efficiency of MPR in macOS and iOS environments
- Experiment integrating implicit shapes into traditional rendering pipelines such as SceneKit or RealityKit.

## Deviations
It's recommended to read Keeter's MPR paper and review the CUDA reference implementation first (see above).
This sections documents deviations from the reference implementation.

- No IEEE 754 floating-point arithmetic support in interval math. This is unsupported in Metal 2.
- No tile packing. I'm not sure if gains from less threads is worth the atomic counters and round trips between CPU <-> GPU. More benchmarking is needed here. Removing tile packing simplified a number of things:
    - Tile struct is now just a tape pointer. No need to track position and next.
    - No need to unpack xy from position. Just use 2/3D thread index.
    - Tile buffer size and thread grid size can be pre-calculated. All stages of tile evaluation can be packed into a single command buffer.

## Progress
- [x] interval math
- [x] 2D tiles evaluation
- [x] 2D pixel evaluation
- [ ] 3D tiles evaluation
- [ ] 3D voxel evaluation
- [ ] RealityKit integration
