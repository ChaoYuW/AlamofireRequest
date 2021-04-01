//
//  RequestTaskMap.swift
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
//用来保存Request对象与URLSessionTask的双向映射， 该结构体被Session持有，可以用来快速根据Request找到对应的URLSessionTask， 或者根据URLSessionTask找到对应的Request。
/// A type that maintains a two way, one to one map of `URLSessionTask`s to `Request`s.
struct RequestTaskMap {
    //task的状态, 用来决定是否释放映射(task是否完成, task是否获取到请求指标)
    private typealias Events = (completed: Bool, metricsGathered: Bool)
    //task到request
    private var tasksToRequests: [URLSessionTask: Request]
    //request到task
    private var requestsToTasks: [Request: URLSessionTask]
    //task的状态
    private var taskEvents: [URLSessionTask: Events]
    //所有的request
    var requests: [Request] {
        Array(tasksToRequests.values)
    }
    //初始化 默认三个字典均为空
    init(tasksToRequests: [URLSessionTask: Request] = [:],
         requestsToTasks: [Request: URLSessionTask] = [:],
         taskEvents: [URLSessionTask: (completed: Bool, metricsGathered: Bool)] = [:]) {
        self.tasksToRequests = tasksToRequests
        self.requestsToTasks = requestsToTasks
        self.taskEvents = taskEvents
    }
    //角标存取task
    subscript(_ request: Request) -> URLSessionTask? {
        get { requestsToTasks[request] }
        set {
            guard let newValue = newValue else {
                guard let task = requestsToTasks[request] else {
                    //如果新值为空, 表示删除映射, 检测下是否存在映射关系, 不存在就报错
                    fatalError("RequestTaskMap consistency error: no task corresponding to request found.")
                }

                requestsToTasks.removeValue(forKey: request)
                tasksToRequests.removeValue(forKey: task)
                taskEvents.removeValue(forKey: task)

                return
            }
            //保存新的task
            requestsToTasks[request] = newValue
            tasksToRequests[newValue] = request
            taskEvents[newValue] = (completed: false, metricsGathered: false)
        }
    }
    //角标存取request
    subscript(_ task: URLSessionTask) -> Request? {
        get { tasksToRequests[task] }
        set {
            guard let newValue = newValue else {
                guard let request = tasksToRequests[task] else {
                    fatalError("RequestTaskMap consistency error: no request corresponding to task found.")
                }

                tasksToRequests.removeValue(forKey: task)
                requestsToTasks.removeValue(forKey: request)
                taskEvents.removeValue(forKey: task)

                return
            }

            tasksToRequests[task] = newValue
            requestsToTasks[newValue] = task
            taskEvents[task] = (completed: false, metricsGathered: false)
        }
    }
    //映射个数, 做了两个字典个数判等
    var count: Int {
        precondition(tasksToRequests.count == requestsToTasks.count,
                     "RequestTaskMap.count invalid, requests.count: \(tasksToRequests.count) != tasks.count: \(requestsToTasks.count)")

        return tasksToRequests.count
    }
    //task状态个数(映射个数, 而且这个属性没有用到)
    var eventCount: Int {
        precondition(taskEvents.count == count, "RequestTaskMap.eventCount invalid, count: \(count) != taskEvents.count: \(taskEvents.count)")

        return taskEvents.count
    }
    //是否为空
    var isEmpty: Bool {
        precondition(tasksToRequests.isEmpty == requestsToTasks.isEmpty,
                     "RequestTaskMap.isEmpty invalid, requests.isEmpty: \(tasksToRequests.isEmpty) != tasks.isEmpty: \(requestsToTasks.isEmpty)")

        return tasksToRequests.isEmpty
    }
    //task状态是否为空(其实就是isEmpty)
    var isEventsEmpty: Bool {
        precondition(taskEvents.isEmpty == isEmpty, "RequestTaskMap.isEventsEmpty invalid, isEmpty: \(isEmpty) != taskEvents.isEmpty: \(taskEvents.isEmpty)")

        return taskEvents.isEmpty
    }
    //在Session收到task获取到请求指标完成后, 会来判断下task是否完全完成(请求完成,且获取指标完成),并更新taskEvents的状态 全部完成之后, 会删除映射关系, Session才会去执行请求完成的相关回调, 该方法返回的值为是否删除了映射关系
    mutating func disassociateIfNecessaryAfterGatheringMetricsForTask(_ task: URLSessionTask) -> Bool {
        guard let events = taskEvents[task] else {
            fatalError("RequestTaskMap consistency error: no events corresponding to task found.")
        }

        switch (events.completed, events.metricsGathered) {
        case (_, true): fatalError("RequestTaskMap consistency error: duplicate metricsGatheredForTask call.")
        case (false, false): taskEvents[task] = (completed: false, metricsGathered: true); return false
        case (true, false): self[task] = nil; return true
        }
    }
    //在Session收到task的didComplete回调之后, 来判断下task是:1.直接完成,2.接着去获取请求指标. 并更新状态, 返回是否删除映射关系
    mutating func disassociateIfNecessaryAfterCompletingTask(_ task: URLSessionTask) -> Bool {
        guard let events = taskEvents[task] else {
            fatalError("RequestTaskMap consistency error: no events corresponding to task found.")
        }

        switch (events.completed, events.metricsGathered) {
        case (true, _): fatalError("RequestTaskMap consistency error: duplicate completionReceivedForTask call.")
        ///Linux下请求不会获取指标, 所以完成之后可以直接删除映射
        #if os(Linux) // Linux doesn't gather metrics, so unconditionally remove the reference and return true.
        default: self[task] = nil; return true
        #else
        case (false, false):
            if #available(macOS 10.12, iOS 10, watchOS 7, tvOS 10, *) {
                taskEvents[task] = (completed: true, metricsGathered: false); return false
            } else {
                // watchOS < 7 doesn't gather metrics, so unconditionally remove the reference and return true.
                //watchOS 7以下也不会获取指标, 所以直接删除映射并返回true
                self[task] = nil; return true
            }
        case (false, true):
            self[task] = nil; return true
        #endif
        }
    }
}
