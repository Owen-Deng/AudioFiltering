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
    private var BUFFER_SIZE:Int
    // thse properties are for interfaceing with the API
    // the user can access these arrays at any time and plot them if they like
    var timeData:[Float]
    var fftData:[Float]
    var fftZoomedData:[Float]
    var loudestTones:Array<Int>
    lazy var serialQueue:DispatchQueue = {
        return DispatchQueue(label: "swiftlee.serial.queue")
    }()
    
    lazy var samplingRate:Int = {
        return Int(self.audioManager!.samplingRate)
    }()
    
    // MARK: Public Methods
    init(buffer_size:Int, fft_zoomed_size:Int) {
        BUFFER_SIZE = buffer_size
        //BUFFER_SIZE = Int(Novocaine.audioManager().samplingRate / 3)
        print("Sampling Rate: \(BUFFER_SIZE)")
        // anything not lazily instatntiated should be allocated here
        timeData = Array.init(repeating: 0.0, count: BUFFER_SIZE)
        fftData = Array.init(repeating: 0.0, count: BUFFER_SIZE/2)
        fftZoomedData = Array.init(repeating: 0.0, count: fft_zoomed_size)
        loudestTones = Array.init(repeating: 0, count: 2)
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
    
    func stop(){
        if let manager = self.audioManager{
            manager.pause()
            manager.inputBlock = nil
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
            serialQueue.async {
                // copy time data to swift array
                self.inputBuffer!.fetchFreshData(&self.timeData, // copied into this array
                                                 withNumSamples: Int64(self.BUFFER_SIZE))
                
                // now take FFT
                self.fftHelper!.performForwardFFT(withData: &self.timeData,
                                                  andCopydBMagnitudeToBuffer: &self.fftData) // fft result is copied into fftData array
                
                // at this point, we have saved the data to the arrays:
                //   timeData: the raw audio samples
                //   fftData:  the FFT of those same samples
                // the user can now use these variables however they like
                // BONUS: show the zoomed FFT
                // we can start at about 150Hz and show the next 300 points
                // actual Hz = f_0 * N/F_s
                let startIdx:Int = 150 * self.BUFFER_SIZE / self.samplingRate
                self.fftZoomedData = Array(self.fftData[startIdx...startIdx+300])
                
                //self.findMaxUsingDilation()
                
                // calculate maximums by shifting the window
                let window_size = 9
                let threshold:Float = 5
                var maxIdx1 = 0
                var maxIdx2 = 0
                var max1:Float = 0.0
                var max2:Float = 0.0
                for i in 0 ..< self.BUFFER_SIZE/2-window_size{
                    let mid = Int(window_size/2)
                    if self.fftData[i+mid] < threshold || self.fftData[i..<i+window_size].max()! != self.fftData[i+mid]{
                        continue
                    }
                    if self.fftData[i+mid] > max1{
                        max2 = max1
                        maxIdx2 = maxIdx1
                        max1 = self.fftData[i+mid]
                        maxIdx1 = i+mid
                    }else if self.fftData[i+mid] > max2{
                        max2 = self.fftData[i+mid]
                        maxIdx2 = i+mid
                    }
                }
                if maxIdx1 != 0 && maxIdx2 != 0{
                    //self.loudestTones[0] = self.peakInterpolation(index: maxIdx1)
                    self.loudestTones[0] = maxIdx1 * self.samplingRate / self.BUFFER_SIZE
                    self.loudestTones[1] = maxIdx2 * self.samplingRate / self.BUFFER_SIZE
                }
              }
            
        }
    }
    
    private func peakInterpolation(index:Int) -> Int{
        let kdf = Float(samplingRate / (BUFFER_SIZE))
        
        let f2:Float = Float(Float(index)*kdf)
        let m3:Float = self.fftData[index+1]
        let m2:Float = self.fftData[index]
        let m1:Float = self.fftData[index-1]
        //let peak = Int(f2 + (m1-m3)/(m3-2*m2+m1)*(kdf/2))
        let peak = Int(f2 + ((m3 - m1)/(2*m2 - m1 - m3))*(kdf/2))
        return peak
        
    }

    //==========================================
    // MARK: Audiocard Callbacks
    // in obj-C it was (^InputBlock)(float *data, UInt32 numFrames, UInt32 numChannels)
    // and in swift this translates to:
    private func handleMicrophone (data:Optional<UnsafeMutablePointer<Float>>, numFrames:UInt32, numChannels: UInt32) {
        // copy samples from the microphone into circular buffer
        self.inputBuffer?.addNewFloatData(data, withNumSamples: Int64(numFrames))
    }
    
    func getTwoLoudestTones() -> Array<Int>{
        return self.loudestTones
    }
    
    
}
