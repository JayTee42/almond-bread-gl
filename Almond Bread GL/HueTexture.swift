//
//  HueTexture.swift
//  Almond Bread GL
//
//  Created by Jonas Treumer on 23.04.17.
//  Copyright © 2017 TU Bergakademie Freiberg. All rights reserved.
//

enum HueTexture: String
{
    case fire = "FireHue"
    case ice = "IceHue"
    case ash = "AshHue"
    case trippy = "TrippyHue"
    
    //Get all the values in order:
    static var orderedValues: [HueTexture]
    {
        return [.fire, .ice, .ash, .trippy]
    }
    
    //A friendly title for the texture:
    var title: String
    {
        switch self
        {
        case .fire: return "Fire"
        case .ice: return "Ice"
        case .ash: return "Ash"
        case .trippy: return "Trippy"
        }
    }
}
