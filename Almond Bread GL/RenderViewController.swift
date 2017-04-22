//
//  RenderViewController.swift
//  Almond Bread GL
//
//  Created by Jonas Treumer on 21.04.17.
//  Copyright © 2017 TU Bergakademie Freiberg. All rights reserved.
//

import UIKit

class RenderViewController: UIViewController
{
    //The render view:
    @IBOutlet weak var renderViewIB: RenderView!
    
    @IBAction func iterationsSliderValueChanged(sender: UISlider)
    {
        //Set the new value:
        self.renderViewIB.iterations = UInt(sender.value)
    }
}
