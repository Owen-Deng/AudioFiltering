//
//  ModuleBViewController.swift
//  AudioLabSwift
//
//  Created by RongWei Ji on 9/28/23.
//  Copyright © 2023 Eric Larson. All rights reserved.
//

import UIKit

class ModuleBViewController: UIViewController {

    
    @IBOutlet weak var graphUIView: UIView!
    struct AudioConstants{
        static let AUDIO_BUFFER_SIZE=1024*4
        static let FFT_BUFFER_SIZE=AUDIO_BUFFER_SIZE/2
    }
    
    
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
