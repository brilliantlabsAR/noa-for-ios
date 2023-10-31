//
//  AIError.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 5/24/23.
//

import Foundation

public enum AIError: Error {
    case urlAuthenticationFailed
    case responsePayloadParseError
    case clientSideNetworkError(error: Error?)
    case apiError(message: String)
    case dataFormatError(message: String)
    case internalError(message: String)
}

extension AIError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .clientSideNetworkError(let error):
            if let error = error {
                return "Network request failed: \(error.localizedDescription)"
            } else {
                return "Network request failed."
            }
        case .responsePayloadParseError:
            return "Unable to parse response from server."
        case .apiError(let message):
            return message
        case .urlAuthenticationFailed:
            return "API URL authentication failed."
        case .dataFormatError(let message):
            return message
        case .internalError(let message):
            return message
        }
    }
}
