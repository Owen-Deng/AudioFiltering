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
    struct AudioConstants{
        static let AUDIO_BUFFER_SIZE=1024*4
        static let FFT_BUFFER_SIZE=AUDIO_BUFFER_SIZE/2
        static let AUDIO_FPS=20
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
            graph.addGraph(withName: "time", numPointsInGraph: AudioConstants.AUDIO_BUFFER_SIZE)
            graph.makeGrids()
        }
        
        audio.startMicrophoneProcessing(withFps: Double(AudioConstants.AUDIO_FPS))
        audio.play()
        Timer.scheduledTimer(withTimeInterval: 1.0/Double(AudioConstants.AUDIO_FPS), repeats: true){_ in self.updateGraph()}
    }
    
    
    
    // setup the updataGraph func to update the uiview
    func updateGraph(){
        if let graph=self.graph{
            graph.updateGraph(data: self.audio.fftData, forKey: "fft")
            
            graph.updateGraph(data: self.audio.timeData, forKey: "time")
            
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
