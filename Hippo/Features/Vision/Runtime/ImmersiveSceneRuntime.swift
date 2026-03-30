

import Foundation
import os.log
import RealityKit
import SwiftUI

@MainActor
@Observable
final class ImmersiveSceneRuntime {
    // MARK: - Logger

    private let logger = Logger(subsystem: "com.television.hippo", category: "ImmersiveSceneRuntime")

    public init() {}

    // MARK: - State

    private var topAnchor: AnchorEntity?

    // MARK: - 3D model 들이 추가될 루트 엔티티

    var sceneRoot: Entity?
    var hudRoot: Entity?

    // MARK: - Setup

    var selectedEntity: Entity?
    private var eventSubscription: EventSubscription?

    /// 배치된 3D 모델 URL 목록 (설정 복귀 시 복원용)
    private var placedModelURLs: [URL] = []

    private let placementService: EntityPlacementService = .init()

    // RealityView 의 content 관리
    func setupScene(in content: RealityViewContent, attachments: RealityViewAttachments) {
        let headAnchor = AnchorEntity(.head)
        content.add(headAnchor)
        topAnchor = headAnchor

        let hudRoot = Entity()
        hudRoot.position = [0, -0.2, -1.0] // 처음엔 정면
        headAnchor.addChild(hudRoot)
        self.hudRoot = hudRoot

        // Main toggle button (original position - center)
        if let topButton = attachments.entity(for: AttachmentIDs.topToggleButton) {
            topButton.components.set([
                InputTargetComponent(),
                HoverEffectComponent(),
            ])
            hudRoot.addChild(topButton)
        }

        var voiceButtonEntity: Entity?

        // Test voice button (bottom-left corner, for testing only)
        if let voiceControlButton = attachments.entity(for: AttachmentIDs.voiceTriggerButton) {
            voiceControlButton.position = [-0.25, -0.015, 0] // Left of topButton
            voiceControlButton.components.set(OpacityComponent(opacity: 0.0))
            hudRoot.addChild(voiceControlButton)
            voiceButtonEntity = voiceControlButton
        }

        topAnchor = headAnchor

        // 3D 모델들의 월드 앵커의 부모
        let rootEntity = Entity()
        rootEntity.name = "SceneRoot"
        content.add(rootEntity)
        sceneRoot = rootEntity

        // 마지막 조작 Entity 정보 저장
        eventSubscription = content.subscribe(to: ManipulationEvents.WillBegin.self) { event in
            if let previousSelection = self.selectedEntity {
                previousSelection.name = ""
            }
            event.entity.name = "selected"
            self.selectedEntity = event.entity
        }

        // 버튼 이동 애니메이션
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            var targetTransform = hudRoot.transform
            targetTransform.translation = SIMD3<Float>(0, 0.2, -1.0)

            hudRoot.move(
                to: targetTransform,
                relativeTo: headAnchor,
                duration: 1.5,
                timingFunction: .easeInOut
            )

            try? await Task.sleep(for: .seconds(1.5))

            if let voiceButton = voiceButtonEntity {
                for opacity in stride(from: 0.0, through: 1.0, by: 0.05) {
                    voiceButton.components.set(OpacityComponent(opacity: Float(opacity)))
                    try? await Task.sleep(for: .milliseconds(30))
                }
                voiceButton.components.set(OpacityComponent(opacity: 1.0))
            }
        }
    }

    func placeEntity(url: URL) async {
        guard let sceneRoot = sceneRoot else {
            logger.error("Scene root is not yet set up.")
            return
        }

        let anchor = placementService.placeAnchorInFront()
        sceneRoot.addChild(anchor)

        do {
            selectedEntity = try await placementService.attach(url: url, to: anchor)
            placedModelURLs.append(url)
            logger.debug("Entity from URL '\(url.lastPathComponent)' placed successfully.")
        } catch {
            logger.error("Failed to attach entity from URL: \(error)")
            anchor.removeFromParent()
        }
    }

    /// 이전에 배치된 3D 모델들을 복원
    func restorePlacedModels() async {
        guard let sceneRoot = sceneRoot, !placedModelURLs.isEmpty else { return }
        logger.debug("Restoring \(self.placedModelURLs.count) placed models...")

        for url in placedModelURLs {
            let anchor = placementService.placeAnchorInFront()
            sceneRoot.addChild(anchor)
            do {
                selectedEntity = try await placementService.attach(url: url, to: anchor)
                logger.debug("Restored: \(url.lastPathComponent)")
            } catch {
                logger.error("Failed to restore: \(url.lastPathComponent)")
                anchor.removeFromParent()
            }
        }
    }

    func deleteSelectedEntity() async {
        guard let entity = selectedEntity else {
            logger.warning("Delete requested, but no entity is selected.")
            return
        }

        await placementService.detach(entity: entity)
        selectedEntity = nil

        logger.debug("Selected entity deleted and selection cleared.")
    }

    func start() {
        logger.debug("🐛 ImmersiveSceneRuntime started")
        ARSessionController.shared.runARSession()
    }

    func stop() {
        logger.debug("ImmersiveSceneRuntime stopped")
        // NOTE: AR session과 topAnchor를 유지해야 3D 모델이 보존됨
        // stopARSession()을 호출하면 AR 앵커가 무효화되어 배치된 모델이 사라짐
        // AR session은 ImmersiveSpace가 dismiss될 때 자동 정리됨
    }
}
