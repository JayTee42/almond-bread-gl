//
//  AdditionalInforViewController.swift
//  Almond Bread GL
//
//  Created by Jonas Treumer on 24.04.17.
//  Copyright © 2017 TU Bergakademie Freiberg. All rights reserved.
//

import UIKit

class AdditionalInfoViewController: UIViewController
{
    //The shader label:
    @IBOutlet weak var shaderLabelIB: UILabel!
    
    //The background for it:
    @IBOutlet weak var shaderLabelBackgroundIB: UIView!
    
    override func viewDidLoad()
    {
        let dbgDomain = "Loading shader source"
        
        //Load the shader:
        guard let url = Bundle.main.url(forResource: "FragmentShader", withExtension: "glsl") else
        {
            preconditionFailure("[\(dbgDomain)] Failed to load source code for shader: \"FragmentShader\"")
        }
        
        guard let sourceCode = try? String(contentsOf: url, encoding: String.Encoding.utf8) else
        {
            preconditionFailure("[\(dbgDomain)] Failed to load source code for shader: \"FragmentShader\"")
        }
        
        self.shaderLabelIB.text = sourceCode.trimmingCharacters(in: CharacterSet.newlines)
        
        //Put fancy round corners to the background view:
        self.shaderLabelBackgroundIB.layer.cornerRadius = 15
        
        //Re-layout:
        self.view.layoutIfNeeded()
    }
    
    @IBAction func licenseButtonTouched(sender: UIButton)
    {
        UIApplication.shared.open(URL(string: "https://creativecommons.org/licenses/by/2.0/")!)
    }
    
    @IBAction func gitButtonTouched(sender: UIButton)
    {
        UIApplication.shared.open(URL(string: "https://github.com/EndoplasmaticReticulum/almond-bread-gl")!)
    }

    @IBAction func dismissButtonTouched(sender: UIButton)
    {
        dismiss(animated: true, completion: nil)
    }
}
