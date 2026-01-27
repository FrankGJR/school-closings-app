# School Closings iPhone App

A native iOS app for displaying school closings and delays from NBC Connecticut and WFSB sources.

## Features

- **Real-time Updates**: Fetches data from the school closings API every time you refresh
- **Clean UI**: Modern SwiftUI interface with color-coded status indicators
- **Status Indicators**: 
  - Red: School Closed
  - Orange: School Delayed
  - Yellow: Other status
- **Last Updated**: Shows when data was last pulled from the API
- **Refresh Button**: Manual refresh with animated spinner
- **Sorted by Name**: Schools are automatically sorted alphabetically
- **Empty State**: Beautiful message when no closings exist

## Setup Instructions

### Requirements
- Xcode 14.0 or later
- iOS 15.0 or later
- Swift 5.7 or later

### Installation

1. **Create Project in Xcode**:
   - Open Xcode
   - File → New → Project
   - Choose "App" template
   - Product Name: `SchoolClosingsApp`
   - Interface: SwiftUI
   - Language: Swift

2. **Add Files**:
   - Copy `ContentView.swift` to your project
   - Copy `SchoolClosingsViewModel.swift` to your project
   - Copy `SchoolClosingsApp.swift` as your main app file

3. **Build & Run**:
   - Select "iPhone 15" simulator (or your target device)
   - Press Cmd+R to build and run

## Code Structure

- **ContentView.swift**: Main UI with school list, refresh button, and status display
- **SchoolClosingsViewModel.swift**: Data fetching and state management
- **SchoolClosingsApp.swift**: App entry point

## API Connection

The app connects to:
```
https://yr4zm4dy27.execute-api.us-east-1.amazonaws.com/Prod/
```

Expected JSON response:
```json
{
  "lastUpdated": "01/27/2026 10:30:45",
  "entries": [
    {
      "Name": "Gengras School",
      "Status": "Closed",
      "UpdateTime": "Updated 10:15 AM",
      "Source": "NBC Connecticut"
    }
  ]
}
```

## Design Features

- **Header**: App title + last updated time + refresh button
- **School Cards**: 
  - School name with status icon
  - Status message with color coding
  - Last update time
  - Data source
  - Subtle divider and border
- **Loading State**: Centered spinner overlay during fetch
- **Empty State**: Checkmark icon with friendly message when no closings

## Color Scheme

- Red (#FF3B30): Closures
- Orange (#FF9500): Delays
- Yellow (#FFCC00): Other status
- Blue (#007AFF): Refresh button
- Semantic colors for light/dark mode support

## Customization

To change the API endpoint, edit line in `SchoolClosingsViewModel.swift`:
```swift
private let apiURL = "YOUR_NEW_API_URL"
```

To modify card styling, edit `SchoolClosingCard` in `ContentView.swift`:
- Colors
- Fonts
- Spacing
- Icons

## Deployment

To release on App Store:
1. Create Apple Developer account
2. Create new App ID in App Store Connect
3. Archive the app (Product → Archive)
4. Upload to App Store Connect
5. Submit for review

## Troubleshooting

**"Network error"**: Check internet connection and API URL
**"Failed to parse data"**: Verify API response format matches expected JSON
**No data loads**: Check that API is returning data (visit URL in browser)

## Future Enhancements

- Push notifications for new closings
- Filter schools by name
- Save favorite schools
- Dark mode optimization
- Widget support
- Share closings with others
