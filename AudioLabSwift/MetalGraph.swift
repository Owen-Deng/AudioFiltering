//
//  MetalGraph.swift
//  AudioLabSwift
//
//  Created by Eric Larson
//  Copyright © 2020 Eric Larson. All rights reserved.
//


//TODO:
// 0. make private things
// 1. Limit values hi/lo to fit in view
// 2. grid in the graph
// 3. values for grid?


import Foundation
import UIKit
import Metal
import Accelerate

class MetalGraph {
    
    //MARK: MTL Properties
    private var device: MTLDevice!
    private var metalLayer: CAMetalLayer!
    private var pipelineState: MTLRenderPipelineState!
    private var commandQueue: MTLCommandQueue!
    private var timer: CADisplayLink!
    
    private var backgroundColor = MTLClearColor(
        red: 50.0/255.0,
        green: 50.0/255.0,
        blue: 50.0/255.0,
        alpha: 1.0)

    //MARK: Dictionary Properties for saving state/data from user
    private var vertexData: [String:[Float]] = [String: [Float]]()
    private var vertexBuffer: [String:MTLBuffer] = [String:MTLBuffer]()
    private var vertexColorBuffer: [String:MTLBuffer] = [String:MTLBuffer]()
    private var vertexPointer: [String:UnsafeMutablePointer<Float>] = [String:UnsafeMutablePointer<Float>]()
    private var vertexNum: [String:Int] = [String:Int]()
    private var dsFactor: [String:Int] = [String:Int]()
    private var vertexGain: [String:Float] = [String:Float]()
    private var vertexBias: [String:Float] = [String:Float]()
    private var needsRender = false
    
    //MARK: iOS color palette with gradients
    private let R = [0xFF,0xFF, 0x52,0x5A, 0xFF,0xFF, 0x1A,0x1D, 0xEF,0xC6, 0xDB,0x89, 0x87,0x0B, 0xFF,0xFF]
    private let G = [0x5E,0x2A, 0xED,0xC8, 0xDB,0xCD, 0xD6,0x62, 0x4D,0x43, 0xDD,0x8C, 0xFC,0xD3, 0x95,0x5E]
    private let B = [0x3A,0x68, 0xC7,0xFB, 0x4C,0x02, 0xFD,0xF0, 0xB6,0xFC, 0xDE,0x90, 0x70,0x18, 0x00,0x3A]

    
    //MARK: Constants
    private struct GraphConstants{
        static let fftNormalizer:Float = 64.0
        static let fftAddition:Float = 40.0
        static let maxPointsPerGraph = 512 // you can increase this or decrease for different GPU speeds
        static let numShaderFloats = 4
    }
    
