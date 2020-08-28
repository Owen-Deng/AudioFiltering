//
//  MetalGraph.swift
//  AudioLabSwift
//
//  Created by Eric Larson 
//  Copyright © 2020 Eric Larson. All rights reserved.
//

import Foundation
import UIKit
import Metal
import Accelerate

class MetalGraph {
    
    var device: MTLDevice!
    var metalLayer: CAMetalLayer!
    var pipelineState: MTLRenderPipelineState!
    var commandQueue: MTLCommandQueue!
    var timer: CADisplayLink!

    
    var vertexData: [String:[Float]] = [String: [Float]]()
    var vertexBuffer: [String:MTLBuffer] = [String:MTLBuffer]()
    var vertexColorBuffer: [String:MTLBuffer] = [String:MTLBuffer]()
    var vertexPointer: [String:UnsafeMutablePointer<Float>] = [String:UnsafeMutablePointer<Float>]()
    var vertexNormalize: [String:Bool] = [String:Bool]()
    var vertexNum: [String:Int] = [String:Int]()
    var dsFactor: [String:Int] = [String:Int]()
    
    let maxPointsPerGraph = 512 // you can increase this or decrease for different GPU speeds
    var needsRender = false
    let numShaderFloats = 4
    
    //iOS color palette with gradients
    let R = [0xFF,0xFF, 0x52,0x5A, 0xFF,0xFF, 0x1A,0x1D, 0xEF,0xC6, 0xDB,0x89, 0x87,0x0B, 0xFF,0xFF]
    let G = [0x5E,0x2A, 0xED,0xC8, 0xDB,0xCD, 0xD6,0x62, 0x4D,0x43, 0xDD,0x8C, 0xFC,0xD3, 0x95,0x5E]
    let B = [0x3A,0x68, 0xC7,0xFB, 0x4C,0x02, 0xFD,0xF0, 0xB6,0xFC, 0xDE,0x90, 0x70,0x18, 0x00,0x3A]
    
