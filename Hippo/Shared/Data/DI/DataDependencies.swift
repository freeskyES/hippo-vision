import Dependencies
import SwiftData
import Foundation

// MARK: - Data Layer Dependencies

extension DependencyValues {
  // MARK: - SwiftData Container

  /// SwiftData ModelContainer for Patient domain
  public var patientModelContainer: ModelContainer {
    get { self[PatientModelContainerKey.self] }
    set { self[PatientModelContainerKey.self] = newValue }
  }

  // MARK: - Local Data Sources

  /// Patient local data source (SwiftData SSOT)
  public var patientLocalDataSource: PatientLocalDataSource {
    get { self[PatientLocalDataSourceKey.self] }
    set { self[PatientLocalDataSourceKey.self] = newValue }
  }

  // MARK: - Remote Data Sources

  /// Patient remote data source (CloudKit)
  public var patientRemoteDataSource: PatientRemoteDataSource {
    get { self[PatientRemoteDataSourceKey.self] }
    set { self[PatientRemoteDataSourceKey.self] = newValue }
  }

  // MARK: - Repositories

  /// Patient repository (offline-first)
  public var patientRepository: PatientRepository {
    get { self[PatientRepositoryKey.self] }
    set { self[PatientRepositoryKey.self] = newValue }
  }

  /// Operation repository (facade for operation-centric operations)
  public var operationRepository: OperationRepository {
    get { self[OperationRepositoryKey.self] }
    set { self[OperationRepositoryKey.self] = newValue }
  }
  
  // MARK: - Sync Monitor
  
  /// CloudKit sync monitor
  public var syncMonitor: SyncMonitor {
    get { self[SyncMonitorKey.self] }
    set { self[SyncMonitorKey.self] = newValue }
  }

}

// MARK: - Dependency Keys

private enum PatientModelContainerKey: DependencyKey {
  @MainActor
  static let liveValue: ModelContainer = {
    do {
      let schema = Schema([
        SDPatient.self,
        SDOperation.self,
        SDOperationAsset.self,
        SDOperationRecording.self
      ])

      let modelConfiguration = ModelConfiguration(
        schema: schema,
        isStoredInMemoryOnly: false,
        cloudKitDatabase: .none // cloudKitDatabase: .private("iCloud.com.television.hippo")
      )

      let container = try ModelContainer(
        for: schema,
        configurations: [modelConfiguration]
      )

      // MARK: - 🧪 Demo Data Seeding (DELETE THIS BLOCK WHEN NO LONGER NEEDED)
      #if DEBUG
      let mainContext = container.mainContext
      Task { @MainActor in
        seedDemoDataIfEmpty(context: mainContext)
      }
      #endif

      return container
    } catch {
      // If migration fails during development, delete the store and try again
      print("⚠️ ModelContainer creation failed: \(error)")
      print("🗑️ Attempting to delete and recreate the database...")

      do {
        // Delete the existing store files
        let fileManager = FileManager.default
        let appSupportURL = try fileManager.url(
          for: .applicationSupportDirectory,
          in: .userDomainMask,
          appropriateFor: nil,
          create: true
        )

        let storeURL = appSupportURL.appendingPathComponent("default.store")
        let storeFiles = [
          storeURL.path,
          storeURL.path + "-shm",
          storeURL.path + "-wal"
        ]

        for file in storeFiles {
          if fileManager.fileExists(atPath: file) {
            try? fileManager.removeItem(atPath: file)
            print("🗑️ Deleted: \(file)")
          }
        }

        // Try creating container again with fresh database
        let schema = Schema([
          SDPatient.self,
          SDOperation.self,
          SDOperationAsset.self,
          SDOperationRecording.self
        ])

        let modelConfiguration = ModelConfiguration(
          schema: schema,
          isStoredInMemoryOnly: false,
          cloudKitDatabase: .none // cloudKitDatabase: .private("iCloud.com.television.hippo")
        )

        return try ModelContainer(
          for: schema,
          configurations: [modelConfiguration]
        )
      } catch {
        fatalError("Failed to create SwiftData ModelContainer even after cleanup: \(error)")
      }
    }
  }()

