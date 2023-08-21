//
//  TimestampView.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 8/18/23.
//

import SwiftUI

struct TimestampView: View {
    @State var timestamp: Date

    private var timestampString: String {
        let isToday = Calendar.current.isDateInToday(timestamp)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        if isToday {
            return "Today \(formatter.string(from: timestamp))"
        } else {
            formatter.dateStyle = .medium
            return formatter.string(from: timestamp)
        }
    }

    var body: some View {
        HStack {
            Spacer()
            Text(timestampString)
                .font(.caption)
                .foregroundColor(Color(UIColor.secondaryLabel))
            Spacer()
        }
    }
}
