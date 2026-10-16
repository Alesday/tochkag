// SPDX-License-Identifier: MIT
// Copyright © 2018-2023 WireGuard LLC. All Rights Reserved.

import Foundation

extension Array {
    func concurrentMap<U>(queue: DispatchQueue?, _ transform: (Element) -> U) -> [U] {
        var result = [U?](repeating: nil, count: self.count)
        let resultQueue = DispatchQueue(label: "ConcurrentMapQueue")

        if let queue = queue {
            queue.sync {
                DispatchQueue.concurrentPerform(iterations: self.count) { index in
                    let value = transform(self[index])
                    resultQueue.sync { result[index] = value }
                }
            }
        } else {
            DispatchQueue.concurrentPerform(iterations: self.count) { index in
                let value = transform(self[index])
                resultQueue.sync { result[index] = value }
            }
        }

        return result.map { $0! }
    }
}
