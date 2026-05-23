import FileProvider
import Foundation
import FloppyCore

enum FloppyFileProviderErrorMapper {
    static func fileProviderError(for error: Error) -> Error {
        if let fileProviderError = error as? NSFileProviderError {
            return fileProviderError
        }

        if let apiError = error as? FloppyAPIError {
            return fileProviderError(for: apiError)
        }

        if (error as NSError).domain == NSURLErrorDomain {
            return NSFileProviderError(.serverUnreachable)
        }

        return error
    }

    static func recoveryState(for error: Error) -> FloppyFinderSyncState {
        if let apiError = error as? FloppyAPIError {
            switch apiError {
            case .missingToken:
                return .authNeeded
            case .httpStatus(let status, _):
                switch status {
                case 401, 403:
                    return .authNeeded
                case 409, 428:
                    return .conflict
                case 410:
                    return .repairNeeded
                case 429:
                    return .queued
                case 507:
                    return .storageBlocked
                case 500...599:
                    return .offline
                default:
                    return .repairNeeded
                }
            default:
                return .repairNeeded
            }
        }

        if (error as NSError).domain == NSURLErrorDomain {
            return .offline
        }

        return .repairNeeded
    }

    private static func fileProviderError(for apiError: FloppyAPIError) -> Error {
        switch apiError {
        case .missingToken:
            return NSFileProviderError(.notAuthenticated)
        case .httpStatus(let status, _):
            switch status {
            case 401, 403:
                return NSFileProviderError(.notAuthenticated)
            case 404:
                return NSFileProviderError(.noSuchItem)
            case 409, 428, 429, 507:
                return NSFileProviderError(.cannotSynchronize)
            case 410:
                return NSFileProviderError(.syncAnchorExpired)
            case 500...599:
                return NSFileProviderError(.serverUnreachable)
            default:
                return NSFileProviderError(.cannotSynchronize)
            }
        default:
            return NSFileProviderError(.cannotSynchronize)
        }
    }
}
