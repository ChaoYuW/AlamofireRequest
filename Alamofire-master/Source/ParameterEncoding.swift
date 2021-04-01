//
//  ParameterEncoding.swift
//
//  Copyright (c) 2014-2018 Alamofire Software Foundation (http://alamofire.org/)
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Foundation

//只能编码字典数据
//ParameterEncoding编码实现简单，因为都是字典数据，body表单编码时，只需要先编码成query string，然后utf8转成data丢入body就行
//ParameterEncoding只有在创建DataRequest跟DownloadRequest时使用，DataStreamRequest无法使用
/// A dictionary of parameters to apply to a `URLRequest`.
public typealias Parameters = [String: Any]

/// A type used to define how a set of parameters are applied to a `URLRequest`.
public protocol ParameterEncoding {
    /// Creates a `URLRequest` by encoding parameters and applying them on the passed request.
    ///
    /// - Parameters:
    ///   - urlRequest: `URLRequestConvertible` value onto which parameters will be encoded.
    ///   - parameters: `Parameters` to encode onto the request.
    ///
    /// - Returns:      The encoded `URLRequest`.
    /// - Throws:       Any `Error` produced during parameter encoding.
    /// 使用URLRequestConvertible创建URLRequest, 然后把字典参数编码进URLRequest中, 可以抛出异常, 抛出异常时会返回AFError.parameterEncodingFailed错误
    func encode(_ urlRequest: URLRequestConvertible, with parameters: Parameters?) throws -> URLRequest
}

// MARK: -

/// Creates a url-encoded query string to be set as or appended to any existing URL query string or set as the HTTP
/// body of the URL request. Whether the query string is set or appended to any existing URL query string or set as
/// the HTTP body depends on the destination of the encoding.
///
/// The `Content-Type` HTTP header field of an encoded request with HTTP body is set to
/// `application/x-www-form-urlencoded; charset=utf-8`.
///
/// There is no published specification for how to encode collection types. By default the convention of appending
/// `[]` to the key for array values (`foo[]=1&foo[]=2`), and appending the key surrounded by square brackets for
/// nested dictionary values (`foo[bar]=baz`) is used. Optionally, `ArrayEncoding` can be used to omit the
/// square brackets appended to array keys.
///
/// `BoolEncoding` can be used to configure how boolean values are encoded. The default behavior is to encode
/// `true` as 1 and `false` as 0.
public struct URLEncoding: ParameterEncoding {
    // MARK: Helper Types
    // MARK: 辅助数据类型

    /// 定义参数被编码到url query中还是body中

    /// Defines whether the url-encoded query string is applied to the existing query string or HTTP body of the
    /// resulting URL request.
    public enum Destination {
        /// Applies encoded query string result to existing query string for `GET`, `HEAD` and `DELETE` requests and
        /// sets as the HTTP body for requests with any other HTTP method.
        /// 有method决定(get, head, delete为urlquery, 其他为body)
        case methodDependent
        /// Sets or appends encoded query string result to existing query string.
        /// url query
        case queryString
        /// Sets encoded query string result as the HTTP body of the URL request.
        ///body
        case httpBody
        /// 返回是否要把参数编入到url query中
        func encodesParametersInURL(for method: HTTPMethod) -> Bool {
            switch self {
            case .methodDependent: return [.get, .head, .delete].contains(method)
            case .queryString: return true
            case .httpBody: return false
            }
        }
    }
    /// 决定如何编码Array
    /// Configures how `Array` parameters are encoded.
    public enum ArrayEncoding {
        /// An empty set of square brackets is appended to the key for every value. This is the default behavior.
        /// key后跟括号编码
        case brackets
        /// No brackets are appended. The key is encoded as is.
        /// key后不跟括号编码
        case noBrackets
        /// 对key进行编码
        func encode(key: String) -> String {
            switch self {
            case .brackets:
                return "\(key)[]"
            case .noBrackets:
                return key
            }
        }
    }
    ///决定如何编码Bool
    /// Configures how `Bool` parameters are encoded.
    public enum BoolEncoding {
        /// Encode `true` as `1` and `false` as `0`. This is the default behavior.
        /// 数字: 1, 0
        case numeric
        /// Encode `true` and `false` as string literals.
        /// string: true, false
        case literal
        /// 对值进行编码
        func encode(value: Bool) -> String {
            switch self {
            case .numeric:
                return value ? "1" : "0"
            case .literal:
                return value ? "true" : "false"
            }
        }
    }

    // MARK: Properties
    // MARK: 快速初始化的三个静态计算属性