    //MARK: Initialization and Rendering Functions
    // Initialize the class, setup where this view will be drawing to
    init(userView:UIView)
    {
        // get device
        guard let device = MTLCreateSystemDefaultDevice() else { fatalError("GPU not available") }
        self.device =  device
        
        //setup layer (in the back of the views)
        metalLayer = CAMetalLayer()
        metalLayer.device = self.device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.frame = userView.bounds
        metalLayer.contentsScale = 2.0
        userView.layer.insertSublayer(metalLayer, at:0)
    
        commandQueue = self.device.makeCommandQueue()
        
        // setup a repeating render function
        timer = CADisplayLink(target: self, selector: #selector(gameloop))
        timer.add(to: RunLoop.main, forMode: .default)
        
        // add in shaders to the program
        guard let defaultLibrary = device.makeDefaultLibrary(),
            let fragmentProgram = defaultLibrary.makeFunction(name: "passThroughFragment"),
            let vertexProgram = defaultLibrary.makeFunction(name: "passThroughVertex") else { fatalError("Could not find Shaders.metal file.") }
            
        let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
        pipelineStateDescriptor.vertexFunction = vertexProgram
        pipelineStateDescriptor.fragmentFunction = fragmentProgram
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineStateDescriptor.colorAttachments[0].isBlendingEnabled = false
            
        pipelineState = try! device.makeRenderPipelineState(descriptor: pipelineStateDescriptor)
        
        //createBox()
    }
    
    private var boxBuffer:MTLBuffer? = nil
    private var boxColorBuffer:MTLBuffer? = nil
    
    private func createBox(){
        let box:[Float] = [-0.75, 0.0,  0.0, 1.0,
                           -0.75, 0.25, 0.0, 1.0,
                            0.75, 0.25, 0.0, 1.0,
                            0.75, 0.0, 0.0, 1.0,
                           -0.75, 0.0, 0.0, 1.0]
        
        let boxColor:[Float] = Array.init(repeating: 0.5, count:box.count)
        
        var dataSize = box.count * MemoryLayout.size(ofValue: box[0])
        boxBuffer = device.makeBuffer(bytes: box,
                                    length: dataSize,
                                    options: .cpuCacheModeWriteCombined)
        
        dataSize = boxColor.count * MemoryLayout.size(ofValue: boxColor[0])
        boxColorBuffer = device.makeBuffer(bytes: boxColor,
                                    length: dataSize,
                                    options: .cpuCacheModeWriteCombined)
        
        
    }
    
    private func render() {
        if needsRender == false { return } // prevent over-rendering manually
        needsRender = false
        
        guard let drawable = metalLayer?.nextDrawable() else { return }
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        // this sets the background color
        renderPassDescriptor.colorAttachments[0].clearColor = self.backgroundColor
        
        
        
        if let commandBuffer = commandQueue.makeCommandBuffer(){

            let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
            renderEncoder.setRenderPipelineState(pipelineState)
            
           
            // show graph boxes
//            renderEncoder.setVertexBuffer(boxBuffer, offset: 0, index: 0)
//            renderEncoder.setVertexBuffer(boxColorBuffer, offset: 0, index: 1)
//            renderEncoder.drawPrimitives(type: .lineStrip,
//                                         vertexStart: 0,
//                                         vertexCount: 20)
            
            
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

    @objc private func gameloop() {
      autoreleasepool {
        self.render()
      }
    }
    
    
    //MARK: Public Access Functions
    func setBackgroundColor(r:Double,g:Double,b:Double,a:Double){
        self.backgroundColor = MTLClearColor(red: r, green: g, blue: b, alpha: a)
    }
    
    func addGraph(withName:String,
                  numPointsInGraph:Int){
        // no normalization needed
        self.addGraph(withName: withName,
                      withGain: 1.0,
                      withBias: 0.0,
                      numPointsInGraph: numPointsInGraph)
    }
    
    
    func addGraph(withName:String,
        shouldNormalizeForFFT:Bool,
        numPointsInGraph:Int){
        // custom FFT normalization option
        if shouldNormalizeForFFT{
            // use built in normalization for the fft
            self.addGraph(withName: withName,
                          withGain: GraphConstants.fftNormalizer,
                          withBias: GraphConstants.fftAddition,
                          numPointsInGraph: numPointsInGraph)
        }else{
            self.addGraph(withName: withName,
                          withGain: 1.0,
                          withBias: 0.0,
                          numPointsInGraph: numPointsInGraph)
        }
    }
    
    func addGraph(withName:String,
                  withGain:Float,
                  withBias:Float,
                  numPointsInGraph:Int){
        //setup graph
        let key = withName
        let numGraphs = Int(vertexData.count)
        
        dsFactor[key] = Int(numPointsInGraph/GraphConstants.maxPointsPerGraph) // downsample factor for each graph
        if dsFactor[key]!<1 { dsFactor[key] = 1 }
        
        //init the graph and normalization
        vertexData[key] = Array.init(repeating: 0.0, count: (numPointsInGraph/dsFactor[key]!)*GraphConstants.numShaderFloats)
        vertexNum[key] = numGraphs
        // custom setup from user
        vertexGain[key] = withGain
        vertexBias[key] = withBias
        
        
        // we use a 4D location, so copy over the right things
        let maxIdx = Int(vertexData[key]!.count/GraphConstants.numShaderFloats)
        for j in 0..<maxIdx{
            // x
            vertexData[key]![GraphConstants.numShaderFloats*j] = (Float(j)/Float(numPointsInGraph/dsFactor[key]!)-0.5)*1.95
            // transform vector (always 1)
            vertexData[key]![GraphConstants.numShaderFloats*j+GraphConstants.numShaderFloats-1] = 1.0
        }
        // this is a hack to get rid of connecting lines at the end of the primitives draw
        vertexData[key]![GraphConstants.numShaderFloats-1] = 0
        vertexData[key]![maxIdx*GraphConstants.numShaderFloats-1] = 0
        
        let dataSize = vertexData[key]!.count * MemoryLayout.size(ofValue: vertexData[key]![0])
        vertexBuffer[key] = device.makeBuffer(bytes: &(vertexData[key]!),
                                              length: dataSize, // length in bytes
                                              options: .cpuCacheModeWriteCombined)
        
        vertexPointer[key] = vertexBuffer[key]!.contents().bindMemory(to: Float.self, capacity: vertexData[key]!.count)
        // save this binding as contiguous memory
        // when we want to update the data, we can simply use this pointer and vDSP
        
        // now make a color buffer, that we setup once and then forget about
        var vertexColorData:[Float] = Array.init(repeating: 1.0, count: (numPointsInGraph/dsFactor[key]!)*GraphConstants.numShaderFloats)
        //setup colors in a gradient within one spectra of color pallette
        var gradOne:Float = 0.0
        var gradTwo:Float = 0.0
        for j in 0..<maxIdx{
            // setup color gradient for each line
            gradOne = Float(j)/Float(maxIdx)
            gradTwo = 1.0-gradOne
            // B, G, R, A
            vertexColorData[j*GraphConstants.numShaderFloats] = (Float(B[(2*numGraphs)%16])*gradOne + Float(B[(2*numGraphs+1)%16])*gradTwo)/255.0
            vertexColorData[j*GraphConstants.numShaderFloats+1] = (Float(G[(2*numGraphs)%16])*gradOne + Float(G[(2*numGraphs+1)%16])*gradTwo)/255.0
            vertexColorData[j*GraphConstants.numShaderFloats+2] = (Float(R[(2*numGraphs)%16])*gradOne + Float(R[(2*numGraphs+1)%16])*gradTwo)/255.0
            vertexColorData[j*GraphConstants.numShaderFloats+3] = 0.9
        }
        vertexColorBuffer[key] = device.makeBuffer(bytes: vertexColorData, length: dataSize, options: [])
    }
    
    func updateGraph(data:[Float], forKey:String){
        
        if vertexData.keys.contains(forKey) {
            
            let numGraphs = Float(vertexData.count)
            var addToPlot = -1.0 + 2*(Float(vertexNum[forKey]!) / numGraphs) + 1.0/numGraphs
            
            var multiplier:Float = 1.0
            
            // get to midpoint of plot on screen
            var minVal:Float = addToPlot - (0.99 / numGraphs)
            var maxVal:Float = addToPlot + (0.99 / numGraphs)
            
            // now add custom normalizations
            addToPlot += vertexBias[forKey]!/(vertexGain[forKey]! * numGraphs)
            multiplier = 1.0/(vertexGain[forKey]! * numGraphs)
            

            
            // multiply by \(multiplier) and add in \(addToPlot), strided by dsFactor and starting at element one of array
            // there is a lot to unpack here, trust me it works and is awesomely fast
            
            // vector:scalar-multiply:scalar-addition
            vDSP_vsmsa(data, // go through this data
                       vDSP_Stride(dsFactor[forKey]!), // down sample input
                       &multiplier, &addToPlot, // scalars to mult and add
                       &(vertexPointer[forKey]![1]),// save to this data (keep zeroth element the same so line do not connect)
                       vDSP_Stride(GraphConstants.numShaderFloats), // skip through 4D location
                       vDSP_Length(data.count/dsFactor[forKey]!)) // do this many adds
            
            // here is what te above code does, but using SIMD
            //for i in 0..<Int(data.count){
            //    vertexData[forKey]![numShaderFloats*i+1] = data[i]*multiplier + addToPlot
            //}
            
            // Now clip data so that its not too large
            
            let maxIdx = Int(vertexData[forKey]!.count/GraphConstants.numShaderFloats)
            vDSP_vclip(&(vertexPointer[forKey]![1]),
                       vDSP_Stride(GraphConstants.numShaderFloats),
                       &minVal, &maxVal,
                       &(vertexPointer[forKey]![1]),
                       vDSP_Stride(GraphConstants.numShaderFloats),
                       vDSP_Length(maxIdx) )

            needsRender = true // set that its okay to render now
        }
        else{
            fatalError("Key provided not in list of graphs.")
        }
    }
}
