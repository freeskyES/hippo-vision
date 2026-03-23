//
//  SyncMonitor.swift
//  Hippo
//
//  Created by 김현기 on 11/21/25.
//

import CoreData
import Observation
import SwiftUI

@Observable
public class SyncMonitor {
    var isSyncing = false
    var dataDidChange = false // 데이터 변경 플래그

    init() {
        // 1. 네트워크 상태 모니터링 (기존 코드 유지 - 로딩바 표시용)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didReceiveCloudKitEvent(_:)),
            name: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil
        )
    }

    // 네트워크 이벤트 처리 (인디케이터용 + 상세 로깅)
    @objc private func didReceiveCloudKitEvent(_ notification: Notification) {
        guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else { return }

        Task { @MainActor in
            let eventTypeName: String
            switch event.type {
            case .import: eventTypeName = "[CK-Import]"
            case .export: eventTypeName = "[CK-Export]"
            case .setup:  eventTypeName = "[CK-Setup]"
            @unknown default: eventTypeName = "[CK-Unknown]"
            }

            if event.endDate == nil {
                // 시작
                print("\(eventTypeName) Sync 시작 | store: \(event.storeIdentifier)")
                self.isSyncing = true
            } else {
                // 종료
                if let error = event.error {
                    let nsError = error as NSError
                    print("\(eventTypeName) Sync 실패")
                    print("  error: \(error.localizedDescription)")
                    print("  domain: \(nsError.domain), code: \(nsError.code)")
                    if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                        print("  underlying: \(underlying.domain) / \(underlying.code) / \(underlying.localizedDescription)")
                    }
                    if let partialErrors = nsError.userInfo["CKPartialErrors"] as? [AnyHashable: Any] {
                        print("  partialErrors: \(partialErrors)")
                    }
                } else {
                    print("\(eventTypeName) Sync 완료 | store: \(event.storeIdentifier)")

                    if event.type == .import {
                        self.dataDidChange = true
                    }
                }
                self.isSyncing = false
            }
        }
    }

    func resetDataChangeFlag() {
        dataDidChange = false
    }
}
