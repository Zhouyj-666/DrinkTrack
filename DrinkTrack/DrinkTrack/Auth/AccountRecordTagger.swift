import Foundation
import CoreData

/// The account id that new local drink/session/place rows should carry.
/// AuthSession updates this when the user logs in or out. Logged-out use
/// leaves it nil so new rows stay unowned (and fully usable on this device).
enum CurrentAccountContext {
    static var accountID: String?
}

/// Tags on-device drink records with an account id so a later sync has a hook.
/// HealthKit samples are intentionally not tagged or uploaded.
enum AccountRecordTagger {
    static let taggedEntities = ["DrinkSession", "DrinkLog", "PlaceMark"]
    static let accountAttribute = "accountId"

    /// Write the current account id onto a newly created row. No-op when logged out
    /// or when this entity has no accountId attribute (older models / HealthKit rows).
    static func applyCurrentAccount(to object: NSManagedObject) {
        apply(CurrentAccountContext.accountID, to: object)
    }

    static func apply(_ accountID: String?, to object: NSManagedObject) {
        guard let accountID, !accountID.isEmpty else { return }
        guard object.entity.attributesByName[accountAttribute] != nil else { return }
        object.setValue(accountID, forKey: accountAttribute)
    }

    /// On login / register, attach every still-unowned local record to this account.
    /// Rows already tagged with a different account are left alone. History is never deleted.
    @discardableResult
    static func attachUnownedRecords(
        accountID: String,
        context: NSManagedObjectContext
    ) throws -> Int {
        let trimmed = accountID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        var tagged = 0
        for entityName in taggedEntities {
            guard let entity = NSEntityDescription.entity(forEntityName: entityName, in: context),
                  entity.attributesByName[accountAttribute] != nil else {
                continue
            }
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            request.predicate = NSPredicate(format: "%K == nil", accountAttribute)
            let rows = try context.fetch(request)
            for row in rows {
                row.setValue(trimmed, forKey: accountAttribute)
                tagged += 1
            }
        }
        if context.hasChanges {
            try context.save()
        }
        return tagged
    }
}
