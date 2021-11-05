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
    private var vertexData: [String:[Float32]] = [String: [Float32]]()
    private var vertexBuffer: [String:MTLBuffer] = [String:MTLBuffer]()
    private var vertexColorBuffer: [String:MTLBuffer] = [String:MTLBuffer]()
    private var vertexPointer: [String:UnsafeMutablePointer<Float32>] = [String:UnsafeMutablePointer<Float32>]()
    private var vertexNum: [String:Int] = [String:Int]()
    private var vertexShowGrid: [String:Bool] = [String:Bool]()
    private var dsFactor: [String:Int] = [String:Int]()
    private var vertexGain: [String:Float32] = [String:Float32]()
    private var vertexBias: [String:Float32] = [String:Float32]()
    private var boxBuffer:[String:MTLBuffer] = [String:MTLBuffer]()
    private var boxColorBuffer:[String:MTLBuffer] = [String:MTLBuffer]()
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
        metalLayer.contentsScale = 2.0
        metalLayer.frame = userView.bounds
        
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
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = metalLayer.pixelFormat
        pipelineStateDescriptor.colorAttachments[0].isBlendingEnabled = false
            
        pipelineState = try! device.makeRenderPipelineState(descriptor: pipelineStateDescriptor)
        
    }
    

    private var gridLength:Int = 0
    private func createGraphGrid(name:String,min:Float,max:Float){
        let mid = (max-min)/2.0+min
        let box:[Float32] = [-0.99, min,  0.0, 0.0, // primitve draw protect
                           -0.99, min,  0.0, 1.0,
                           -0.99, max, 0.0, 1.0,
                            0.99, max, 0.0, 1.0,
                            0.99, min, 0.0, 1.0,
                           -0.99, min, 0.0, 1.0, // outer box
                           -0.75, min,  0.0, 1.0,
                           -0.75, max, 0.0, 1.0,
                            0.75, max, 0.0, 1.0,
                            0.75, min, 0.0, 1.0,
                           -0.75, min, 0.0, 1.0, // outer quartile box
                           -0.25, min,  0.0, 1.0,
                           -0.25, max, 0.0, 1.0,
                            0.25, max, 0.0, 1.0,
                            0.25, min, 0.0, 1.0,
                           -0.25, min, 0.0, 1.0, // inner quartile box
                           -0.5,  min,  0.0, 1.0,
                           -0.5,  max, 0.0, 1.0,
                            0.5,  max, 0.0, 1.0,
                            0.5,  min, 0.0, 1.0,
                           -0.5,  min, 0.0, 1.0, // mid quartile box
                            0.0,  min, 0.0, 1.0,
                            0.0,  max, 0.0, 1.0, // mid line
                           -0.99, max,  0.0, 1.0, // center line
                           -0.99, mid,  0.0, 1.0,
                            0.99, mid,  0.0, 1.0,
                            0.99, mid,  0.0, 0.0 // primitve draw protect
        ]
        
        let boxColor:[Float32] = [Float32].init(repeating: 0.5, count:box.count)
        gridLength = box.count
        
        var dataSize = box.count * MemoryLayout.size(ofValue: box[0])
        boxBuffer[name] = device.makeBuffer(bytes: box,
                                    length: dataSize,
                                    options: []) //cpuCacheModeWriteCombined
        
        dataSize = boxColor.count * MemoryLayout.size(ofValue: boxColor[0])
        boxColorBuffer[name] = device.makeBuffer(bytes: boxColor,
                                    length: dataSize,
                                    options: [])
        
        
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
            for (key,_) in boxBuffer{
                renderEncoder.setVertexBuffer(boxBuffer[key], offset: 0, index: 0)
                renderEncoder.setVertexBuffer(boxColorBuffer[key], offset: 0, index: 1)
                renderEncoder.drawPrimitives(type: .lineStrip,
                                             vertexStart: 0,
                                             vertexCount: gridLength-2)
            }
            
            
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
        
        self.addGraph(withName: withName,
                      withGain: withGain,
                      withBias: withBias,
                      numPointsInGraph: numPointsInGraph,
                      showGrid: true
        )
    }
    
    func addGraph(withName:String,
                  withGain:Float,
                  withBias:Float,
                  numPointsInGraph:Int,
                  showGrid:Bool){
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
        var vertexColorData:[Float32] = Array.init(repeating: 1.0, count: (numPointsInGraph/dsFactor[key]!)*GraphConstants.numShaderFloats)

        
        let b:Float32 = Float32(B[(2*numGraphs)%16])/255.0
        let g:Float32 = Float32(G[(2*numGraphs)%16])/255.0
        let r:Float32 = Float32(R[(2*numGraphs)%16])/255.0
        let a:Float32 = Float32(0.9)
        for j in 0..<maxIdx{

            // B, G, R, A
            vertexColorData[j*GraphConstants.numShaderFloats] = b
            vertexColorData[j*GraphConstants.numShaderFloats+1] = g
            vertexColorData[j*GraphConstants.numShaderFloats+2] = r
            vertexColorData[j*GraphConstants.numShaderFloats+3] = a
            // hack to get the added colors from showing up
            if j <= 1 || j >= maxIdx-2{
                vertexColorData[j*GraphConstants.numShaderFloats] = 0.0
                vertexColorData[j*GraphConstants.numShaderFloats+1] = 0.0
                vertexColorData[j*GraphConstants.numShaderFloats+2] = 0.0
                vertexColorData[j*GraphConstants.numShaderFloats+3] = 0.0
            }
        }
        vertexColorBuffer[key] = device.makeBuffer(bytes: vertexColorData, length: dataSize, options: [])
        
        // now save if we should have a grid for this graph
        vertexShowGrid[key] = showGrid

    }
    
    func makeGrids(){
        for (forKey,_) in vertexBuffer{
            if vertexShowGrid[forKey]!{
                let numGraphs = Float(vertexData.count)
                let addToPlot = -1.0 + 2*(Float(vertexNum[forKey]!) / numGraphs) + 1.0/numGraphs
                // get to midpoint of plot on screen
                let minVal:Float = addToPlot - (0.9 / numGraphs)
                let maxVal:Float = addToPlot + (0.9 / numGraphs)
                createGraphGrid(name:forKey, min: minVal, max: maxVal)
            }
        }
    }
    
    func updateGraph(data:[Float], forKey:String){
        
        if vertexData.keys.contains(forKey) {
            
            let numGraphs = Float(vertexData.count)
            var addToPlot = -1.0 + 2*(Float(vertexNum[forKey]!) / numGraphs) + 1.0/numGraphs
            
            var multiplier:Float = 1.0
            
            // get to midpoint of plot on screen
            var minVal:Float = addToPlot - (0.89 / numGraphs)
            var maxVal:Float = addToPlot + (0.89 / numGraphs)
            
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
