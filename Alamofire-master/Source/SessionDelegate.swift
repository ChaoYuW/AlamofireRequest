//
//  SessionDelegate.swift
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

/// Class which implements the various `URLSessionDelegate` methods to connect various Alamofire features.
open class SessionDelegate: NSObject {
//    用于下载的回调里，处理文件
    private let fileManager: FileManager
//    用于在URLSessionDelegate获取request信息以及回调给外面状态
    weak var stateProvider: SessionStateProvider?
//    在各种回调里，调用事件监听器对应的方法，让外界处理
    var eventMonitor: EventMonitor?

    /// Creates an instance from the given `FileManager`.
    ///
    /// - Parameter fileManager: `FileManager` to use for underlying file management, such as moving downloaded files.
    ///                          `.default` by default.
    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Internal method to find and cast requests while maintaining some integrity checking.
    ///
    /// - Parameters:
    ///   - task: The `URLSessionTask` for which to find the associated `Request`.
    ///   - type: The `Request` subclass type to cast any `Request` associate with `task`.
    //根据Task获取对应的Request, 并转换成对应的子类
    func request<R: Request>(for task: URLSessionTask, as type: R.Type) -> R? {
        guard let provider = stateProvider else {
            assertionFailure("StateProvider is nil.")
            return nil
        }
//        从SessionStateProvider(Session)中根据task获取request
        return provider.request(for: task) as? R
    }
}

/// Type which provides various `Session` state values.
protocol SessionStateProvider: AnyObject {
//    获取安全认证管理者
    var serverTrustManager: ServerTrustManager? { get }
//    获取重定向的处理者
    var redirectHandler: RedirectHandler? { get }
//    获取缓存响应的处理者
    var cachedResponseHandler: CachedResponseHandler? { get }

//    通过task获取Request
    func request(for task: URLSessionTask) -> Request?
//    收集到性能指标之后的回调
    func didGatherMetricsForTask(_ task: URLSessionTask)
//    请求完成的回调
    func didCompleteTask(_ task: URLSessionTask, completion: @escaping () -> Void)
//    获取身份验证的证书
    func credential(for task: URLSessionTask, in protectionSpace: URLProtectionSpace) -> URLCredential?
//    URLSession无效的回调
    func cancelRequestsForSessionInvalidation(with error: Error?)
}

// MARK: URLSessionDelegate

extension SessionDelegate: URLSessionDelegate {
    open func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        //Session不可用时, 通知监听器, 然后回调Session取消全部请求
        eventMonitor?.urlSession(session, didBecomeInvalidWithError: error)

        stateProvider?.cancelRequestsForSessionInvalidation(with: error)
    }
}

// MARK: URLSessionTaskDelegate

extension SessionDelegate: URLSessionTaskDelegate {
    /// Result of a `URLAuthenticationChallenge` evaluation.
    //定义元组包裹认证处理方式, 证书, 以及错误
    typealias ChallengeEvaluation = (disposition: URLSession.AuthChallengeDisposition, credential: URLCredential?, error: AFError?)
    //收到需要验证证书的回调
    open func urlSession(_ session: URLSession,
                         task: URLSessionTask,
                         didReceive challenge: URLAuthenticationChallenge,
                         completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        //告知事件监听器
        eventMonitor?.urlSession(session, task: task, didReceive: challenge)

        let evaluation: ChallengeEvaluation
        //组装认证方式, 证书, 错误信息
        switch challenge.protectionSpace.authenticationMethod {
        case NSURLAuthenticationMethodServerTrust:
            evaluation = attemptServerTrustAuthentication(with: challenge)
        case NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodHTTPDigest, NSURLAuthenticationMethodNTLM,
             NSURLAuthenticationMethodNegotiate, NSURLAuthenticationMethodClientCertificate:
            evaluation = attemptCredentialAuthentication(for: challenge, belongingTo: task)
        default:
            evaluation = (.performDefaultHandling, nil, nil)
        }
        //获取证书失败的话, 该请求失败, 传递错误
        if let error = evaluation.error {
            stateProvider?.request(for: task)?.didFailTask(task, earlyWithError: error)
        }

        completionHandler(evaluation.disposition, evaluation.credential)
    }

