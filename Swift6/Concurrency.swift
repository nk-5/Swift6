//
//  Concurrency.swift
//  Swift6
//
//  Created by Keigo Nakagawa on 2025/07/30.
//

import Foundation
import SwiftUI

/*
* Swift Concurrency Checking (SWIFT_STRICT_CONCURRENCY)の状態にも依存する
*   - Minimal: 明示的にSendableを採用している箇所で、Sendable制約とアクター隔離をチェック
*   - Targeted: Minimalに加え、暗黙的にSendableが採用されている箇所でもSendable制約とアクター隔離をチェック
*   - complete: (Swift 6の完全なconcurrencyチェック）モジュール全体を通してSendable制約とアクター隔離をチェック
* refs: https://tech-blog.cluster.mu/entry/2025/07/25
* refs: https://zenn.dev/coconala/articles/407d73903e6f2c
*/


/* ------------------------------------------------------------------------------------------------------------*/
/*
 * Infer Isolated Conformances
 * Noの場合：❌  Conformance of 'HogeViewModel' to protocol 'HogeProtocol' crosses into main actor-isolated code and can cause data races; this is an error in the Swift 6 language mode
 *  HogeProtocolがMainActorでないので、warningが発生する
 *
 * Yesの場合： クラスの isolation から プロトコル準拠の isolation を推論し、エラーが発生しない
 */
class InferIsolatedConformancesDesc {
    struct User {
        let name: String
    }

    // protocolはnonisolation
    protocol HogeProtocol {
        func fetch() -> User
    }

    @MainActor
    class HogeViewModel: HogeProtocol {
        var name: String = ""

        func fetch() -> User {
            .init(name: "hoge")
        }
    }
}

/* ------------------------------------------------------------------------------------------------------------*/
/*
 * nonisolated(nonsending) By Default
 * 呼び出し元のアクターを継承して実行するかどうか
 * Yes（安全側）: デフォルトでnonisolated(nonsending) を付与するので、呼び出し元のisolated domainと同じdomainで実行される
 * No（従来の緩い挙動）: デフォルトでnonisolated(nonsending) を付与しないので呼び出し元とは異なるisolated domainの場合はエラーになる
 * Migrate: Swift 5 互換を保ちつつ、一部に警告を出しながら Yes へ移行していくモード（警告が出るがコンパイルは通る）
 */

struct NonisolatedNonsendingByDefaultView: View {
    let repository = Repository()

    var body: some View {
        EmptyView()
            .task {
                await repository.load() // Yesだとエラーが発生しない
            }
    }
}

class Repository { // Sendable でなくても OK
//    nonisolated(nonsending) func load() async {
    func load() async {
        // 呼び出し元アクターで動く (この場合は MainActor)
    }
}

/* ------------------------------------------------------------------------------------------------------------*/
/*
 * Disable Outward Actor Isolation Inference
 * クロスモジュール間における actor 隔離の推論（inference）を抑制するオプション
 * 型のメンバー関数（インスタンスメソッドやプロパティなど）に対して「暗黙的に actor 隔離を推論する」機能を有効/無効にするかを制御します。
 * Yes: モジュールBではMainActorがないとみなされ、logger.log(...) は actor-isolated と見なされず、警告やエラーになる可能性あり
 * No: モジュールAのMainActorが伝播し、 logger.log(...) は MainActor 上で動くよう扱われる
 * https://developer.apple.com/documentation/xcode/build-settings-reference#Disable-Outward-Actor-Isolation-Inference
 * Swift6では常に有効
 */

import Module

final class DisableOutwardActorIsolationInference: Sendable {
    // ModuleA
//    @MainActor
//    public class Logger {
//        public init() {}
//
//        public func log(_ message: String) {
//            print("log:", message)
//        }
//    }

    // ModuleB (App side)

    //import ModuleA

//    @MainActor
//    func perform() {
//        let logger = Module.Logger()
////        let logger = Logger()
//        logger.log("Hello") // ← actor-isolatedと推論されるかどうかがポイント
//    }


    @MainActor
    class ViewModel: LoggerProtocol {
        var title: String = "Hello"

        func greet() {
            print(title) // OK：titleもMainActor隔離されている
        }

