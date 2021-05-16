import Foundation


/// Code Builder is a ResultBuilder class which provides easier-to-read way of composing string with indentation and new lines. Element of the DSL generated by this class is `String`. As for now, only if-else statements are available. At the time of implementation, for-in statement was not widely available.
/// - Note: ResultBuilder is merged in Swift 5.4 and available since Swift 5.1
#if swift(>=5.4)
@resultBuilder class CodeBuilder {}
#else
@_functionBuilder class CodeBuilder {}
#endif
extension CodeBuilder {
    /// Ignoring sequence is introduec in order to prevent superfulous line breaks in conditions 
    static let ignoringEspace: String = "<%IGNORED%>"
    
    /// Following static methods are documented in https://github.com/apple/swift-evolution/blob/main/proposals/0289-result-builders.md
    static func buildBlock( _ segments: String...) -> String {
        segments.filter { $0 != CodeBuilder.ignoringEspace } .joined(separator: "\n")
    }
    
    static func buildEither(first: String) -> String { first }
    static func buildEither(second: String) -> String { second }
    
    static func buildOptional(_ component: String?) -> String { component ?? CodeBuilder.ignoringEspace }
    static func buildIf(_ segment: String?) -> String { buildOptional(segment) }
}

/// Convenience class for using CodeBuilder DSL. This class was introduced to shorten calls. As for now, this class compensates for some missing DSL features like for-in loops. 
class Code {
    static var defaultCodeIndentation: String = "    "
    
    /// Code in builder block of this function will have additional indentation passed in the first argument.
    /// - Parameter indentation: Intendation added on top of existing indentation. Default value is value of static property `defaultCodeIndentation`. Pass `nil` or "" to ommit indentation.
    static func block(indentation: String? = defaultCodeIndentation, @CodeBuilder builder: ()->String) -> String {
        let code = builder()
        
        if let indentation = indentation {
            return indentation + (code.replacingOccurrences(of: "\n", with: "\n" + indentation))
        }
        
        return builder()
    }
    
    /// Strings inside of this builder have all occurances of `\n` removed.
    static func line(@CodeBuilder builder: ()->String) -> String {
        builder().components(separatedBy: "\n").joined()
    }
    
    /// Loop provided as a replacement for missing for-in loop. This function will be removed in the future. For Enumerated variant use `loopEnumerated(over:builder:)`
    static func loop<T>(over items: [T], @CodeBuilder builder: (T)->String) -> String {
        !items.isEmpty ? items.map(builder).joined(separator: "\n") : CodeBuilder.ignoringEspace
    }
    
    /// Loop provided as a replacement for missing for-in loop. Array is returned as enumerated.
    static func loopEnumerated<T>(over items: [T], @CodeBuilder builder: (Int, T)->String) -> String {
        !items.isEmpty ? items.enumerated().map(builder).joined(separator: "\n") : CodeBuilder.ignoringEspace
    }
}