    /// Evaluates the server trust `URLAuthenticationChallenge` received.
    ///
    /// - Parameter challenge: The `URLAuthenticationChallenge`.
    ///
    /// - Returns:             The `ChallengeEvaluation`.
//    处理服务器认证
    func attemptServerTrustAuthentication(with challenge: URLAuthenticationChallenge) -> ChallengeEvaluation {
        let host = challenge.protectionSpace.host

        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust
        else {
            //如果没有自定义证书管理器 直接返回默认处理即可
            return (.performDefaultHandling, nil, nil)
        }

        do {
            guard let evaluator = try stateProvider?.serverTrustManager?.serverTrustEvaluator(forHost: host) else {
                return (.performDefaultHandling, nil, nil)
            }
            //从ServerTrustManager中取ServerTrustEvaluating对象, 执行自定义认证
            try evaluator.evaluate(trust, forHost: host)

            return (.useCredential, URLCredential(trust: trust), nil)
        } catch {
            //自定义认证出错的话, 返回取消认证操作 + 错误
            return (.cancelAuthenticationChallenge, nil, error.asAFError(or: .serverTrustEvaluationFailed(reason: .customEvaluationFailed(error: error))))
        }
    }

    /// Evaluates the credential-based authentication `URLAuthenticationChallenge` received for `task`.
    ///
    /// - Parameters:
    ///   - challenge: The `URLAuthenticationChallenge`.
    ///   - task:      The `URLSessionTask` which received the challenge.
    ///
    /// - Returns:     The `ChallengeEvaluation`.
    //其他认证方式
    func attemptCredentialAuthentication(for challenge: URLAuthenticationChallenge,
                                         belongingTo task: URLSessionTask) -> ChallengeEvaluation {
        guard challenge.previousFailureCount == 0 else {
            //如果之前认证失败了 直接跳过本次认证, 开始下一次认证
            return (.rejectProtectionSpace, nil, nil)
        }

        guard let credential = stateProvider?.credential(for: task, in: challenge.protectionSpace) else {
            //没有获取到认证处理对象, 忽略本次认证
            return (.performDefaultHandling, nil, nil)
        }

        return (.useCredential, credential, nil)
    }
    //上传进度
    open func urlSession(_ session: URLSession,
                         task: URLSessionTask,
                         didSendBodyData bytesSent: Int64,
                         totalBytesSent: Int64,
                         totalBytesExpectedToSend: Int64) {
        //通知监听器
        eventMonitor?.urlSession(session,
                                 task: task,
                                 didSendBodyData: bytesSent,
                                 totalBytesSent: totalBytesSent,
                                 totalBytesExpectedToSend: totalBytesExpectedToSend)
        //拿到Request, 更新上传进度
        stateProvider?.request(for: task)?.updateUploadProgress(totalBytesSent: totalBytesSent,
                                                                totalBytesExpectedToSend: totalBytesExpectedToSend)
    }
    //上传请求准备上传新的body流
    open func urlSession(_ session: URLSession,
                         task: URLSessionTask,
                         needNewBodyStream completionHandler: @escaping (InputStream?) -> Void) {
        //通知监听器
        eventMonitor?.urlSession(session, taskNeedsNewBodyStream: task)

        guard let request = request(for: task, as: UploadRequest.self) else {
            //只有上传请求会响应这个方法
            assertionFailure("needNewBodyStream did not find UploadRequest.")
            completionHandler(nil)
            return
        }
        //从request中拿到InputStream返回, 只有使用InputStream创建的上传请求才会返回正确, 否则会抛出错误
        completionHandler(request.inputStream())
    }
    //重定向
    open func urlSession(_ session: URLSession,
                         task: URLSessionTask,
                         willPerformHTTPRedirection response: HTTPURLResponse,
                         newRequest request: URLRequest,
                         completionHandler: @escaping (URLRequest?) -> Void) {
        //通知监听器
        eventMonitor?.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: request)

        if let redirectHandler = stateProvider?.request(for: task)?.redirectHandler ?? stateProvider?.redirectHandler {
            //先看Request有没有自己的重定向处理器, 再看Session有没有全局重定向处理器, 有的话处理下
            redirectHandler.task(task, willBeRedirectedTo: request, for: response, completion: completionHandler)
        } else {
            completionHandler(request)
        }
    }
    //获取请求指标
    open func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        //通知监听器
        eventMonitor?.urlSession(session, task: task, didFinishCollecting: metrics)
        //通知Request
        stateProvider?.request(for: task)?.didGatherMetrics(metrics)
        //通知Session
        stateProvider?.didGatherMetricsForTask(task)
    }
    //请求完成, 后续可能回去获取网页指标
    open func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        //通知监听器
        eventMonitor?.urlSession(session, task: task, didCompleteWithError: error)
        //通知Session请求完成
        let request = stateProvider?.request(for: task)

        stateProvider?.didCompleteTask(task) {
            //回调内容为 确认请求指标完成后, 通知Request请求完成
            request?.didCompleteTask(task, with: error.map { $0.asAFError(or: .sessionTaskFailed(error: $0)) })
        }
    }

    @available(macOS 10.13, iOS 11.0, tvOS 11.0, watchOS 4.0, *)
    //网络变更导致的请求等待处理
    open func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
        eventMonitor?.urlSession(session, taskIsWaitingForConnectivity: task)
    }
}

