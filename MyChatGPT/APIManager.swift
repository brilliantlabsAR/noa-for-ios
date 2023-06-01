//
//  APIManager.swift
//  SampleAlamofire
//
//  Created by Rajesh Roy on 25/02/20.
//  Copyright © 2020 Sk Azad. All rights reserved.
//

import Alamofire
import SwiftyJSON
import UIKit
let strMimeType = "image/png"
class APIManager {
    
    static func post(urlString strUrl: String, withParams params: [String: Any]? = nil, andHeaders header: [String: Any]? = nil, onCompletion: @escaping (_ responseModel: ResponseModel) -> Void)
    {
        let headerTemp = getHttpHeader(header: header)
        
        AF.request(URL(string: strUrl)!, method: .post, parameters: params, encoding: URLEncoding.default, headers: headerTemp).responseJSON { response in
                
                self.handleResponse(response: response) { responseM in
                    let responseMTemp = responseM
                    responseMTemp.strUrl = strUrl
                    
                    onCompletion(responseMTemp)
                }
            }
    }
    
    static func put(urlString strUrl: String, withParams params: [String: Any]? = nil, andHeaders header: [String: Any]? = nil, onCompletion: @escaping (_ responseModel: ResponseModel) -> Void)
    {
        let headerTemp = getHttpHeader(header: header)
        
        AF.request(URL(string: strUrl)!, method: .put, parameters: params, encoding: JSONEncoding.default, headers: headerTemp).responseJSON { response in
                
                self.handleResponse(response: response) { responseM in
                    let responseMTemp = responseM
                    responseMTemp.strUrl = strUrl
                    
                    onCompletion(responseMTemp)
                }
            }
    }
    static func delete(urlString strUrl: String, withParams params: [String: Any]? = nil, andHeaders header: [String: Any]? = nil, onCompletion: @escaping (_ responseModel: ResponseModel) -> Void)
    {
        let headerTemp = getHttpHeader(header: header)
        
        AF.request(URL(string: strUrl)!, method: .delete, parameters: params, encoding: URLEncoding.httpBody, headers: headerTemp).responseJSON { response in
                
                self.handleResponse(response: response) { responseM in
                    let responseMTemp = responseM
                    responseMTemp.strUrl = strUrl
                    
                    onCompletion(responseMTemp)
                }
            }
    }
    
    static func get(urlString strUrl: String, withParams params: [String: Any]? = nil, andHeaders header: [String: Any]? = nil, onCompletion: @escaping (_ responseModel: ResponseModel) -> Void)
    {
        let headerTemp = getHttpHeader(header: header)
        
        AF.request(URL(string: strUrl)!, method: .get, parameters: params, encoding: URLEncoding.default, headers: headerTemp).responseJSON { response in
                
                self.handleResponse(response: response) { responseM in
                    let responseMTemp = responseM
                    responseMTemp.strUrl = strUrl
                    
                    onCompletion(responseMTemp)
                }
            }
    }

    static func patch(urlString strUrl: String, withParams params: [String: Any]? = nil, andHeaders header: [String: Any]? = nil, onCompletion: @escaping (_ responseModel: ResponseModel) -> Void)
    {
        let headerTemp = getHttpHeader(header: header)
        
        AF.request(URL(string: strUrl)!, method: .patch, parameters: params, encoding: URLEncoding.default, headers: headerTemp).responseJSON { response in
                
                self.handleResponse(response: response) { responseM in
                    let responseMTemp = responseM
                    responseMTemp.strUrl = strUrl
                    
                    onCompletion(responseMTemp)
                }
            }
    }
    
    static func postMultipartData(urlString strUrl: String, withParams params: [String: Any]? = nil, imageFile image: UIImage, strImageName: String = "file", andHeaders header: [String: Any]? = nil, onCompletion: @escaping (_ responseModel: ResponseModel) -> Void)
    {
        let headerTemp = getHttpHeader(header: header)
        
        AF.upload(multipartFormData: { multipartFormData in
            if let imageData = image.jpegData(compressionQuality: 0.75) {
                multipartFormData.append(imageData, withName: strImageName, fileName: "file.jpeg", mimeType: strMimeType)
            }
            
            if params != nil {
                for (key, value) in params! {
                    multipartFormData.append(Data("\(value)".utf8), withName: key)
                }
            }
        }, to: URL(string: strUrl)!, method: .post, headers: headerTemp).responseJSON { response in
            self.handleResponse(response: response) { responseM in
                let responseMTemp = responseM
                responseMTemp.strUrl = strUrl
                    
                onCompletion(responseMTemp)
            }
        }
    }
    
