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
    @IBOutlet weak var handLabel: UILabel! // for the small animation
    @IBOutlet weak var phoneLabel: UILabel! //for the samll animationc
    
    //setup constants
    struct AudioConstants{
        static let AUDIO_BUFFER_SIZE=1024*8//generate more data to zoom
        static let FFT_BUFFER_SIZE=AUDIO_BUFFER_SIZE/2
        static let AUDIO_FPS=20
        static let ZOOMEDFFT_POINT_COUNT=50 // for the zoomed fft graph data
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
    var counter:Int=0 // for update the gesturinglable 10FPS
    func updateGraph(){
        if let graph=self.graph{
            graph.updateGraph(data: self.audio.fftData, forKey: "fft")
          //  graph.updateGraph(data: self.audio.timeData, forKey: "time")
            
            // for the zoomed fft graph data about the peak of the fft 100point to show the zoomed area graph
            if playingSwitch.isOn{
                //get the 50 point from the 25left of tone and 25 right. for the zoomed graph
                graph.updateGraph(data: self.audio.zoomedFftdata, forKey: "zoomedfft")
            }
            if counter % 2 == 0 { // for update gesturing in 10FPS
                updateGesturingState()
            }
            counter+=1
            
        } 
    }
    
    
    
    func updateGesturingState(){
        if playingSwitch.isOn{
            gesturingLabel.isHidden=false
            switch self.audio.gesturingState{
            case.Not:  gesturingLabel.text="Not Gesturing"
            case.away:  gesturingLabel.text="Gesturing Away"
            case .toward:
                gesturingLabel.text="Gesturing Toward"
                
            }
        }
    }
    
    
    
    //
    func movingTowardHandAnimation(){
        UIView.animate(withDuration: 3, animations: {
            self.handLabel.frame.origin.x -= 100
            self.handLabel.alpha=0
        })
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
            gesturingLabel.isHidden=true
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
