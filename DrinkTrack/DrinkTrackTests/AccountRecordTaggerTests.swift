import XCTest
import CoreData
@testable import DrinkTrack

final class AccountRecordTaggerTests: XCTestCase {
    private var persistence: PersistenceController!
    private var context: NSManagedObjectContext!

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        context = persistence.viewContext
        CurrentAccountContext.accountID = nil
    }

    override func tearDown() {
        CurrentAccountContext.accountID = nil
        context = nil
        persistence = nil
        super.tearDown()
    }

    func testAttachTagsOnlyUnownedDrinkRowsAndLeavesHealthPointsAlone() throws {
        let session = makeSession(accountID: nil)
        let ownedSession = makeSession(accountID: "already-other")
        let log = makeLog(in: session, accountID: nil)
        let mark = makePlaceMark(accountID: nil)
        let health = makeHealthPoint(in: session)

        let tagged = try AccountRecordTagger.attachUnownedRecords(accountID: "user-a", context: context)
        XCTAssertEqual(tagged, 3)

        XCTAssertEqual(session.value(forKey: "accountId") as? String, "user-a")
        XCTAssertEqual(log.value(forKey: "accountId") as? String, "user-a")
        XCTAssertEqual(mark.value(forKey: "accountId") as? String, "user-a")
        XCTAssertEqual(ownedSession.value(forKey: "accountId") as? String, "already-other")
        XCTAssertNil(health.entity.attributesByName["accountId"])
    }

    func testApplyCurrentAccountOnNewRowsThenStopsAfterClearingContext() {
        CurrentAccountContext.accountID = "user-b"
        let session = DrinkSessionEntity(context: context)
        session.id = UUID()
        session.startedAt = Date()
        session.status = "active"
        AccountRecordTagger.applyCurrentAccount(to: session)
        XCTAssertEqual(session.value(forKey: "accountId") as? String, "user-b")

        CurrentAccountContext.accountID = nil
        let later = DrinkSessionEntity(context: context)
        later.id = UUID()
        later.startedAt = Date()
        later.status = "active"
        AccountRecordTagger.applyCurrentAccount(to: later)
        XCTAssertNil(later.value(forKey: "accountId"))
        // Previously tagged history stays put.
        XCTAssertEqual(session.value(forKey: "accountId") as? String, "user-b")
    }

    private func makeSession(accountID: String?) -> DrinkSessionEntity {
        let session = DrinkSessionEntity(context: context)
        session.id = UUID()
        session.startedAt = Date()
        session.status = "archived"
        if let accountID {
            session.setValue(accountID, forKey: "accountId")
        }
        return session
    }

    private func makeLog(in session: DrinkSessionEntity, accountID: String?) -> DrinkLogEntity {
        let log = DrinkLogEntity(context: context)
        log.id = UUID()
        log.category = DrinkCategory.beer.rawValue
        log.volumeMl = 330
        log.standardDrinks = 1
        log.timestamp = Date()
        log.session = session
        if let accountID {
            log.setValue(accountID, forKey: "accountId")
        }
        return log
    }

    private func makePlaceMark(accountID: String?) -> NSManagedObject {
        let entity = NSEntityDescription.entity(forEntityName: "PlaceMark", in: context)!
        let mark = NSManagedObject(entity: entity, insertInto: context)
        mark.setValue(UUID(), forKey: "id")
        mark.setValue("家里", forKey: "name")
        mark.setValue(31.2, forKey: "latitude")
        mark.setValue(121.4, forKey: "longitude")
        mark.setValue(Date(), forKey: "markedAt")
        if let accountID {
            mark.setValue(accountID, forKey: "accountId")
        }
        return mark
    }

    private func makeHealthPoint(in session: DrinkSessionEntity) -> HealthDataPointEntity {
        let point = HealthDataPointEntity(context: context)
        point.id = UUID()
        point.timestamp = Date()
        point.setValue(72.0, forKey: "heartRate")
        point.session = session
        return point
    }
}
