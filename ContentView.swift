import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = SchoolClosingsViewModel()
    @State private var isRefreshing = false
    
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("School Status")
                                .font(.system(size: 28, weight: .bold, design: .default))
                                .foregroundColor(.primary)
                            
                            Text("Last updated: \(viewModel.lastUpdated)")
                                .font(.system(size: 13, weight: .regular, design: .default))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            isRefreshing = true
                            viewModel.fetchClosings {
                                isRefreshing = false
                            }
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(
                                    Circle()
                                        .fill(Color.blue)
                                )
                                .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                                .animation(isRefreshing ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                        }
                        .disabled(isRefreshing)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
                .background(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 2)
                
                // Content
                if viewModel.entries.isEmpty && !viewModel.isLoading {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)
                        
                        VStack(spacing: 8) {
                            Text("No Closings")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            Text("All schools are operating normally")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 32)
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(viewModel.entries, id: \.self) { entry in
                                SchoolClosingCard(entry: entry)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                    }
                }
            }
            
            // Loading Overlay
            if viewModel.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.3, anchor: .center)
                    
                    Text("Loading...")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.2))
                .ignoresSafeArea()
            }
        }
        .onAppear {
            viewModel.fetchClosings()
        }
    }
}

struct SchoolClosingCard: View {
    let entry: SchoolClosing
    
    var statusColor: Color {
        let status = entry.status.lowercased()
        if status.contains("closed") {
            return Color.red
        } else if status.contains("delay") || status.contains("delayed") {
            return Color.orange
        } else {
            return Color.yellow
        }
    }
    
    var statusIcon: String {
        let status = entry.status.lowercased()
        if status.contains("closed") {
            return "xmark.circle.fill"
        } else if status.contains("delay") || status.contains("delayed") {
            return "exclamationmark.circle.fill"
        } else {
            return "clock.fill"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // School Name and Status Icon
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    Text(entry.status)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(statusColor)
                }
                
                Spacer()
                
                Image(systemName: statusIcon)
                    .font(.system(size: 28))
                    .foregroundColor(statusColor)
            }
            
            Divider()
                .padding(.vertical, 4)
            
            // Details
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    Text(entry.updateTime)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    Text(entry.source)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray5), lineWidth: 1)
        )
    }
}

#Preview {
    ContentView()
}
