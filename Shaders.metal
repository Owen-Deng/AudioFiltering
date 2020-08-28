//
//  Shaders.metal
//  AudioLabSwift
//
//  Created by Eric Larson 
//  Copyright © 2020 Eric Larson. All rights reserved.
//
// started with shader code from the following very helpful repository:
//   https://github.com/RedQueenCoder/Metal-Learning-Projects/blob/master/2DDrawing/Star/Star/GameViewController.swift

#include <metal_stdlib>
using namespace metal;




struct VertexInOut
{
    float4  position [[position]];
    float4  color;
};

vertex VertexInOut passThroughVertex(uint vid [[ vertex_id ]],
                                     constant packed_float4* position  [[ buffer(0) ]],
                                     constant packed_float4* color    [[ buffer(1) ]])
{
    VertexInOut outVertex;
    
    outVertex.position = position[vid];
    outVertex.color    = color[vid];
    
    return outVertex;
};

fragment half4 passThroughFragment(VertexInOut inFrag [[stage_in]])
{
    return half4(inFrag.color);
};