  @MainActor
  static let testValue: ModelContainer = {
    do {
      let schema = Schema([
        SDPatient.self,
        SDOperation.self,
        SDOperationAsset.self,
        SDOperationRecording.self
      ])

      let modelConfiguration = ModelConfiguration(
        schema: schema,
        isStoredInMemoryOnly: true  // In-memory for tests
      )

      return try ModelContainer(
        for: schema,
        configurations: [modelConfiguration]
      )
    } catch {
      fatalError("Failed to create test ModelContainer: \(error)")
    }
  }()
}

private enum PatientLocalDataSourceKey: DependencyKey {
  @MainActor
  static let liveValue: PatientLocalDataSource = {
    @Dependency(\.patientModelContainer) var container
      return PatientLocalDataSourceSwiftData(context: container.mainContext)
  }()

  @MainActor
  static let testValue: PatientLocalDataSource = {
    @Dependency(\.patientModelContainer) var container
      return PatientLocalDataSourceSwiftData(context: container.mainContext)
  }()
}

private enum PatientRemoteDataSourceKey: DependencyKey {
  static let liveValue: PatientRemoteDataSource = PatientRemoteDataSourceCloudKit()

  // Mock for testing
  static let testValue: PatientRemoteDataSource = PatientRemoteDataSourceMock()
}

private enum PatientRepositoryKey: DependencyKey {
  static let liveValue: PatientRepository = {
    @Dependency(\.patientLocalDataSource) var localDataSource
    @Dependency(\.patientRemoteDataSource) var remoteDataSource

    return PatientRepositoryImpl(
      localDataSource: localDataSource,
      remoteDataSource: remoteDataSource
    )
  }()

  static let testValue: PatientRepository = {
    @Dependency(\.patientLocalDataSource) var localDataSource
    @Dependency(\.patientRemoteDataSource) var remoteDataSource

    return PatientRepositoryImpl(
      localDataSource: localDataSource,
      remoteDataSource: remoteDataSource
    )
  }()
}

private enum OperationRepositoryKey: DependencyKey {
  static let liveValue: OperationRepository = {
    @Dependency(\.patientRepository) var patientRepository

    return OperationRepositoryImpl(patientRepository: patientRepository)
  }()

  static let testValue: OperationRepository = {
    @Dependency(\.patientRepository) var patientRepository

    return OperationRepositoryImpl(patientRepository: patientRepository)
  }()
}

private enum SyncMonitorKey: DependencyKey {
  @MainActor
  static let liveValue: SyncMonitor = SyncMonitor()
  
  @MainActor
  static let testValue: SyncMonitor = SyncMonitor()
}


// MARK: - Mock Remote Data Source (for testing)

private final class PatientRemoteDataSourceMock: PatientRemoteDataSource {
  func pullAll() async throws -> [Patient] {
    return []
  }

  func push(_ patient: Patient) async throws {
    // Mock: do nothing
  }

  func remove(id: String) async throws {
    // Mock: do nothing
  }
}

// MARK: - 🧪 Demo Data Seeding (DELETE THIS ENTIRE SECTION WHEN NO LONGER NEEDED)

