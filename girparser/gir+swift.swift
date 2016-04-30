//
//  gir+swift.swift
//  Gtk3Swift
//
//  Created by Rene Hexel on 2/04/2016.
//  Copyright © 2016 Rene Hexel. All rights reserved.
//

/// Swift representation of comments
public func commentCode(thing: GIR.Thing, indentation: String = "") -> String {
    return thing.comment.isEmpty ? "" : thing.comment.characters.reduce(indentation + "/// ") {
        $0 + ($1 == "\n" ? "\n" + indentation + "/// " : String($1))
    }
}

/// Swift representation of deprecation
public func deprecatedCode(thing: GIR.Thing, indentation: String) -> String? {
    return thing.deprecated.map {
        $0.isEmpty ? "" : $0.characters.reduce(indentation + "/// ") {
            $0 + ($1 == "\n" ? "\n" + indentation + "/// " : String($1))
        }
    }
}

/// Swift code representation with code following the comments
public func swiftCode(thing: GIR.Thing, _ postfix: String = "", indentation: String = "") -> String {
    let s = commentCode(thing, indentation: indentation)
    let t: String
    if let d = deprecatedCode(thing, indentation: indentation) {
        t = s + d
    } else {
        t = s
    }
    return t + (s.isEmpty ? "" : "\n") + postfix
}

/// Swift code representation of a type alias
public func swiftCode(alias: GIR.Alias) -> String {
    return swiftCode(alias, "public typealias \(alias.name) = \(alias.type)")
}

/// Swift code representation of a constant
public func swiftCode(constant: GIR.Constant) -> String {
    return swiftCode(constant, "public let \(constant.name) = \(constant.type) /* \(constant.value) */")
}

/// Swift code type alias representation of an enum
public func typeAlias(e: GIR.Enumeration) -> String {
    return swiftCode(e, "public typealias \(e.name) = \(e.type)")
}

/// Swift code representation of an enum
public func swiftCode(e: GIR.Enumeration) -> String {
    let alias = typeAlias(e)
    let code = alias + "\n\npublic extension \(e.name) {\n" + e.members.map(valueCode("    ")).joinWithSeparator("\n") + "\n}"
    return code
}

/// Swift code representation of an enum value
public func valueCode(indentation: String) -> GIR.Enumeration.Member -> String {
    return { (m: GIR.Enumeration.Member) -> String in
        swiftCode(m, indentation + "public static let \(m.name) = \(m.ctype) /* \(m.value) */", indentation: indentation)
    }
}


/// Swift protocol representation of a record/class as a wrapper of a pointer
public func recordProtocolCode(e: GIR.Record, parent: String, indentation: String = "    ") -> String {
    let p = (parent.isEmpty ? "" : ": \(parent)")
    let code = "public protocol \(e.node)Type\(p) {\n" + indentation +
        "var ptr: UnsafeMutablePointer<\(e.ctype)> { get }\n" +
    "}\n\n"
    return code
}


/// Default implementation for record methods as protocol extension
public func recordProtocolExtensionCode(e: GIR.Record, indentation: String = "    ") -> String {
    let mcode = methodCode(indentation)(e)
    let code = "public extension \(e.node)Type {\n" +
        e.methods.lazy.map(mcode).joinWithSeparator("\n") +
    "}\n\n"
    return code
}


/// Swift code for methods (with a given indentation)
public func methodCode(_ indentation: String) -> GIR.Record -> GIR.Method -> String {
    return { (record: GIR.Record) -> GIR.Method-> String in { (method: GIR.Method) -> String in
        let args = method.args.lazy
//        let n = args.count
//        print("\(method.name): \(n) arguments:")
//        method.args.forEach {
//            print("\($0.name)[instance=\($0.instance)]: \($0.type) = '\($0.ctype)'")
//        }
        return indentation + "public func \(method.name)(" +
            args.filter { !$0.instance } .map(argumentCode).joinWithSeparator(", ") +
        ") -> \(method.returns.ctype == "" ? method.returns.type : toSwift(method.returns.ctype)) {\n" + indentation +
            ( method.returns.isVoid ? "    " : "    return " ) +
        "\(method.cname)(\(args.map(toSwift).joinWithSeparator(", ")))\n" + indentation +
        "}\n"
        }}
}


/// Swift code for methods
public func argumentCode(arg: GIR.Argument) -> String {
    return "\(arg.name): \(arg.type)"
}


/// Swift code for argument
public func toSwift(_ arg: GIR.Argument) -> String {
    return arg.instance ? "ptr" : arg.name
}




/// Swift struct representation of a record/class as a wrapper of a pointer
public func recordStructCode(e: GIR.Record, indentation: String = "    ") -> String {
    let code = "public struct \(e.node)Struct: \(e.node)Type {\n" + indentation +
        "public let ptr: UnsafeMutablePointer<\(e.ctype)>\n" +
    "}\n\n" +
    "public extension \(e.node)Struct {\n" + indentation +
        "public init<T>(cPointer: UnsafeMutablePointer<T>) {\n" + indentation +
        "    ptr = UnsafeMutablePointer<\(e.ctype)>(cPointer)\n" + indentation +
        "}\n\n" + indentation +
//        "public init<T>(cPointer: UnsafePointer<T>) {\n" + indentation +
//        "    ptr = UnsafeMutablePointer<\(e.ctype)>(cPointer)\n" + indentation +
//        "}\n\n" + indentation +
        "public init(opaquePointer: COpaquePointer) {\n" + indentation +
        "    ptr = UnsafeMutablePointer<\(e.ctype)>(opaquePointer)\n" + indentation +
        "}\n\n" +
    "}\n\n"

    return code
}


/// Swift struct representation of a record/class as a wrapper of a pointer
public func recordClassCode(e: GIR.Record, parent: String, indentation: String = "    ") -> String {
    let p = parent.isEmpty ? "" : "\(parent), "
    let code = "public class \(e.name): \(p)\(e.node)Type {\n" + indentation +
        "    public let ptr: UnsafeMutablePointer<\(e.ctype)>\n\n" +
        "    public init(ptr: UnsafeMutablePointer<\(e.ctype)>) {\n" +
        "        self.ptr = ptr\n" +
        "    }\n" +
        "}\n\n" +
        "public extension \(e.name) {\n" + indentation +
        "public convenience init<T>(cPointer: UnsafeMutablePointer<T>) {\n" + indentation +
        "    self.init(ptr: UnsafeMutablePointer<\(e.ctype)>(cPointer))\n" + indentation +
        "}\n\n" + indentation +
//        "public convenience init<T>(cPointer: UnsafePointer<T>) {\n" + indentation +
//        "    self.init(ptr: UnsafeMutablePointer<\(e.ctype)>(cPointer))\n" + indentation +
//        "}\n\n" + indentation +
        "public convenience init(opaquePointer: COpaquePointer) {\n" + indentation +
        "    self.init(ptr: UnsafeMutablePointer<\(e.ctype)>(opaquePointer))\n" + indentation +
        "}\n\n" +
    "}\n\n"

    return code
}




/// Swift code representation of a record
public func swiftCode(e: GIR.Record) -> String {
    let p = recordProtocolCode(e, parent: "")
    let s = recordStructCode(e)
    let c = recordClassCode(e, parent: "")
    let e = recordProtocolExtensionCode(e)
    let code = p + s + c + e
    return code
}
