//
//  ViewController.swift
//  AudioLabSwift
//
//  Created by Eric Larson on 8/24/20.
//  Copyright © 2020 Eric Larson. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

    let audio = AudioModel()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // just start up the audio model here
        audio.play()
       
    }
    
    @IBAction func showFreq(_ sender: UIButton) {
        var mag:Float
        var freq:Float
        (mag,freq) = audio.getMaxFrequencyMagnitude()
        
        print(freq, mag)
    }
    
    
    

}

