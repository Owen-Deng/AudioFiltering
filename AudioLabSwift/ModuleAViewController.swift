//
//  ViewController.swift
//  AudioLabSwift
//
//  Created by Eric Larson 
//  Copyright © 2020 Eric Larson. All rights reserved.
// Team name：Trio
// Team members：Chuanqi Deng, Rognwei Ji, Yunfeng Huang

import UIKit
import Metal


class ModuleAViewController: UIViewController {

    @IBOutlet weak var loudestLabel: UILabel!
    @IBOutlet weak var userView: UIView!
    struct AudioConstants{
        static let AUDIO_BUFFER_SIZE = 8192
        static let FFT_ZOOMED_SIZE = 300
    }
    
    // setup audio model
    let audio = FrequencyRecognitionModel(buffer_size: AudioConstants.AUDIO_BUFFER_SIZE, fft_zoomed_size: AudioConstants.FFT_ZOOMED_SIZE)
    lazy var graph:MetalGraph? = {
        print("FrameSize: \(self.userView.frame)")
        return MetalGraph(userView: self.userView)
    }()
        
    
    private func setGraph(){
        if let graph = self.graph{
            graph.setBackgroundColor(r: 0, g: 0, b: 0, a: 1)
            
            // add in graphs for display
            // note that we need to normalize the scale of this graph
            // because the fft is returned in dB which has very large negative values and some large positive values
            
            // BONUS: lets also display a version of the FFT that is zoomed in
            graph.addGraph(withName: "fftZoomed",
                           shouldNormalizeForFFT: true,
                           numPointsInGraph: AudioConstants.FFT_ZOOMED_SIZE) // 300 points to display
            
            
            graph.addGraph(withName: "fft",
                           shouldNormalizeForFFT: true,
                           numPointsInGraph: AudioConstants.AUDIO_BUFFER_SIZE/2)
            
            graph.addGraph(withName: "time",
                           numPointsInGraph: AudioConstants.AUDIO_BUFFER_SIZE)
            
            
            
            graph.makeGrids() // add grids to graph
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setGraph()
        // start up the audio model here, querying microphone
        audio.startMicrophoneProcessing(withFps: 20) // preferred number of FFT calculations per second

        audio.play()
        
        // run the loop for updating the graph peridocially
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            self.updateGraph()
        }
    }
    
    // periodically, update the graph with refreshed FFT Data
    func updateGraph(){
        
        if let graph = self.graph{
            graph.updateGraph(
                data: self.audio.fftData,
                forKey: "fft"
            )
            
            graph.updateGraph(
                data: self.audio.timeData,
                forKey: "time"
            )
            
            graph.updateGraph(
                data: self.audio.fftZoomedData,
                forKey: "fftZoomed"
            )
            // update graph size to support landscape mode
            self.graph!.updateGraphSize()
        }
        
        // display two loudest tones and their musical notes(if possible)
        let twoLoudestTones = audio.getTwoLoudestTones()
        if twoLoudestTones.count == 2{
            loudestLabel.text = "First loudest tone: \(twoLoudestTones[0]) \(audio.determineNote(Hz: twoLoudestTones[0]))\nSecond loudest tone: \(twoLoudestTones[1]) \(audio.determineNote(Hz: twoLoudestTones[1]))"
        }
        
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        audio.stop()
        if (userView.layer.sublayers?.count)! >= 1{
            userView.layer.sublayers?.remove(at: 0)
        }
    }

}