    /// 默认使用method决定编码位置, 数组使用带括号, bool使用数字
    /// Returns a default `URLEncoding` instance with a `.methodDependent` destination.
    public static var `default`: URLEncoding { URLEncoding() }
    /// url query 编码, 数组使用带括号, bool使用数字
    /// Returns a `URLEncoding` instance with a `.queryString` destination.
    public static var queryString: URLEncoding { URLEncoding(destination: .queryString) }
    /// form 表单编码到body, 数组使用带括号, bool使用数字
    /// Returns a `URLEncoding` instance with an `.httpBody` destination.
    public static var httpBody: URLEncoding { URLEncoding(destination: .httpBody) }
    //MARK: 属性与初始化
    /// 参数编码位置
    /// The destination defining where the encoded query string is to be applied to the URL request.
    public let destination: Destination
    /// 数组编码格式
    /// The encoding to use for `Array` parameters.
    public let arrayEncoding: ArrayEncoding
    /// Bool编码格式
    /// The encoding to use for `Bool` parameters.
    public let boolEncoding: BoolEncoding

    // MARK: Initialization

    /// Creates an instance using the specified parameters.
    ///
    /// - Parameters:
    ///   - destination:   `Destination` defining where the encoded query string will be applied. `.methodDependent` by
    ///                    default.
    ///   - arrayEncoding: `ArrayEncoding` to use. `.brackets` by default.
    ///   - boolEncoding:  `BoolEncoding` to use. `.numeric` by default.
    public init(destination: Destination = .methodDependent,
                arrayEncoding: ArrayEncoding = .brackets,
                boolEncoding: BoolEncoding = .numeric) {
        self.destination = destination
        self.arrayEncoding = arrayEncoding
        self.boolEncoding = boolEncoding
    }

    // MARK: Encoding
    // MARK: 实现协议的编码方法
    public func encode(_ urlRequest: URLRequestConvertible, with parameters: Parameters?) throws -> URLRequest {
        //先拿到URLRequest
        var urlRequest = try urlRequest.asURLRequest()
        //没参数的话直接返回
        guard let parameters = parameters else { return urlRequest }

        // 根据请求方法不同判断处理参数是放在url后面还是body
        //先拿到method, 然后使用method判断下往哪里编码参数
        //不够严谨, 如果method为空, 应该抛出异常的. ParameterEncoder中有处理
        if let method = urlRequest.method, destination.encodesParametersInURL(for: method) {
            //url query编码
            guard let url = urlRequest.url else {
                // url为空直接抛出异常
                throw AFError.parameterEncodingFailed(reason: .missingURL)
            }

            if var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false), !parameters.isEmpty {
                //先获取到已有的query string, 存在的话就加上个&, 然后拼接上新的query string
                let percentEncodedQuery = (urlComponents.percentEncodedQuery.map { $0 + "&" } ?? "") + query(parameters)
                urlComponents.percentEncodedQuery = percentEncodedQuery
                urlRequest.url = urlComponents.url
            }
        } else {
            //body编码
            if urlRequest.headers["Content-Type"] == nil {
                urlRequest.headers.update(.contentType("application/x-www-form-urlencoded; charset=utf-8"))
            }
            //把query string转成utf8编码丢入body中
            urlRequest.httpBody = Data(query(parameters).utf8)
        }

        return urlRequest
    }

    /// Creates a percent-escaped, URL encoded query string components from the given key-value pair recursively.
    ///
    /// - Parameters:
    ///   - key:   Key of the query component.
    ///   - value: Value of the query component.
    ///
    /// - Returns: The percent-escaped, URL encoded query string components.
    // 递归遍历参数的每一层，将其展开为一维
    public func queryComponents(fromKey key: String, value: Any) -> [(String, String)] {
        // 创建一个数组，参数类型是2个字符串的元组类型，用于分别存储key、value
        var components: [(String, String)] = []
        // 根据参数字典中的value类型是字典、数组、整型、布尔分别处理
        switch value {
        case let dictionary as [String: Any]:
            //字典处理, 遍历字典递归调用
            for (nestedKey, value) in dictionary {
                components += queryComponents(fromKey: "\(key)[\(nestedKey)]", value: value)
            }
        case let array as [Any]:
            for value in array {
                //数组处理, 根据数组key编码的类型遍历递归调用
                components += queryComponents(fromKey: arrayEncoding.encode(key: key), value: value)
            }
        case let number as NSNumber:
            //nsnumber使用objCType类判断是否是bool
            if number.isBool {
                components.append((escape(key), escape(boolEncoding.encode(value: number.boolValue))))
            } else {
                components.append((escape(key), escape("\(number)")))
            }
        case let bool as Bool:
            //bool处理, 根据编码类型来处理
            components.append((escape(key), escape(boolEncoding.encode(value: bool))))
        default:
            //其他的,直接转成string
            components.append((escape(key), escape("\(value)")))
        }
        return components
    }

    /// Creates a percent-escaped string following RFC 3986 for a query string key or value.
    ///
    /// - Parameter string: `String` to be percent-escaped.
    ///
    /// - Returns:          The percent-escaped `String`.
    /// url转义, 转成百分号格式的
    /// 会忽略   :#[]@!$&'()*+,;=
    public func escape(_ string: String) -> String {
        string.addingPercentEncoding(withAllowedCharacters: .afURLQueryAllowed) ?? string
    }
    /// 把参数字典转成query string
    private func query(_ parameters: [String: Any]) -> String {
        // 创建一个元组，参数类型是2个字符串的元组类型，用于分别存储key、value
        var components: [(String, String)] = []
        // 将参数key按照字母正序的方式排序，然后遍历每个key
        for key in parameters.keys.sorted(by: <) {
            let value = parameters[key]!
            // 根据value类型具体处理参数
            components += queryComponents(fromKey: key, value: value)
        }
        // 按照key1=value1&key2=value2的格式拼接返回参数字符串
        return components.map { "\($0)=\($1)" }.joined(separator: "&")
    }
}

