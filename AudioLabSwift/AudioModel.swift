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
    private var WINDOW_SIZE:Int
    private var HALF_WINDOW_SIZE:Int
    private var THRESHOLD:Float

    // thse properties are for interfaceing with the API
    // the user can access these arrays at any time and plot them if they like
    var timeData:[Float]
    var fftData:[Float]
    var fftZoomedData:[Float]
    private var loudestTones:Array<Int>
    private lazy var serialQueue:DispatchQueue = {
        return DispatchQueue(label: "swiftlee.serial.queue")
    }()
    
    lazy var samplingRate:Int = {
        return Int(self.audioManager!.samplingRate)
    }()
    
    // Hz between two data points
    lazy var deltaF:Float = {
        return Float(self.audioManager!.samplingRate) / Float(BUFFER_SIZE)
    }()
    
    // MARK: Public Methods
    init(buffer_size:Int, fft_zoomed_size:Int) {
        BUFFER_SIZE = buffer_size
        THRESHOLD = 5.0
        WINDOW_SIZE = 9
        HALF_WINDOW_SIZE = Int(WINDOW_SIZE / 2)
        //DELTA_F = Float(self.audioManager!.samplingRate) / Float(BUFFER_SIZE)

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
                
                // BONUS: show the zoomed FFT
                // we can start at about 150Hz and show the next 300 points
                // actual Hz = f_0 * N/F_s
                let startIdx:Int = 150 * self.BUFFER_SIZE / self.samplingRate
                self.fftZoomedData = Array(self.fftData[startIdx...startIdx+300])
                
                // calculate two maximums by shifting the window
                var maxIdx1 = 0
                var maxIdx2 = 0
                var max1:Float = 0.0
                var max2:Float = 0.0
                var middle:Int
                for i in 0 ..< self.BUFFER_SIZE/2-self.WINDOW_SIZE{
                    middle = i + self.HALF_WINDOW_SIZE
                    if self.fftData[middle] < self.THRESHOLD || self.fftData[i..<i+self.WINDOW_SIZE].max()! != self.fftData[middle]{
                        continue
                    }
                    if self.fftData[middle] > max1{
                        max2 = max1 // move the second loudest tone to max2
                        maxIdx2 = maxIdx1
                        max1 = self.fftData[middle]
                        maxIdx1 = middle
                    }else if self.fftData[middle] > max2{
                        max2 = self.fftData[middle]
                        maxIdx2 = middle
                    }
                }
                if maxIdx1 != 0 && maxIdx2 != 0{
                    //self.loudestTones[0] = self.peakInterpolation(index: maxIdx1)
                    self.loudestTones[0] = Int(Float(maxIdx1) * self.deltaF)
                    self.loudestTones[1] = Int(Float(maxIdx2) * self.deltaF)
                }
              }
        }
    }
    
    private func peakInterpolation(index:Int) -> Int{
        let kdf = Float(samplingRate / BUFFER_SIZE)
        
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