// MARK: URLSessionDataDelegate

extension SessionDelegate: URLSessionDataDelegate {
    //收到响应数据
    open func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        //通知监听器
        eventMonitor?.urlSession(session, dataTask: dataTask, didReceive: data)
        //只有DataRequest跟DataStreamRequest会收到数据
        if let request = request(for: dataTask, as: DataRequest.self) {
            request.didReceive(data: data)
        } else if let request = request(for: dataTask, as: DataStreamRequest.self) {
            request.didReceive(data: data)
        } else {
            assertionFailure("dataTask did not find DataRequest or DataStreamRequest in didReceive")
            return
        }
    }
    //处理是否保存缓存
    open func urlSession(_ session: URLSession,
                         dataTask: URLSessionDataTask,
                         willCacheResponse proposedResponse: CachedURLResponse,
                         completionHandler: @escaping (CachedURLResponse?) -> Void) {
        //通知监听器
        eventMonitor?.urlSession(session, dataTask: dataTask, willCacheResponse: proposedResponse)

        if let handler = stateProvider?.request(for: dataTask)?.cachedResponseHandler ?? stateProvider?.cachedResponseHandler {
            //用request的缓存处理器处理缓存
            handler.dataTask(dataTask, willCacheResponse: proposedResponse, completion: completionHandler)
        } else {
            //没有缓存处理器的话，采用默认逻辑处理缓存
            completionHandler(proposedResponse)
        }
    }
}

// MARK: URLSessionDownloadDelegate

extension SessionDelegate: URLSessionDownloadDelegate {
    //开始断点续传的回调
    open func urlSession(_ session: URLSession,
                         downloadTask: URLSessionDownloadTask,
                         didResumeAtOffset fileOffset: Int64,
                         expectedTotalBytes: Int64) {
        eventMonitor?.urlSession(session,
                                 downloadTask: downloadTask,
                                 didResumeAtOffset: fileOffset,
                                 expectedTotalBytes: expectedTotalBytes)
        guard let downloadRequest = request(for: downloadTask, as: DownloadRequest.self) else {
            //只有DownloadRequest能处理该协议
            assertionFailure("downloadTask did not find DownloadRequest.")
            return
        }

        downloadRequest.updateDownloadProgress(bytesWritten: fileOffset,
                                               totalBytesExpectedToWrite: expectedTotalBytes)
    }
    //更新下载进度
    open func urlSession(_ session: URLSession,
                         downloadTask: URLSessionDownloadTask,
                         didWriteData bytesWritten: Int64,
                         totalBytesWritten: Int64,
                         totalBytesExpectedToWrite: Int64) {
        eventMonitor?.urlSession(session,
                                 downloadTask: downloadTask,
                                 didWriteData: bytesWritten,
                                 totalBytesWritten: totalBytesWritten,
                                 totalBytesExpectedToWrite: totalBytesExpectedToWrite)
        guard let downloadRequest = request(for: downloadTask, as: DownloadRequest.self) else {
            assertionFailure("downloadTask did not find DownloadRequest.")
            return
        }

        downloadRequest.updateDownloadProgress(bytesWritten: bytesWritten,
                                               totalBytesExpectedToWrite: totalBytesExpectedToWrite)
    }
    //下载完成
    open func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        eventMonitor?.urlSession(session, downloadTask: downloadTask, didFinishDownloadingTo: location)

        guard let request = request(for: downloadTask, as: DownloadRequest.self) else {
            assertionFailure("downloadTask did not find DownloadRequest.")
            return
        }
        //准备转存文件，定义(转存目录，下载options)元组
        let (destination, options): (URL, DownloadRequest.Options)
        if let response = request.response {
            //从request拿到转存目录
            (destination, options) = request.destination(location, response)
        } else {
            // If there's no response this is likely a local file download, so generate the temporary URL directly.
            (destination, options) = (DownloadRequest.defaultDestinationURL(location), [])
        }

        eventMonitor?.request(request, didCreateDestinationURL: destination)

        do {
            //是否删除旧文件
            if options.contains(.removePreviousFile), fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            //是否创建目录链
            if options.contains(.createIntermediateDirectories) {
                let directory = destination.deletingLastPathComponent()
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            //转存文件
            try fileManager.moveItem(at: location, to: destination)
            //回调给request
            request.didFinishDownloading(using: downloadTask, with: .success(destination))
        } catch {
            //出错的话抛出异常
            request.didFinishDownloading(using: downloadTask, with: .failure(.downloadedFileMoveFailed(error: error,
                                                                                                       source: location,
                                                                                                       destination: destination)))
        }
    }
}
