//
//  Concurrency.swift
//  Swift6
//
//  Created by Keigo Nakagawa on 2025/07/30.
//

import Foundation
import SwiftUI

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
 * Swift Concurrency Checking (SWIFT_STRICT_CONCURRENCY)の状態にも依存する
 *   - Minimal: エラーにならない
 *   - Targeted:
 *   - complete:
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

