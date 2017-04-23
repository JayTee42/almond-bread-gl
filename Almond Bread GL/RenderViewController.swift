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
    private static let expandedConstraintDistance = CGFloat(160)
    
    //Iterations:
    private static let minIterations = UInt(1)
    private static let maxIterations = UInt(1024)
    private static let initialIterations = UInt(256)
    
    //Render scale:
    private static let minRenderScale = 0.5
    private static let maxRenderScale = 1.25 * Double(UIScreen.main.scale)
    private static let initialRenderScale = Double(UIScreen.main.scale)
    
    //Continuous sliders:
    private static let initialContinuousSliders = false
    
    //Themes:
    private static let initialTheme = HueTexture.fire
    
    //Are we currently expanded?
    private var isExpanded = false
    
    //The expand / collapse constraint:
    @IBOutlet weak var expandCollapseConstraintIB: NSLayoutConstraint!
    
    //The render view:
    @IBOutlet weak var renderViewIB: RenderView!
    
    //The iterations UI:
    @IBOutlet weak var iterationsSliderIB: UISlider!
    @IBOutlet weak var iterationsLabelIB: UILabel!
    
    //The render scale UI:
    @IBOutlet weak var renderScaleSliderIB: UISlider!
    @IBOutlet weak var renderScaleLabelIB: UILabel!
    
    //The multisampling UI:
    @IBOutlet weak var multisamplingSwitchIB: UISwitch!
    
    //The continuous UI:
    @IBOutlet weak var continuousSlidersSwitchIB: UISwitch!
    
    //The themes segment:
    @IBOutlet weak var themesSegment: UISegmentedControl!
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        //Set the initial values:
        
        //Expand / Collaps:
        self.expandCollapseConstraintIB.constant = (self.isExpanded ? RenderViewController.expandedConstraintDistance : 0)
        self.view.layoutIfNeeded()
        
        //Iterations:
        self.renderViewIB.iterations = RenderViewController.initialIterations
        
        self.iterationsSliderIB.minimumValue = Float(RenderViewController.minIterations)
        self.iterationsSliderIB.maximumValue = Float(RenderViewController.maxIterations)
        self.iterationsSliderIB.value = Float(RenderViewController.initialIterations)
        
        self.iterationsLabelIB.text = "\(RenderViewController.initialIterations)"
        
        //Render scale:
        self.renderViewIB.superSamplingFactor = RenderViewController.initialRenderScale
        
        self.renderScaleSliderIB.minimumValue = Float(RenderViewController.minRenderScale)
        self.renderScaleSliderIB.maximumValue = Float(RenderViewController.maxRenderScale)
        self.renderScaleSliderIB.value = Float(RenderViewController.initialRenderScale)
        
        self.renderScaleLabelIB.text = String(format: "%.2fx", RenderViewController.initialRenderScale)
        
        //Continuous sliders:
        self.iterationsSliderIB.isContinuous = RenderViewController.initialContinuousSliders
        self.renderScaleSliderIB.isContinuous = RenderViewController.initialContinuousSliders
        
        self.continuousSlidersSwitchIB.isOn = RenderViewController.initialContinuousSliders
        
        //Themes:
        self.renderViewIB.hueTexture = RenderViewController.initialTheme
        
        self.themesSegment.removeAllSegments()
        HueTexture.orderedValues.forEach{ self.themesSegment.insertSegment(withTitle: $0.title, at: self.themesSegment.numberOfSegments, animated: false) }
        self.themesSegment.selectedSegmentIndex = HueTexture.orderedValues.index(of: RenderViewController.initialTheme)!
    }
    
    @IBAction func toggleExpandedButtonTouched(sender: UIButton)
    {
        self.isExpanded = !self.isExpanded
        
        self.view.layoutIfNeeded()
        self.expandCollapseConstraintIB.constant = (self.isExpanded ? RenderViewController.expandedConstraintDistance : 0)
        UIView.animate(withDuration: 0.5){ self.view.layoutIfNeeded() }
    }
    
    @IBAction func iterationsSliderValueChanged(sender: UISlider)
    {
        //Set the new value:
        let value = UInt(sender.value)
        
        self.renderViewIB.iterations = value
        self.iterationsLabelIB.text = "\(value)"
    }
    
    @IBAction func renderScaleSliderValueChanged(sender: UISlider)
    {
        //Set the new value:
        let value = Double(sender.value)
        
        self.renderViewIB.superSamplingFactor = value
        self.renderScaleLabelIB.text = String(format: "%.2fx", value)
    }
    
    @IBAction func continuousSlidersSwitchValueChanged(sender: UISwitch)
    {
        self.iterationsSliderIB.isContinuous = sender.isOn
        self.renderScaleSliderIB.isContinuous = sender.isOn
    }
    
    @IBAction func themesSegmentValueChanged(sender: UISegmentedControl)
    {
        self.renderViewIB.hueTexture = HueTexture.orderedValues[sender.selectedSegmentIndex]
    }
}
