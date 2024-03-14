//
//  Weak.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 3/14/24.
//

class Weak<T: AnyObject> {
  weak var value : T?
  init (_ value: T) {
    self.value = value
  }
}