        func log(_ message: String) {
        }
    }

//    @MainActor
    func run(vm: ViewModel) {

        Task.detached {
            let logger = Module.Logger()
            await logger.log("hello")
            await print(vm.title) // ❌ MainActorに隔離されたプロパティに非同期からアクセス → コンパイルエラー
        }
    }

    actor DataStore {
        var logs: [String] = []

        func save(log: String) {
            // プライベート関数を呼び出す
            addTimestampAndSave(log)
        }

        // この時点では、どのスレッドで実行されるべきか明記していない
        // だが、private なのでコンパイラが「DataStoreの一部だ」と推論してくれる
        func addTimestampAndSave(_ message: String) {
            // ❌ await なしで logs にアクセスできている
            //    -> この関数が DataStore アクター上で実行されている証拠
            logs.append("\(Date()): \(message)")
            print("ログを保存しました。")
        }
    }

    @MainActor
    func runTest() async {
        let store = DataStore()

        print("テストを開始します...")

        // 外部のアクター(@MainActor)からDataStoreのメソッドを呼び出す
        // これにより、アクターの境界を越えるため、厳格なチェックが必ず行われる
        await store.save(log: "アクターの境界を越えた呼び出し")

        print("テストが完了しました。")
    }

    func runTestHoge() {
        // テストの実行
//        Task { @MainActor in
        Task {
            await self.runTest()
        }
    }
}



/* ------------------------------------------------------------------------------------------------------------*/
/*
 * Global-Actor-Isolated Types Usability
 * 主な目的は、プロパティにnonisolated(unsafe)とマークする必要性を減らすことです。
 * グローバルアクター（たとえば @MainActor）で隔離された型の使いやすさをどう扱うかを制御する
 * Yes: Logger のインスタンス化や格納が許容される（Swift 5 系の動作互換性を維持）
 * No: Logger の型自体が MainActor に隔離されているため、非 @MainActor の文脈で使うとエラーになる（Swift 6 の厳格なコンパイルチェックが有効になり、安全だが制限も増える。
 * https://developer.apple.com/documentation/xcode/build-settings-reference#Disable-Outward-Actor-Isolation-Inference
 * Swift6では常に有効、すなわちnonisolated(unsafe)は省略される
 */

class GlobalActorIsolatedTypesUsability {
//    class NonSendable {
//      func test() {}
//    }
//
//    @MainActor
//    class IsolatedSubclass: NonSendable {
//      var mutable = 0
//      override func test() {
//        super.test()
////        mutable += 0 // error: Main actor-isolated property 'mutable' can not be referenced from a non-isolated context
//      }
//
//        func trySendableCapture() {
//            Task.detached { @Sendable in
//                self.test() // error: Capture of 'self' with non-sendable type 'IsolatedSubclass' in a `@Sendable` closure
//            }
//        }
//    }

//    @MainActor
    class Logger {
        var text: String = ""
        func log(_ message: String) {
            print(message)
        }
    }

    struct Wrapper {
        let logger: Logger // ❌ Global-Actor-Isolated Types Usability = No のときにエラー

//        func run(logger: Logger) {
//            logger.log("test")
//        }
    }

    func run() {
        let logger = Logger()  // ← ⚠️ Global-Actor-Isolated Types Usability = No ならここでエラー
//        logger.log("Hello")    // ← さらに別の actor-isolation エラーも
    }

    let logger: Logger = .init()



    // メインアクターに分離されたクラス
    @MainActor
    class UserData {
        var name: String // StringはSendableではないが、@MainActorによって保護される
        var logger = Logger()  // ← ⚠️ Global-Actor-Isolated Types Usability = No ならここでエラー

        init(name: String) {
            self.name = name
        }

        func printUserName() {
            print("現在のユーザー名: \(name)")
        }

        // 非同期でユーザー名を更新する関数
        func updateUserName(newName: String) async {
            // メインアクター上で実行されるため、nameへのアクセスは安全
            self.name = newName
            print("ユーザー名を \(newName) に更新しました。")
        }
    }

    // 別のアクター（例: グローバルな非同期タスク）からUserDataを操作する
//    func performUserUpdate() async {
//        let user = UserData(name: "初期ユーザー")
//        await user.printUserName() // メインアクターに切り替えて実行される
//
//        // メインアクターに切り替えてupdateUserNameを呼び出す
//        await user.updateUserName(newName: "新しいユーザー名")
//        await user.printUserName()
//    }