    init(mainView:UIView)
    {
        // get device
        guard let device = MTLCreateSystemDefaultDevice() else { fatalError("GPU not available") }
        self.device =  device
        
        //setup layer (in the back of the views)
        metalLayer = CAMetalLayer()
        metalLayer.device = self.device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.frame = mainView.layer.frame
        mainView.layer.insertSublayer(metalLayer, at:0)
        
        commandQueue = self.device.makeCommandQueue()
        
        timer = CADisplayLink(target: self, selector: #selector(gameloop))
        timer.add(to: RunLoop.main, forMode: .default)
        
        guard let defaultLibrary = device.makeDefaultLibrary(),
            let fragmentProgram = defaultLibrary.makeFunction(name: "passThroughFragment"),
            let vertexProgram = defaultLibrary.makeFunction(name: "passThroughVertex") else { fatalError() }
            
        let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
        pipelineStateDescriptor.vertexFunction = vertexProgram
        pipelineStateDescriptor.fragmentFunction = fragmentProgram
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineStateDescriptor.colorAttachments[0].isBlendingEnabled = false
            
        pipelineState = try! device.makeRenderPipelineState(descriptor: pipelineStateDescriptor)
    }
    
    func addGraph(withName:String,
        shouldNormalize:Bool,
        numPointsInGraph:Int){
        
        //setup graph
        let key = withName
        let numGraphs = Int(vertexData.count)
        
        dsFactor[key] = Int(numPointsInGraph/maxPointsPerGraph) // downsample factor for each graph
        if dsFactor[key]!<1 { dsFactor[key] = 1 }
        
        vertexData[key] = Array.init(repeating: 0.0, count: (numPointsInGraph/dsFactor[key]!)*numShaderFloats)
        vertexNormalize[key] = shouldNormalize
        vertexNum[key] = numGraphs
        
        // we use a 4D location, so copy over the right things
        let maxIdx = Int(vertexData[key]!.count/numShaderFloats)
        for j in 0..<maxIdx{
            // x
            vertexData[key]![numShaderFloats*j] = (Float(j)/Float(numPointsInGraph/dsFactor[key]!)-0.5)*2.0
            // transform vector (always 1)
            vertexData[key]![numShaderFloats*j+numShaderFloats-1] = 1.0
        }
        // this is a hack to get rid of connecting lines at the end of the primitives draw
        vertexData[key]![numShaderFloats-1] = 0
        vertexData[key]![maxIdx*numShaderFloats-1] = 0
        
        let dataSize = vertexData[key]!.count * MemoryLayout.size(ofValue: vertexData[key]![0])
        vertexBuffer[key] = device.makeBuffer(bytes: &(vertexData[key]!),
                                              length: dataSize, // length in bytes
                                              options: .cpuCacheModeWriteCombined)
        
        vertexPointer[key] = vertexBuffer[key]!.contents().bindMemory(to: Float.self, capacity: vertexData[key]!.count)
        // save this binding as contiguous memory
        // when we want to update the data, we can simply use this pointer adn vDSP
        
        // now make a color buffer, that we setup once and then forget about
        var vertexColorData:[Float] = Array.init(repeating: 1.0, count: (numPointsInGraph/dsFactor[key]!)*numShaderFloats)
        //setup colors
        var gradOne:Float = 0.0
        var gradTwo:Float = 0.0
        for j in 0..<maxIdx{
            // setup color gradient for each line
            gradOne = Float(j)/Float(maxIdx)
            gradTwo = 1.0-gradOne
            // B, G, R, A
            vertexColorData[j*numShaderFloats] = (Float(B[(2*numGraphs)%16])*gradOne + Float(B[(2*numGraphs+1)%16])*gradTwo)/255.0
            vertexColorData[j*numShaderFloats+1] = (Float(G[(2*numGraphs)%16])*gradOne + Float(G[(2*numGraphs+1)%16])*gradTwo)/255.0
            vertexColorData[j*numShaderFloats+2] = (Float(R[(2*numGraphs)%16])*gradOne + Float(R[(2*numGraphs+1)%16])*gradTwo)/255.0
            vertexColorData[j*numShaderFloats+3] = 0.9
        }
        vertexColorBuffer[key] = device.makeBuffer(bytes: vertexColorData, length: dataSize, options: [])
        
    }
    
    func render() {
        if needsRender == false { return } // prevent over-rendering manually
        needsRender = false
        
        guard let drawable = metalLayer?.nextDrawable() else { return }
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: 50.0/255.0,
            green: 50.0/255.0,
            blue: 50.0/255.0,
            alpha: 1.0)
        
        if let commandBuffer = commandQueue.makeCommandBuffer(){

            let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
            renderEncoder.setRenderPipelineState(pipelineState)
            // for each graph, update the values for the line
            for (key,_) in vertexBuffer{
                renderEncoder.setVertexBuffer(vertexBuffer[key], offset: 0, index: 0)
                renderEncoder.setVertexBuffer(vertexColorBuffer[key], offset:0 , index: 1)
                renderEncoder.drawPrimitives(type: .lineStrip,
                                             vertexStart: 0,
                                             vertexCount: vertexData[key]!.count)
            }
            renderEncoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }

    @objc func gameloop() {
      autoreleasepool {
        self.render()
      }
    }
    
    func updateGraph(data:[Float], forKey:String){
        
        if vertexData.keys.contains(forKey) {
            
            let numGraphs = Float(vertexData.count)
            var addToPlot = -1.0 + 2*(Float(vertexNum[forKey]!) / numGraphs) + 1.0/numGraphs
            
            var multiplier:Float = 1.0
            
            if vertexNormalize[forKey]! {
                // normalize for fft values
                addToPlot += 84.0/(64.0 * numGraphs)
                multiplier = 1.0/(64.0 * numGraphs)
            }else{
                // normalize for microphone values
                multiplier = 3.0/numGraphs
            }
            
            // multiply by \(multiplier) and add in \(addToPlot), strided by 3 and starting at element one of array
            // there is a lot to unpack here, trust me it works and is awesomely fast
            //vDSP_vsmsa(data, vDSP_Stride(dsFactor[forKey]!), &multiplier, &addToPlot, &(vertexData[forKey]![1]), vDSP_Stride(3), vDSP_Length(data.count/dsFactor[forKey]!))
            
            vDSP_vsmsa(data, vDSP_Stride(dsFactor[forKey]!), &multiplier, &addToPlot,
                       &(vertexPointer[forKey]![1]), vDSP_Stride(numShaderFloats),
                       vDSP_Length(data.count/dsFactor[forKey]!))
            
            // here is what te above code does, but using SIMD
            //for i in 0..<Int(data.count){
            //    vertexData[forKey]![numShaderFloats*i+1] = data[i]*multiplier + addToPlot
            //}

            needsRender = true // set that its okay to render now
        }
        else{
            fatalError("Key provided not in list of graphs.") // should we error here or throw a print?
        }
    }
}
