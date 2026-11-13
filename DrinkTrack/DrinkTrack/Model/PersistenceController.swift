import CoreData

/// 本地 Core Data 持久化控制器（§6.1：默认本地存储，不上传任何服务器）。
/// iCloud 同步（§6.1 可选 iCloud 同步）在本轮仅做 UI 开关占位，`NSPersistentCloudKitContainer`
/// 的接入留到后续轮次——现在用的是普通 `NSPersistentContainer`，避免在没有真正配置好
/// CloudKit Container / 加密方案前，误让用户以为数据已经在同步。
final class PersistenceController {
    static let shared = PersistenceController()

    /// 用于 SwiftUI Preview 和单元测试的内存态容器，不写磁盘。
    static var preview: PersistenceController {
        let controller = PersistenceController(inMemory: true)
        return controller
    }

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "DrinkTrack")
        if let description = container.persistentStoreDescriptions.first {
            // Lightweight migration: adding optional attributes (e.g. DrinkLog.amountFen)
            // must not wipe an existing on-device store.
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
            if inMemory {
                description.url = URL(fileURLWithPath: "/dev/null")
            }
        }
        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                // 生产环境中应做更友好的降级处理（例如提示用户存储初始化失败）。
                // 这里直接 fatalError 便于开发阶段尽早发现模型/磁盘问题。
                fatalError("Core Data 加载失败: \(error), \(error.userInfo)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    var viewContext: NSManagedObjectContext { container.viewContext }

    func save() {
        let context = viewContext
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            // 同上，生产环境需要更完善的错误上报，这里先打印，不让一次保存失败崩掉整个 App。
            print("保存 Core Data 上下文失败: \(error)")
        }
    }

    /// §6.1 数据一键清除：删除所有实体的本地数据，但不会删除 HealthKit 里的原始数据
    /// （HealthKit 的数据属于用户，由系统管理，App 无权也不应删除）。
    func eraseAllLocalData() throws {
        let entityNames = container.managedObjectModel.entities.compactMap { $0.name }
        for name in entityNames {
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: name)
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
            deleteRequest.resultType = .resultTypeObjectIDs
            let result = try viewContext.execute(deleteRequest) as? NSBatchDeleteResult
            if let objectIDs = result?.result as? [NSManagedObjectID] {
                let changes = [NSDeletedObjectsKey: objectIDs]
                NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [viewContext])
            }
        }
        save()
    }
}
