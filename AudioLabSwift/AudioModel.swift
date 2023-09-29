//
//  AudioModel.swift
//  AudioLabSwift
//
//  Created by Eric Larson 
//  Copyright © 2020 Eric Larson. All rights reserved.
//

import Foundation
import Accelerate

class AudioModel {
    
    // MARK: Properties
    private var BUFFER_SIZE:Int=1024*4//init this for sharedInstance
    // thse properties are for interfaceing with the API
    // the user can access these arrays at any time and plot them if they like
    var timeData:[Float]
    var fftData:[Float]
    
    static var sharedInstance=AudioModel()//add this for sharedInstance
    
    //==============================
    // MARK: Properties for the ModuleB
    var toneSineFrequncy:Float = 0.0{
        didSet{
            if let manager=self.audioManager{
                phaseIncrement=Float(2*Double.pi*Double(toneSineFrequncy)/manager.samplingRate  )
            }
        }
    }
    private var phase:Float=0.0
    private var phaseIncrement:Float=0.0
    private var sineWaveRepeatMax:Float=Float(2*Double.pi)
    lazy var  samplingRate :Int={
        return Int(self.audioManager!.samplingRate)
    }()
    //==============================
    
    // MARK: Public Methods
    // rewrite hte AudioModel for sharedInstant
    init() {
        // anything not lazily instatntiated should be allocated here
        timeData = Array.init(repeating: 0.0, count: BUFFER_SIZE)
        fftData = Array.init(repeating: 0.0, count: BUFFER_SIZE/2)
        toneSineFrequncy=0 // for the default
    }
    
    // public function for starting processing of microphone data
    func startMicrophoneProcessing(withFps:Double){
        // setup the microphone to copy to circualr buffer
        if let manager = self.audioManager{
            manager.inputBlock = self.handleMicrophone
            
            // repeat this fps times per second using the timer class
            //   every time this is called, we update the arrays "timeData" and "fftData"
            Timer.scheduledTimer(withTimeInterval: 1.0/withFps, repeats: true) { _ in
                self.runEveryInterval()
            }
            
        }
    }
    
    
    // You must call this when you want the audio to start being handled by our model
    func play(){
        if let manager = self.audioManager{
            manager.play()
        }
    }
    
    
    //==========================================
    // MARK: Private Properties
    private lazy var audioManager:Novocaine? = {
        return Novocaine.audioManager()
    }()
    
    private lazy var fftHelper:FFTHelper? = {
        return FFTHelper.init(fftSize: Int32(BUFFER_SIZE))
    }()
    
    
    private lazy var inputBuffer:CircularBuffer? = {
        return CircularBuffer.init(numChannels: Int64(self.audioManager!.numInputChannels),
                                   andBufferSize: Int64(BUFFER_SIZE))
    }()
    
    
    //==========================================
    // MARK: Private Methods
    // NONE for this model
    
    //==========================================
    // MARK: Model Callback Methods
    private func runEveryInterval(){
        if inputBuffer != nil {
            // copy time data to swift array
            self.inputBuffer!.fetchFreshData(&timeData,
                                             withNumSamples: Int64(BUFFER_SIZE))
            
            // now take FFT
            fftHelper!.performForwardFFT(withData: &timeData,
                                         andCopydBMagnitudeToBuffer: &fftData)
            
            // at this point, we have saved the data to the arrays:
            //   timeData: the raw audio samples
            //   fftData:  the FFT of those same samples
            // the user can now use these variables however they like
            
        }
    }
    
    //==========================================
    // MARK: Audiocard Callbacks
    // in obj-C it was (^InputBlock)(float *data, UInt32 numFrames, UInt32 numChannels)
    // and in swift this translates to:
    private func handleMicrophone (data:Optional<UnsafeMutablePointer<Float>>, numFrames:UInt32, numChannels: UInt32) {
        // copy samples from the microphone into circular buffer
        self.inputBuffer?.addNewFloatData(data, withNumSamples: Int64(numFrames))
    }
    
    
    //========================================
    // MARK: funcs for ModuleB
    //func start to processing sinewave
    func startProcessingSineWaveForPlayback(withFreq:Float=330.0){
        toneSineFrequncy=withFreq
        if let manager=self.audioManager{
            manager.outputBlock=self.handleSpeakerQueryWithSinuSound
        }
    }
    
    func stopProcessingSinwave(){
        if let manager=self.audioManager{
            manager.outputBlock=nil
        }
    }
    
    private func handleSpeakerQueryWithSinuSound(data:Optional<UnsafeMutablePointer<Float>>,numFrams:UInt32,numChannels:UInt32){
        if let arrayData=data{
            var i=0
            let chan=Int(numChannels)
            let frame=Int(numFrams)
            if chan==1{
                while i<frame{
                    arrayData[i]=sin(phase)
                   // arrayData[i+1]=arrayData[i]
                    phase += phaseIncrement
                    if (phase>=sineWaveRepeatMax){phase-=sineWaveRepeatMax}
                    i+=1
                }
            }else if chan==2{
                let len=frame*chan
                while i<len{
                    arrayData[i]=sin(phase)
                    arrayData[i+1]=arrayData[i]
                    phase += phaseIncrement
                    if (phase>=sineWaveRepeatMax){phase-=sineWaveRepeatMax}
                    i+=2
                }
            }
            
            
        }
        
    }
    
    
    
}