    // 非同期処理を開始
//    Task {
//        await performUserUpdate()
//    }
}

/* ------------------------------------------------------------------------------------------------------------*/
/*
 * Infer Sendable for Methods and Key Path Literals
 * クロージャが @Sendable であれば、その中でキャプチャされるメソッドや関数が Sendable かどうかを、コンパイラが自動で検査・推論します。
 * 明示的に @Sendable や Sendable を記述する必要がない場面が増えます。
 * Yes（推論を有効）: クロージャ内で使用されるメソッドや key path を 自動で Sendable として安全性チェックし、準拠できる場合は許可される。
 * No（推論を無効）: Sendable であることを 明示的に記述しない限り、安全性が不明なものはエラーや警告になる。
 *
 */

//class OldStyle {
//    class Greeter: Sendable {
//        func greet(name: String) {
//            print("Hello, \(name)")
//        }
//    }
//
//    func run() {
//        let greeter = Greeter()
//
//        // Sendableなクロージャ
//        Task.detached(priority: nil) { @Sendable in
//            // ❌ Swift 5.9 では警告またはエラー：greeter が非 Sendable
//            greeter.greet(name: "Swift")
//        }
//    }
//}

class NewStyle {
    class Greeter {
        func greet(name: String) {
            print("Hello, \(name)")
        }
    }

    func run(greeter: Greeter) async {
        let greeter = Greeter()

        Task.detached {
            greeter.greet(name: "Swift") // ✅ Swift6.2からはSendableであればコンパイル通る：自動で安全性チェック、通る場合は推論してくれる
        }
    }
}

/* ------------------------------------------------------------------------------------------------------------*/
/*
 * Dynamic Actor Isolation
 * アクター隔離を「動的に切り替える」＝プロトコルやクロージャで動的に actor を判断できるようにする。
 * 実行時にアクター分離違反をチェックし、問題があればアサーション（プログラムのクラッシュ）として報告するメカニズムを導入します。
 * Yes: actorの隔離メンバーにアクセスできる（実行時隔離）、nonisolated(unsafe)が使える
 * No: actorメンバーへのアクセスは禁止される
 * 具体例：
 *  1. Objective-Cとの相互運用: Objective-Cで書かれたコードなど、Swiftの静的な並行処理ルールに準拠できない外部フレームワークと連携する場合。
 *   2. 非厳密な並行処理コンテキストからの呼び出し: まだ厳密な並行処理チェックが適用されていないモジュール（@preconcurrencyでマークされたものなど）から、アクター分離されたコードを呼び出す場合。
 * @preconcurrencyは、このような古い、あるいはまだ並行処理に最適化されていないモジュールや型、関数に対して、一時的に厳密な並行処理チェックを緩和するために使用されます。
 */



/* ------------------------------------------------------------------------------------------------------------*/
/*
 * Isolated Default Value
 * 関数のデフォルト引数値や格納プロパティの初期値が、その宣言のアクター分離要件を満たす必要があるというルールと、その関連するコンパイラ設定について
 * Yes: コンパイラは、デフォルト引数や格納プロパティの初期値が、その宣言のアクター分離要件を満たしているかを厳密にチェックするようになる
 * No: コンパイラは、デフォルト引数や格納プロパティの初期値に対するアクター分離チェックを緩和します。
 * TODO: そもそもデフォルト値にインスタンスプロパティを付与することはできないので気にしなくて良い？
 */

//class IsolatedDefaultValue {
//    class Hoge {
//        var name: String = "aaa"
//
//        func setName(a: String) {
//            name = a
//        }
//
//    }
//
//    @MainActor
//    class MyView {
//        var someData: Int = 0
//
////        func update() { // ここで問題が発生しうる
//        func update(value: Int = someData) { // ここで問題が発生しうる
////        func update(value: Hoge = .init()) { // ここで問題が発生しうる
//            run(value: someData)
//        }
//
//        func run(value: Int = 0) {
//
//        }
//    }
//}




/* ------------------------------------------------------------------------------------------------------------*/
/*
 * Isolated Global Variables
 */


