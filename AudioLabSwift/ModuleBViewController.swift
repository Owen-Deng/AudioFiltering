//
//  ModuleBViewController.swift
//  AudioLabSwift
//
//  Created by RongWei Ji on 9/28/23.
//  Copyright © 2023 Eric Larson. All rights reserved.
//

import UIKit

class ModuleBViewController: UIViewController {

    //setup UI, constants, AudioModel
    @IBOutlet weak var graphUIView: UIView!
    @IBOutlet weak var playingLabel: UILabel!
    @IBOutlet weak var playingSwitch: UISwitch!
    @IBOutlet weak var playingHzSlider: UISlider!
    @IBOutlet weak var gesturingLabel: UILabel!
    
    //setup constants
    struct AudioConstants{
        static let AUDIO_BUFFER_SIZE=1024*8//generate more data to zoom
        static let FFT_BUFFER_SIZE=AUDIO_BUFFER_SIZE/2
        static let AUDIO_FPS=20
        static let ZOOMEDFFT_POINT_COUNT=50 // for the zoomed fft graph data
        static let DOPPLER_PEAK_WINDOWS_LENGH=5
    }
    
  
    var audio=AudioModel.sharedInstance
    
    
    
    //Setup the graph
    lazy var graph:MetalGraph?={
        return MetalGraph(userView: self.graphUIView)
    }()
    
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        //add graph in the UIView
        //graph time: read the micphone
        //graph fft: fft in dB
        if let graph=self.graph{
            graph.setBackgroundColor(r: 0, g: 0, b: 0, a: 1)
            graph.addGraph(withName: "fft",shouldNormalizeForFFT: true, numPointsInGraph: AudioConstants.FFT_BUFFER_SIZE)
          //  graph.addGraph(withName: "time", numPointsInGraph: AudioConstants.AUDIO_BUFFER_SIZE)
            graph.addGraph(withName: "zoomedfft", shouldNormalizeForFFT: true, numPointsInGraph: AudioConstants.ZOOMEDFFT_POINT_COUNT)
            graph.makeGrids()
        }
        
        audio.startMicrophoneProcessing(withFps: Double(AudioConstants.AUDIO_FPS))
        audio.play()
        Timer.scheduledTimer(withTimeInterval: 1.0/Double(AudioConstants.AUDIO_FPS), repeats: true){_ in self.updateGraph()}
        setDefaultUI() // stat the vc and set ui in default
    }
    
    
    // set the default state of several views
    func setDefaultUI(){
        playingLabel.text="not Playing"
        playingSwitch.isOn=false
        playingHzSlider.value=0
        gesturingLabel.isHidden=true
    }
    
    
    // setup the updataGraph func to update the uiview
    func updateGraph(){
        if let graph=self.graph{
            graph.updateGraph(data: self.audio.fftData, forKey: "fft")
          //  graph.updateGraph(data: self.audio.timeData, forKey: "time")
            
            // for the zoomed fft graph data about the peak of the fft 100point to show the zoomed area graph
            if playingSwitch.isOn{
                //get the 50 point from the 50left of tone and 50 right of. if start is less than 0 , from 0
            
               // findDopplerPeak(array: &subFftArray)
                graph.updateGraph(data: self.audio.zoomedFftdata, forKey: "zoomedfft")
                
            }
            
        } 
    }
    
    
    func findDopplerPeak(array:inout[Float]){
        var startIndex:Int=0
        var endIndex:Int=startIndex+AudioConstants.DOPPLER_PEAK_WINDOWS_LENGH-1
        while endIndex<array.count{
            
            var maxV:Float=0.0
            var maxIndex:Int=0;
            var subArray=Array(array[startIndex...endIndex])
            vDSP_maxvi(&subArray, 1, &maxV, &maxIndex, vDSP_Length(AudioConstants.DOPPLER_PEAK_WINDOWS_LENGH))
            if (startIndex + Int(maxIndex))==(startIndex+endIndex)/2{
                print("central max :\(startIndex + Int(maxIndex)) and the Value is \(maxV)")
            }
            startIndex=startIndex+1
            endIndex=startIndex+AudioConstants.DOPPLER_PEAK_WINDOWS_LENGH-1
        }
        
    }
    
    
    
    // switch to play the sound of slider value hz
    @IBAction func switchPlay(_ sender: Any) {
        if playingSwitch.isOn{
            audio.startProcessingSineWaveForPlayback(withFreq: playingHzSlider.value)
            audio.play()
            playingLabel.text="Playing\(playingHzSlider.value)Hz"
        }else{
            audio.stopProcessingSinwave()
            playingLabel.text="not Playing"
        }
        
    }
    
    
    @IBAction func changeFrequency(_ sender: UISlider) {
        if playingSwitch.isOn{
            self.audio.toneSineFrequncy=Float(Double(sender.value))
            playingLabel.text="Playing\(sender.value)Hz"
        }else{
            
        }
    }
    
    
    
    

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}