// MARK: -

/// Uses `JSONSerialization` to create a JSON representation of the parameters object, which is set as the body of the
/// request. The `Content-Type` HTTP header field of an encoded request is set to `application/json`.
public struct JSONEncoding: ParameterEncoding {
    // MARK: Properties
    // MARK: 用来快速初始化的静态计算变量

    //默认类型, 压缩json格式

    /// Returns a `JSONEncoding` instance with default writing options.
    public static var `default`: JSONEncoding { JSONEncoding() }

    /// Returns a `JSONEncoding` instance with `.prettyPrinted` writing options.
    //标准json格式
    public static var prettyPrinted: JSONEncoding { JSONEncoding(options: .prettyPrinted) }

    // MARK: 属性与初始化
        
    //保存JSONSerialization.WritingOptions
    /// The options for writing the parameters as JSON data.
    public let options: JSONSerialization.WritingOptions

    // MARK: Initialization

    /// Creates an instance using the specified `WritingOptions`.
    ///
    /// - Parameter options: `JSONSerialization.WritingOptions` to use.
    
    public init(options: JSONSerialization.WritingOptions = []) {
        self.options = options
    }

    // MARK: Encoding
    // MARK: 实现协议的编码方法
    public func encode(_ urlRequest: URLRequestConvertible, with parameters: Parameters?) throws -> URLRequest {
        //拿到Request
        var urlRequest = try urlRequest.asURLRequest()

        guard let parameters = parameters else { return urlRequest }

        do {
            //编码成data
            let data = try JSONSerialization.data(withJSONObject: parameters, options: options)

            if urlRequest.headers["Content-Type"] == nil {
                urlRequest.headers.update(.contentType("application/json"))
            }
            //丢入body
            urlRequest.httpBody = data
        } catch {
            throw AFError.parameterEncodingFailed(reason: .jsonEncodingFailed(error: error))
        }

        return urlRequest
    }

    /// Encodes any JSON compatible object into a `URLRequest`.
    ///
    /// - Parameters:
    ///   - urlRequest: `URLRequestConvertible` value into which the object will be encoded.
    ///   - jsonObject: `Any` value (must be JSON compatible` to be encoded into the `URLRequest`. `nil` by default.
    ///
    /// - Returns:      The encoded `URLRequest`.
    /// - Throws:       Any `Error` produced during encoding.
    //把json对象编码进body中, 其实上面的编码方法可以直接掉这个方法, 两个方法实现一毛一样
    public func encode(_ urlRequest: URLRequestConvertible, withJSONObject jsonObject: Any? = nil) throws -> URLRequest {
        var urlRequest = try urlRequest.asURLRequest()

        guard let jsonObject = jsonObject else { return urlRequest }

        do {
            let data = try JSONSerialization.data(withJSONObject: jsonObject, options: options)

            if urlRequest.headers["Content-Type"] == nil {
                urlRequest.headers.update(.contentType("application/json"))
            }

            urlRequest.httpBody = data
        } catch {
            throw AFError.parameterEncodingFailed(reason: .jsonEncodingFailed(error: error))
        }

        return urlRequest
    }
}

// MARK: -

extension NSNumber {
    fileprivate var isBool: Bool {
        // Use Obj-C type encoding to check whether the underlying type is a `Bool`, as it's guaranteed as part of
        // swift-corelibs-foundation, per [this discussion on the Swift forums](https://forums.swift.org/t/alamofire-on-linux-possible-but-not-release-ready/34553/22).
        String(cString: objCType) == "c"
    }
}
