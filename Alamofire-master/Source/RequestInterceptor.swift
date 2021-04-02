//
//  RequestInterceptor.swift
//
//  Copyright (c) 2019 Alamofire Software Foundation (http://alamofire.org/)
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
//RequestInterceptor请求拦截器是一个协议，用来在请求流程中拦截请求，并对请求进行一些必要的处理
/// A type that can inspect and optionally adapt a `URLRequest` in some manner if necessary.
public protocol RequestAdapter {
    /// Inspects and adapts the specified `URLRequest` in some manner and calls the completion handler with the Result.
    ///
    /// - Parameters:
    ///   - urlRequest: The `URLRequest` to adapt.
    ///   - session:    The `Session` that will execute the `URLRequest`.
    ///   - completion: The completion handler that must be called when adaptation is complete.
    func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping (Result<URLRequest, Error>) -> Void)
}

// MARK: -

/// Outcome of determination whether retry is necessary.
public enum RetryResult {
    /// Retry should be attempted immediately.
    /// 立刻重试
    case retry
    /// Retry should be attempted after the associated `TimeInterval`.
    /// 延迟重试
    case retryWithDelay(TimeInterval)
    /// Do not retry.
    /// 不重试,直接完成请求
    case doNotRetry
    /// Do not retry due to the associated `Error`.
    /// 不重试并抛出错误
    case doNotRetryWithError(Error)
}

extension RetryResult {
    /// 是否需要重试
    var retryRequired: Bool {
        switch self {
        case .retry, .retryWithDelay: return true
        default: return false
        }
    }
    /// 延迟重试时间
    var delay: TimeInterval? {
        switch self {
        case let .retryWithDelay(delay): return delay
        default: return nil
        }
    }
    /// 不重试并抛出错误时的错误信息
    var error: Error? {
        guard case let .doNotRetryWithError(error) = self else { return nil }
        return error
    }
}

/// A type that determines whether a request should be retried after being executed by the specified session manager
/// and encountering an error.
public protocol RequestRetrier {
    /// Determines whether the `Request` should be retried by calling the `completion` closure.
    ///
    /// This operation is fully asynchronous. Any amount of time can be taken to determine whether the request needs
    /// to be retried. The one requirement is that the completion closure is called to ensure the request is properly
    /// cleaned up after.
    ///
    /// - Parameters:
    ///   - request:    `Request` that failed due to the provided `Error`.
    ///   - session:    `Session` that produced the `Request`.
    ///   - error:      `Error` encountered while executing the `Request`.
    ///   - completion: Completion closure to be executed when a retry decision has been determined.
    func retry(_ request: Request, for session: Session, dueTo error: Error, completion: @escaping (RetryResult) -> Void)
}

// MARK: -

/// Type that provides both `RequestAdapter` and `RequestRetrier` functionality.
public protocol RequestInterceptor: RequestAdapter, RequestRetrier {}
//扩展一下，使得即便遵循协议也可以不实现方法，依旧不会报错
extension RequestInterceptor {
    public func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        //直接返回原请求
        completion(.success(urlRequest))
    }

    public func retry(_ request: Request,
                      for session: Session,
                      dueTo error: Error,
                      completion: @escaping (RetryResult) -> Void) {
        //不重试
        completion(.doNotRetry)
    }
}
// 先定义了一个用来适配请求的闭包：
/// `RequestAdapter` closure definition.
public typealias AdaptHandler = (URLRequest, Session, _ completion: @escaping (Result<URLRequest, Error>) -> Void) -> Void
/// `RequestRetrier` closure definition.
//先定义了一个用来决定重试逻辑的闭包：
public typealias RetryHandler = (Request, Session, Error, _ completion: @escaping (RetryResult) -> Void) -> Void

// MARK: -


/// Closure-based `RequestAdapter`.
open class Adapter: RequestInterceptor {
    private let adaptHandler: AdaptHandler

    /// Creates an instance using the provided closure.
    ///
    /// - Parameter adaptHandler: `AdaptHandler` closure to be executed when handling request adaptation.
    public init(_ adaptHandler: @escaping AdaptHandler) {
        self.adaptHandler = adaptHandler
    }

    open func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        adaptHandler(urlRequest, session, completion)
    }
}

// MARK: -
//然后实现基于闭包的请求适配器，只是简单的持有一个闭包来适配请求：
/// Closure-based `RequestRetrier`.
open class Retrier: RequestInterceptor {
    private let retryHandler: RetryHandler

    /// Creates an instance using the provided closure.
    ///
    /// - Parameter retryHandler: `RetryHandler` closure to be executed when handling request retry.
    public init(_ retryHandler: @escaping RetryHandler) {
        self.retryHandler = retryHandler
    }