    static func postMultipartDataWithMultipleImage(urlString strUrl: String, withParams params: [String: Any]? = nil, imageFiles arrImages: [UIImage], arrImageNames: [String], andHeaders header: [String: Any]? = nil, onCompletion: @escaping (_ responseModel: ResponseModel) -> Void)
    {
        let headerTemp = getHttpHeader(header: header)
        
        AF.upload(multipartFormData: { multipartFormData in
            for index in 0 ... (arrImages.count - 1) {
                let strName = arrImageNames[index]
                let image = arrImages[index]
                let strFileName = strName.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
                
                if let imageData = image.jpegData(compressionQuality: 1) {
                    multipartFormData.append(imageData, withName: strName, fileName: "\(strFileName).jpeg", mimeType: strMimeType)
                }
            }
            
            if params != nil {
                for (key, value) in params! {
                    multipartFormData.append(Data("\(value)".utf8), withName: key)
                }
            }
        }, to: URL(string: strUrl)!, method: .post, headers: headerTemp).responseJSON { response in
            self.handleResponse(response: response) { responseM in
                let responseMTemp = responseM
                responseMTemp.strUrl = strUrl
                    
                onCompletion(responseMTemp)
            }
        }
    }
    
    static func postMultipartWithMultipleData(urlString strUrl: String, withParams params: [String: Any]? = nil, datas arrDatas: [Data], names arrNames: [String], mimeTypes arrMimes: [String], andHeaders header: [String: Any]? = nil, onCompletion: @escaping (_ responseModel: ResponseModel) -> Void)
    {
        let headerTemp = getHttpHeader(header: header)
        
        AF.upload(multipartFormData: { multipartFormData in
            for index in 0 ..< arrNames.count {
                let strName = arrNames[index]
                let data = arrDatas[index]
                let mime = arrMimes[index]
                let arr = mime.components(separatedBy: "/")
                
                let strFileName = strName.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
                
                multipartFormData.append(data, withName: strName, fileName: "\(strFileName).\(arr.last ?? "")", mimeType: mime)
            }
            
            for (key, value) in params! {
                multipartFormData.append(Data("\(value)".utf8), withName: key)
            }
        }, to: URL(string: strUrl)!, method: .post, headers: headerTemp).responseJSON { response in
            self.handleResponse(response: response) { responseM in
                let responseMTemp = responseM
                responseMTemp.strUrl = strUrl
                    
                onCompletion(responseMTemp)
            }
        }
    }

    static func handleResponse(response: AFDataResponse<Any>, onCompletion: @escaping (_ responseModel: ResponseModel) -> Void)
    {
        let responseM = ResponseModel()
        
        switch response.result {
        case .success:
            do {
                let json = try JSON(data: response.data ?? Data())
                responseM.completeJsonResp = json
                responseM.rawData = response.data!
                
                responseM.intResCode = json["status"].intValue
                responseM.strResMsg = json["message"].stringValue
                responseM.strAuth = json["auth"].stringValue
                
                responseM.jsonResp = json["data"]
                responseM.isSuccess = json["success"].boolValue
            } catch {}
            
            // responseM.isSuccess = responseM.strResMsg == "success"
            
        case .failure(let error):
            let message: String
            if let httpStatusCode = response.response?.statusCode {
                message = "Error code : \(httpStatusCode)"
            } else {
                message = error.localizedDescription
            }
            responseM.strResMsg = message
            print("APIManager failure block \n\(message)\n\n")
        }
        
        if responseM.strResMsg.lowercased().contains("urlsessiontask") {
            responseM.strResMsg = "Please check your internet connection."
        }
        
        onCompletion(responseM)
    }
    
    private static func getHttpHeader(header: [String: Any]? = nil) -> HTTPHeaders {
        var headerTemp = HTTPHeaders()
        // Taking the header here as it's mandatory for all API except Registration/Login
        let headerOne = getHeader()
        if header != nil {
            for key in headerOne.keys {
                if key.count > 1, let value = headerOne[key] {
                    let h = HTTPHeader(name: key, value: "\(value)")
                    headerTemp.add(h)
                }
            }
        }
        return headerTemp
    }
}
