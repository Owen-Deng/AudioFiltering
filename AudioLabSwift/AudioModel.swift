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
    private var BUFFER_SIZE:Int=1024*8//init this for sharedInstance, make more data for zoom
    private var ZOOMED_FFT_SUBARRAY_COUNT=50 // for the zoomed graph subarray from the fftdata this is the count for dopple
    private var ZOOMED_FFT_WINDOW_LENGTH=5// this is this the windows??
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
    var zoomedFftdata:[Float] //this is array for the zoomedata
    var playingFrequency:Float=0.0  // this for playing frequency
    //==============================
    
    // MARK: Public Methods
    // rewrite hte AudioModel for sharedInstant
    init() {
        // anything not lazily instatntiated should be allocated here
        timeData = Array.init(repeating: 0.0, count: BUFFER_SIZE)
        fftData = Array.init(repeating: 0.0, count: BUFFER_SIZE/2)
        toneSineFrequncy=0 // for the default
        zoomedFftdata=Array.init(repeating: 0.0, count: ZOOMED_FFT_SUBARRAY_COUNT)
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
            
            // MARK: For the sub array only 50 points to zoom the fftdata when playing certain frequncey
            if let manager=self.audioManager{
                var startIndex:Int =  (Int(playingFrequency)*BUFFER_SIZE/Int(manager.samplingRate)-(ZOOMED_FFT_SUBARRAY_COUNT/2))
                // sampleingRate 48khz ,fftdata.count 2048 , timebuffersize 4096. if slider 18k , the graph is from 0-24khz ,and the points is total 2048. the index should be 1536 . the subarray index 1536-1636,every points cross 11hz.
                //now make the buffersize double 4096*2 and fft is 4096 ,now the points div is 5hz,so can make more clear for the graph
                if startIndex<0{
                    startIndex =  0//the left of the fftbuffer range
                }else if startIndex>(BUFFER_SIZE/2-ZOOMED_FFT_SUBARRAY_COUNT){
                    startIndex = (BUFFER_SIZE/2-ZOOMED_FFT_SUBARRAY_COUNT)//the right bound of the fftbuffer range
                }
                
                zoomedFftdata=Array(self.fftData[startIndex...startIndex+ZOOMED_FFT_SUBARRAY_COUNT-1])
                
            }
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
    func startProcessingSineWaveForPlayback(withFreq:Float){
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