    open func retry(_ request: Request,
                    for session: Session,
                    dueTo error: Error,
                    completion: @escaping (RetryResult) -> Void) {
        retryHandler(request, session, error, completion)
    }
}

// MARK: -

/// `RequestInterceptor` which can use multiple `RequestAdapter` and `RequestRetrier` values.
open class Interceptor: RequestInterceptor {
    /// All `RequestAdapter`s associated with the instance. These adapters will be run until one fails.
    /// 保存适配器, 有任何一个出现错误, 就会抛出错误
    public let adapters: [RequestAdapter]
    /// All `RequestRetrier`s associated with the instance. These retriers will be run one at a time until one triggers retry.
    /// 保存重试器, 有任何一个出现了需要重试(立即重试或者延迟重试)就会停止, 然后抛出需要重试. 有任何一个不重试并抛出错误也会停止, 并抛出错误.
    public let retriers: [RequestRetrier]

    /// Creates an instance from `AdaptHandler` and `RetryHandler` closures.
    ///
    /// - Parameters:
    ///   - adaptHandler: `AdaptHandler` closure to be used.
    ///   - retryHandler: `RetryHandler` closure to be used.
    /// 也可以使用重试器与适配器回调来创建单个的组合器
    public init(adaptHandler: @escaping AdaptHandler, retryHandler: @escaping RetryHandler) {
        adapters = [Adapter(adaptHandler)]
        retriers = [Retrier(retryHandler)]
    }

    /// Creates an instance from `RequestAdapter` and `RequestRetrier` values.
    ///
    /// - Parameters:
    ///   - adapter: `RequestAdapter` value to be used.
    ///   - retrier: `RequestRetrier` value to be used.
    /// 用两个数组初始化
    public init(adapter: RequestAdapter, retrier: RequestRetrier) {
        adapters = [adapter]
        retriers = [retrier]
    }

    /// Creates an instance from the arrays of `RequestAdapter` and `RequestRetrier` values.
    ///
    /// - Parameters:
    ///   - adapters:     `RequestAdapter` values to be used.
    ///   - retriers:     `RequestRetrier` values to be used.
    ///   - interceptors: `RequestInterceptor`s to be used.
    /// 用适配器+重试器+拦截器数组初始化, 会把拦截器数组均加入到适配器与重试器数组中
    public init(adapters: [RequestAdapter] = [], retriers: [RequestRetrier] = [], interceptors: [RequestInterceptor] = []) {
        self.adapters = adapters + interceptors
        self.retriers = retriers + interceptors
    }
    /// 适配器代理方法, 调下面的私有方法
    open func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        adapt(urlRequest, for: session, using: adapters, completion: completion)
    }
    /// 私有适配方法, 会不停递归
    private func adapt(_ urlRequest: URLRequest,
                       for session: Session,
                       using adapters: [RequestAdapter],
                       completion: @escaping (Result<URLRequest, Error>) -> Void) {
        // 用来准备递归的数组
        var pendingAdapters = adapters
        // 递归空了就执行回调并返回
        guard !pendingAdapters.isEmpty else { completion(.success(urlRequest)); return }
        // 取出第一个适配器
        let adapter = pendingAdapters.removeFirst()

        adapter.adapt(urlRequest, for: session) { result in
            switch result {
            case let .success(urlRequest):
                // 适配通过, 递归去适配剩下的
                self.adapt(urlRequest, for: session, using: pendingAdapters, completion: completion)
            case .failure:
                // 适配失败, 直接抛出错误
                completion(result)
            }
        }
    }
    // 重试器逻辑, 调下面私有方法
    open func retry(_ request: Request,
                    for session: Session,
                    dueTo error: Error,
                    completion: @escaping (RetryResult) -> Void) {
        retry(request, for: session, dueTo: error, using: retriers, completion: completion)
    }
    // 私有重试逻辑, 会递归调用
    private func retry(_ request: Request,
                       for session: Session,
                       dueTo error: Error,
                       using retriers: [RequestRetrier],
                       completion: @escaping (RetryResult) -> Void) {
        // 用来递归的重试器数组
        var pendingRetriers = retriers
        // 递归完成且没有触发重试或错误, 就返回不重试, 并返回不重试
        guard !pendingRetriers.isEmpty else { completion(.doNotRetry); return }
        // 取出第一个
        let retrier = pendingRetriers.removeFirst()

        retrier.retry(request, for: session, dueTo: error) { result in
            switch result {
            case .retry, .retryWithDelay, .doNotRetryWithError:
                completion(result)
            case .doNotRetry:
                // Only continue to the next retrier if retry was not triggered and no error was encountered
                self.retry(request, for: session, dueTo: error, using: pendingRetriers, completion: completion)
            }
        }
    }
}
