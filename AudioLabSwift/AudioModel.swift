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
    private var ZOOMED_FFT_SUBARRAY_COUNT=50 // it's count of the zoomed fft for dopple frequncy
    private var ZOOMED_FFT_WINDOW_LENGTH=5// the window in the zoom to check the max
    private var DIF_PEAKS=0.5 // Threshold check the second peak and the max peak. if the second is 0.5xMax can know it's a peak from several peaks
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
    var gesturingState = gesturingStateEnum.Not
    enum gesturingStateEnum{
        case Not
        case toward
        case away
    }
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
            if  toneSineFrequncy>0, let manager=self.audioManager{
                if manager.outputBlock != nil{
                    var startIndex:Int =  (Int(toneSineFrequncy)*BUFFER_SIZE/Int(manager.samplingRate)-(ZOOMED_FFT_SUBARRAY_COUNT/2))
                    // sampleingRate 48khz ,fftdata.count 2048 , timebuffersize 4096. if slider 18k , the graph is from 0-24khz ,and the points is total 2048. the index should be 1536 . the subarray index 1536-1636,every points cross 11hz.
                    //now make the buffersize double 4096*2 and fft is 4096 ,now the points div is 5hz,so can make more clear for the graph
                    if startIndex<0{
                        startIndex =  0//the left of the fftbuffer range
                    }else if startIndex>(BUFFER_SIZE/2-ZOOMED_FFT_SUBARRAY_COUNT){
                        startIndex = (BUFFER_SIZE/2-ZOOMED_FFT_SUBARRAY_COUNT)//the right bound of the fftbuffer range
                    }
                    zoomedFftdata=Array(self.fftData[startIndex...startIndex+ZOOMED_FFT_SUBARRAY_COUNT-1])
                    print(toneSineFrequncy)
                    print(zoomedFftdata)
                    findDopplerPeak(array: &zoomedFftdata)
                }
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
    
    // a stop func for stoping the sound
    func stopProcessingSinwave(){
        if let manager=self.audioManager{
            manager.outputBlock=nil
        }
    }
    
    // handle the speaker to make sine wave
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
    
    
    // this is one way for check the windows max of the zoomed array of playing
    func findDopplerPeak(array:inout[Float]){
        // use the window to get several peaks
        var startIndex:Int=0
        var endIndex:Int=startIndex+ZOOMED_FFT_WINDOW_LENGTH-1
        var windowsPeaksArray:[Float]=[]
        while endIndex<array.count{
            var maxV:Float=0.0
            var maxIndex:Int=0;
            var subArray=Array(array[startIndex...endIndex])
            vDSP_maxvi(&subArray, 1, &maxV, &maxIndex, vDSP_Length(ZOOMED_FFT_WINDOW_LENGTH))
            if (startIndex + Int(maxIndex))==(startIndex+endIndex)/2{
                print("central max :\(startIndex + Int(maxIndex)) and the Value is \(maxV)")
                windowsPeaksArray.append(maxV) //create the new peaks array to find which gesturing
            }
            startIndex=startIndex+1
            endIndex=startIndex+ZOOMED_FFT_WINDOW_LENGTH-1
        }
        //caculate the dif between the peaks and find out energy enough for detectin
        if let maxValue=windowsPeaksArray.max(){
            if maxValue==windowsPeaksArray[windowsPeaksArray.count/2-1]{ // make the peak in zoomed more stable
                let dif=maxValue-windowsPeaksArray[0] //this is normal difference between the max peak and other points
                var peak:Int=0// set the recieved peak position 0 means no such peak.1 means left of refenrece,2means right
                for (index , value) in windowsPeaksArray.enumerated(){// find the second peak
                    if Double((maxValue-value)/dif) > DIF_PEAKS || (maxValue-value)==0{
                        // no gesturing the dif is too big . nothing hapen. or energy is too small
                        //peak=0
                    }else{
                        // the energy is big enough to know something refection hapende and dopple is hapenning
                        if index>=windowsPeaksArray.count/2{
                            peak=2
                        }else{
                            peak=1
                        }
                    }
                }
                //if get the peak than set the status
                switch peak {
                case 0:self.gesturingState=gesturingStateEnum.Not
                case 1:self.gesturingState=gesturingStateEnum.away
                case 2:self.gesturingState=gesturingStateEnum.toward
                default:
                    self.gesturingState=gesturingStateEnum.Not
                }
            }
        }
    }
    
    
    
    
    
}
