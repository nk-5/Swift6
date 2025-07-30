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
*   - Minimal: （最も緩い、Swift 5相当）
*   - Targeted: （一部のエラーが有効）
*   - complete: (Swift 6の完全なconcurrencyチェック）
*/


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


/*
 * nonisolated(nonsending) By Default
 * Yes（安全側）: デフォルトでnonisolated(nonsending) を付与するので、呼び出し元のisolated domainと同じdomainで実行される
 * No（従来の緩い挙動）: デフォルトでnonisolated(nonsending) を付与しないので呼び出し元とは異なるisolated domainの場合はエラーになる
 * Migrate:
 */

struct NonisolatedNonsendingByDefaultView: View {
    let repository = Repository()

    var body: some View {
        EmptyView()
            .task {
                await repository.load() // エラーが発生しない
            }
    }
}

class Repository { // Sendable でなくても OK
//    nonisolated(nonsending) func load() async {
    func load() async {
        // 呼び出し元アクターで動く (この場合は MainActor)
    }
}


/*
 * Disable Outward Actor Isolation Inference
 * クロスモジュール間における actor 隔離の推論（inference）を抑制するオプション
 * Yes: モジュールBではMainActorがないとみなされ、logger.log(...) は actor-isolated と見なされず、警告やエラーになる可能性あり
 * No: モジュールAのMainActorが伝播し、 logger.log(...) は MainActor 上で動くよう扱われる
 */

class DisableOutwardActorIsolationInference {
    // ModuleA
    @MainActor
    public class Logger {
        public init() {}

        public func log(_ message: String) {
            print("log:", message)
        }
    }

    // ModuleB (App side)

    //import ModuleA

    @MainActor
    func perform() {
        let logger = Logger()
        logger.log("Hello") // ← actor-isolatedと推論されるかどうかがポイント
    }
}


/*
 * Global-Actor-Isolated Types Usability
 * グローバルアクター（たとえば @MainActor）で隔離された型の使いやすさをどう扱うかを制御する
 * Yes: Logger のインスタンス化や格納が許容される（Swift 5 系の動作互換性を維持）
 * No: Logger の型自体が MainActor に隔離されているため、非 @MainActor の文脈で使うとエラーになる（Swift 6 の厳格なコンパイルチェックが有効になり、安全だが制限も増える。
 * TODO: Xcode26-beta4でNoでもエラーにならない
 */

class GlobalActorIsolatedTypesUsability {

    @MainActor
    class Logger {
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

}


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
    // TODO: YesでもSendable付与しないとSendableなクロージャ内の呼び出しでコンパイルエラーになる、推論されていない??
    final class Greeter: Sendable {
        func greet(name: String) {
            print("Hello, \(name)")
        }
    }

    func run() {
        let greeter = Greeter()

        Task.detached { @Sendable in
            greeter.greet(name: "Swift") // ✅ OK：自動で安全性チェック、通る場合は推論してくれる
        }
    }
}