/* ------------------------------------------------------------------------------------------------------------*/
/*
 * Region Based Isolation
 * Region Based Isolation では、非Sendableな値が Isolation Boundary を跨ぐ場合でも、値が以降のコードで再利用されないことをコンパイラが検出できればエラーが発生しない
 */

class RegionBasedIsolation {
    // Sendable に準拠していない（または明示的に準拠させていない）クラス
    // クラスは参照型であり、Sendable でないと複数スレッドでの共有は危険
    class NonSendableCounter {
        var value: Int = 0

        func increment() {
            value += 1
        }

        func getValue() -> Int {
            return value
        }
    }

    // Global actor に分離されていないため、異なる Task からアクセスすると危険
    var globalCounter = NonSendableCounter() // グローバル変数もデフォルトでは安全に共有できない

    @MainActor
    func demonstrateRegionBasedIsolationError() async {
        print("--- Region Based Isolation Error Demonstration ---")
        globalCounter.increment()

        // Task 1: globalCounter を変更しようとする
        let task1 = Task {
            // ここでコンパイルエラーが発生します！
            // エラーメッセージ例:
            // "Reference to captured var 'globalCounter' in concurrently-executing code is not 'Sendable' and cannot be referenced from a stricter concurrency context"
            // または類似の「captured var」や「not Sendable」に関するエラー
            print("thread is  \(Thread().isMainThread)") // (エラーがなければ)
            globalCounter.increment()
            print("Task 1 incremented: \(globalCounter.getValue())") // (エラーがなければ)
        }

//        // Task 2: 同時に globalCounter を変更しようとする
//        let task2 = Task {
//            // ここでもコンパイルエラーが発生します！
//            globalCounter.increment()
//            print("Task 2 incremented: \(globalCounter.getValue())") // (エラーがなければ)
//        }

//        _ = await [task1.value]
//                _ = await [task1.value, task2.value]
    }

    class Client {
        var name: String
        var initialBalance: Double

        init(name: String, initialBalance: Double) {
            self.name = name
            self.initialBalance = initialBalance
      }
    }

    actor ClientStore {
        var clients: [Client] = []

        static let shared = ClientStore()

        func addClient(_ c: Client) {
            clients.append(c)
        }
    }

    func openNewAccount(name: String, initialBalance: Double) async {
        let client = Client(name: name, initialBalance: initialBalance)
        await ClientStore.shared.addClient(client)
//        print(client.name)
    }

//    final class NonSendableGreeter {
//        var name: String = "Swift"
//
//        func greet() {
//            print("Hello, \(name)")
//        }
//    }
//
//    func run() {
//        let greeter = NonSendableGreeter()
//
//        // 明示的に Task の中に閉じ込める
//        Task.detached { @Sendable in
//            greeter.greet() // ⚠️ Region Based Isolation = No だとコンパイルエラー
//        }
//    }
}

class ImplicitlyOpenedExtentials {
    // Equatableに準拠した何らかの値を保持するプロトコル
    protocol Holdable {
        associatedtype Value: Equatable
        var storedValue: Value { get }
    }

    // 上記プロトコルに準拠した具体的な型
    struct StringHolder: Holdable {
        var storedValue: String
    }

    // 存在型（any Holdable）の変数
    let anything: any Holdable = StringHolder(storedValue: "Swift")

    // 機能が有効な場合、ジェネリックなメソッドを直接呼び出せる
    // 以前は、any Holdable型から具体的な型を取り出すための複雑な処理が必要だった
    func areEqual<T: Holdable>(_ val1: T, _ val2: T) -> Bool {
        return val1.storedValue == val2.storedValue
    }

    func hoge() {
        print(anything.storedValue)
    }

    // anythingが内部で自動的に展開され、ジェネリック関数に渡される
    // areEqual(anything, anything) // このような直接比較はできないが、
    // コンパイラがanyの扱いをより賢く行うようになるのがこの機能の趣旨

    protocol Animal {
        func speak()
    }

    struct Dog: Animal {
        func speak() { print("Woof") }
    }

    struct Cat: Animal {
        func speak() { print("Meow") }
    }

    func run() {
        let a: Animal = Dog()
    }
}