#if DEBUG
@MainActor
private func seedDemoDataIfEmpty(context: ModelContext) {
  // 김종득 환자가 있는지 확인 (최신 시딩 기준)
  let patientCheck = FetchDescriptor<SDPatient>(predicate: #Predicate { $0.name == "김종득" })
  let hasLatestSeed = ((try? context.fetchCount(patientCheck)) ?? 0) > 0

  if hasLatestSeed {
    print("Demo data up to date, skipping seed")
    return
  }

  // 기존 데이터가 있으면 전체 삭제 후 재시딩 (환자 구성이 변경됐으므로)
  let assetDescriptor = FetchDescriptor<SDOperationAsset>()
  let assetCount = (try? context.fetchCount(assetDescriptor)) ?? 0
  if assetCount > 0 {
    print("Updating demo data (new patient added)...")
  }

  // 기존 데이터 삭제 (iCloud에서 3D 모델 없이 내려온 데이터 정리)
  let patientDescriptor = FetchDescriptor<SDPatient>()
  if let existingPatients = try? context.fetch(patientDescriptor), !existingPatients.isEmpty {
    print("🌱 Removing \(existingPatients.count) patients without 3D models...")
    existingPatients.forEach { context.delete($0) }
    try? context.save()
  }

  print("🌱 Seeding demo data...")

  let calendar = Calendar(identifier: .gregorian)
  let now = Date()

  let sharedDiagnosis = "간세포암(Hepatocellular carcinoma, HCC) — 2.1 cm 종양"
  let sharedSurgicalSite = "간 S5(5분절), 중앙부"
  let sharedDetails = "동맥기 조영증강 및 지연기 소실(washout) 소견을 보이는 간 S5 종양으로, 중간간정맥(MHV) 인접하나 혈관 침범은 없음. 약 5 mm 안전거리를 확보한 부분 간절제 예정."

  // 3D 모델 에셋 로드
  let modelDataKBA: Data = {
    guard let url = Bundle.main.url(forResource: "KBA_HCC", withExtension: "usdz"),
          let data = try? Data(contentsOf: url) else {
      print("⚠️ KBA_HCC.usdz not found in bundle, skipping 3D model")
      return Data()
    }
    print("🌱 Loaded KBA_HCC.usdz (\(data.count / 1024)KB)")
    return data
  }()

  let modelDataKJD: Data = {
    guard let url = Bundle.main.url(forResource: "KJD_HCC", withExtension: "usdz"),
          let data = try? Data(contentsOf: url) else {
      print("⚠️ KJD_HCC.usdz not found in bundle, skipping 3D model")
      return Data()
    }
    print("🌱 Loaded KJD_HCC.usdz (\(data.count / 1024)KB)")
    return data
  }()

  // 환자 1: 김우빈 (38세, 남) — patientNumber: 1666
  let patient1 = SDPatient(
    id: UUID().uuidString,
    patientNumber: "1666",
    name: "김우빈",
    genderRaw: Gender.male.rawValue,
    birthDate: calendar.date(from: DateComponents(year: 1988, month: 1, day: 1))!,
    createdAt: now,
    updatedAt: now
  )
  let op1 = SDOperation(
    id: UUID().uuidString,
    title: "간 종양 절제",
    diagnosis: sharedDiagnosis,
    surgeon: "오남기",
    surgicalSite: sharedSurgicalSite,
    date: now,
    details: sharedDetails,
    statusRaw: OperationStatus.planned.rawValue
  )
  op1.patient = patient1
  if !modelDataKBA.isEmpty {
    let asset1 = SDOperationAsset(id: UUID().uuidString, originalFileName: "KBA_HCC.usdz", fileData: modelDataKBA)
    asset1.operation = op1
    op1.assets = [asset1]
  }
  patient1.operations = [op1]

  // 환자 2: 김남길 (27세, 남) — patientNumber: 1542
  let patient2 = SDPatient(
    id: UUID().uuidString,
    patientNumber: "1542",
    name: "김남길",
    genderRaw: Gender.male.rawValue,
    birthDate: calendar.date(from: DateComponents(year: 1999, month: 1, day: 1))!,
    createdAt: now,
    updatedAt: now
  )
  let op2 = SDOperation(
    id: UUID().uuidString,
    title: "간 종양 절제",
    diagnosis: sharedDiagnosis,
    surgeon: "오남기",
    surgicalSite: sharedSurgicalSite,
    date: now,
    details: sharedDetails,
    statusRaw: OperationStatus.planned.rawValue
  )
  op2.patient = patient2
  if !modelDataKBA.isEmpty {
    let asset2 = SDOperationAsset(id: UUID().uuidString, originalFileName: "KBA_HCC.usdz", fileData: modelDataKBA)
    asset2.operation = op2
    op2.assets = [asset2]
  }
  patient2.operations = [op2]

  // 환자 3: 이나연 (26세, 여) — patientNumber: 1325
  let patient3 = SDPatient(
    id: UUID().uuidString,
    patientNumber: "1325",
    name: "이나연",
    genderRaw: Gender.female.rawValue,
    birthDate: calendar.date(from: DateComponents(year: 2000, month: 1, day: 1))!,
    createdAt: now,
    updatedAt: now
  )
  let op3 = SDOperation(
    id: UUID().uuidString,
    title: "간 종양 절제",
    diagnosis: sharedDiagnosis,
    surgeon: "오남기",
    surgicalSite: sharedSurgicalSite,
    date: now,
    details: sharedDetails,
    statusRaw: OperationStatus.planned.rawValue
  )
  op3.patient = patient3
  if !modelDataKBA.isEmpty {
    let asset3 = SDOperationAsset(id: UUID().uuidString, originalFileName: "KBA_HCC.usdz", fileData: modelDataKBA)
    asset3.operation = op3
    op3.assets = [asset3]
  }
  patient3.operations = [op3]

  // 환자 4: 김남길 (28세, 남) — patientNumber: 1651
  let patient4 = SDPatient(
    id: UUID().uuidString,
    patientNumber: "1651",
    name: "김남길",
    genderRaw: Gender.male.rawValue,
    birthDate: calendar.date(from: DateComponents(year: 1998, month: 1, day: 1))!,
    createdAt: now,
    updatedAt: now
  )
  let op4 = SDOperation(
    id: UUID().uuidString,
    title: "간 종양 절제",
    diagnosis: sharedDiagnosis,
    surgeon: "오남기",
    surgicalSite: sharedSurgicalSite,
    date: now,
    details: sharedDetails,
    statusRaw: OperationStatus.planned.rawValue
  )
  op4.patient = patient4
  if !modelDataKBA.isEmpty {
    let asset4 = SDOperationAsset(id: UUID().uuidString, originalFileName: "KBA_HCC.usdz", fileData: modelDataKBA)
    asset4.operation = op4
    op4.assets = [asset4]
  }
  patient4.operations = [op4]

  // 환자 5: 김종득 — patientNumber: 1780 (updatedAt을 최신으로 설정하여 리스트 최상단 표시)
  let latestUpdate = now.addingTimeInterval(1)
  let patient5 = SDPatient(
    id: UUID().uuidString,
    patientNumber: "1780",
    name: "김종득",
    genderRaw: Gender.male.rawValue,
    birthDate: calendar.date(from: DateComponents(year: 1965, month: 1, day: 1))!,
    createdAt: latestUpdate,
    updatedAt: latestUpdate
  )
  let op5Date = calendar.startOfDay(for: now)  // 오늘 0시 (정렬 시 가장 앞)
  let op5 = SDOperation(
    id: UUID().uuidString,
    title: "간 종양 절제",
    diagnosis: sharedDiagnosis,
    surgeon: "오남기",
    surgicalSite: sharedSurgicalSite,
    date: op5Date,
    details: sharedDetails,
    statusRaw: OperationStatus.planned.rawValue
  )
  op5.patient = patient5
  if !modelDataKJD.isEmpty {
    let asset5 = SDOperationAsset(id: UUID().uuidString, originalFileName: "KJD_HCC.usdz", fileData: modelDataKJD)
    asset5.operation = op5
    op5.assets = [asset5]
  }
  patient5.operations = [op5]

  for patient in [patient5, patient1, patient2, patient3, patient4] {
    context.insert(patient)
  }

  try? context.save()
  print("Demo data seeded: 5 patients (surgeon: 오남기)")
}
#endif
