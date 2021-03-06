//
//  File.swift
//  
//
//  Created by Mikoláš Stuchlík on 17.11.2020.
//
import SwiftLibXML

extension GIR {

    /// a signal is equivalent to a function
    public class Signal: Function {
        public override var kind: String { return "Signal" }
    }
    
}
