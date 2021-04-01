//
//  ViewController.swift
//  AlamofireRequest
//
//  Created by chao on 2021/3/26.
//

import UIKit
import Alamofire

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.

    }
    
    @IBAction func GetPostClick(_ sender: UIButton) {
        
        let urlString = "http:baidu.com?page=1"
        
//        AF.request(<#T##convertible: URLConvertible##URLConvertible#>)
//        AF.request(<#T##convertible: URLRequestConvertible##URLRequestConvertible#>)
//        AF.request(<#T##convertible: URLRequestConvertible##URLRequestConvertible#>, interceptor: <#T##RequestInterceptor?#>)
//        AF.request(<#T##convertible: URLConvertible##URLConvertible#>, method: <#T##HTTPMethod#>, parameters: <#T##Encodable?#>, encoder: <#T##ParameterEncoder#>, headers: <#T##HTTPHeaders?#>, interceptor: <#T##RequestInterceptor?#>, requestModifier: <#T##Session.RequestModifier?##Session.RequestModifier?##(inout URLRequest) throws -> Void#>)
//        AF.request(urlString, method: .get, parameters: ["siteId":"100000"], encoding:JSONEncoding.default , headers: nil, interceptor: nil, requestModifier: nil).responseJSON { (<#AFDataResponse<Any>#>) in
//            <#code#>
//        }
        
        
        let request = AF.request(urlString).responseJSON { (resp) in
            print(resp)
            
        }
    }
    

    
}

