import DailyCore
import XCTest

@testable import DailyWorkspace

@MainActor
final class TaskStoreTests: XCTestCase {
    func testAddThatCannotBeSavedIsRolledBackAndReported() {
        let persistence = InMemoryTaskPersistence()
        persistence.failSaves = true
        let store = TaskStore(makePersistence: { persistence })

        XCTAssertFalse(store.add(title: "Call Sam", due: nil))

        XCTAssertTrue(store.tasks.items.isEmpty)
        XCTAssertEqual(store.message, "Tasks could not be saved: disk full")
    }

    func testUndoDeletePersistsTheRestoredTask() throws {
        let persistence = InMemoryTaskPersistence()
        let store = TaskStore(makePersistence: { persistence })
        store.add(title: "Water plants", due: nil)
        let task = try XCTUnwrap(store.tasks.items.first)

        store.delete(task)
        XCTAssertTrue(persistence.stored.items.isEmpty)
        store.undoDelete()

        XCTAssertEqual(persistence.stored.items.map(\.id), [task.id])
        XCTAssertNil(store.recentlyDeleted)
    }

    func testUnavailableStorageRefusesAddsAndSaysWhy() {
        let store = TaskStore(makePersistence: { throw TestFailure("no Application Support") })
        XCTAssertEqual(store.message, "Tasks could not be loaded: no Application Support")

        XCTAssertFalse(store.add(title: "Lost on quit", due: nil))

        XCTAssertTrue(store.tasks.items.isEmpty)
        XCTAssertEqual(store.message, "Tasks are not being saved: storage is unavailable.")
    }

    func testToggleThatCannotBeSavedIsRolledBack() throws {
        let persistence = InMemoryTaskPersistence()
        let store = TaskStore(makePersistence: { persistence })
        store.add(title: "Pay rent", due: nil)
        let task = try XCTUnwrap(store.tasks.items.first)
        persistence.failSaves = true

        store.toggle(task)

        XCTAssertFalse(try XCTUnwrap(store.tasks.items.first).isCompleted)
        XCTAssertEqual(store.message, "Tasks could not be saved: disk full")
    }

    func testDeleteThatCannotBeSavedKeepsTheTaskAndOffersNoUndo() throws {
        let persistence = InMemoryTaskPersistence()
        let store = TaskStore(makePersistence: { persistence })
        store.add(title: "Pay rent", due: nil)
        let task = try XCTUnwrap(store.tasks.items.first)
        persistence.failSaves = true

        store.delete(task)

        XCTAssertEqual(store.tasks.items.map(\.id), [task.id])
        XCTAssertNil(store.recentlyDeleted)
    }
}
