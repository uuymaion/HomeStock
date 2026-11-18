# HomeStock — Home Inventory

An iPhone app for the whole family to keep track of **where things are stored at home**, **when they expire**, **how often they need to be used or replaced**, and **when it's time to restock**.


## Concept

Households often run into the same problems:

- You need something but can't remember which cabinet, or which shelf, it's in.
- Things expire before anyone notices, or you buy something you already have.
- Items that need regular replacement, like filters or toothbrushes, keep getting forgotten.
- Each family member puts things away in their own way, and nobody else can find them.

HomeStock brings all of this into one app built around just two actions: **Add** and **Find**.

- **Add**: record an item. Only the name is required; everything else can be filled in later.
- **Find**: locate items through search, tags, or the map, and get reminders when something needs attention.

The interface uses a dark blue and purple color scheme, and the map is a grid floor inspired by idle/placement games, to make organizing the house a little more fun.


## Features

### Items
- Each item can record: name, category, tags, brand, location, expiry date, usage interval, and quantity. Everything except the name is optional.
- Expiry date: notifies you N days before expiry. N can be set per item.
- Usage interval: use or replace every N days, weeks, or months. Tap "Used" to restart the timer.
- Quantity: adjust with + / −. You get a restock reminder when it drops to or below a threshold you set.
- The item detail page supports editing and deleting, and shows status badges such as "Expiring soon", "Time to use", and "Restock".

### Tags
- **Category**: at most one per item, e.g. toiletries, hygiene products, electronics. Items without one are "Uncategorized".
- **Tags**: any combination, e.g. tissues, cleaning cloths.
- **Brand**: one per item.
- Tags can be selected or created directly on the add-item screen. Used tags are remembered and can be deleted in Settings › Tag Management.
- Tags are shared across the whole family.

### Find (Home)
- Lists all items, searchable by name, tag, or location.
- Quick category switcher at the top, plus filters for tags and brands.
- Sort by: newest, name, or most urgent.
- Option to show only items that need attention (expiring, due for use, or needing restock).

### Locations
- Structure: **Room → Cabinet (a grid of shelves × columns) → Box**.
- Cabinets have a configurable number of shelves and columns, e.g. 3 shelves × 2 columns = 6 compartments.
- Boxes can sit in a cabinet compartment or directly in a room.
- Items can be placed in a room, a cabinet compartment, or a box.
- When a box is moved, the items inside move with it automatically.

### Grid Map
- Each room has its own grid floor, viewed from directly above (2D). Default size is 10 × 8, adjustable.
- **Cabinets and furniture** occupy cells. Drag to move (snaps to the grid, no overlapping), resize, rotate 90°, or delete.
- **Built-in furniture**: table, bed, chair.
- **Custom furniture**: choose a name, icon, and size. Saved as a template the whole family can reuse.
- **Walls and doors** are drawn along grid lines and don't occupy cells, so you can outline rooms that aren't rectangular.
- Tap a cabinet to open it and see what's in each compartment.

### Family Sharing
- One person creates a family and sets a password; the app generates a 6-character family code. Other members join with the code and password.
- Each room can be **shared with the family** or **private**. Private rooms and their contents are visible only to their creator.
- The family creator can remove members and change the password.
- Data is stored in the cloud and syncs between family members in real time. The app also works offline and syncs automatically once reconnected.

### Notifications
- Three kinds of reminders: expiry, usage interval, and restock. All are local iPhone notifications, so no separate server is needed.
- The daily notification time, and the default number of days to notify before expiry for new items, can be changed in Settings.

## Tech Stack

| Item | Technology |
|---|---|
| Platform | iOS 17+ (iPhone) |
| Language / UI | Swift, SwiftUI |
| Database | Firebase Cloud Firestore (with offline cache) |
| Sign-in | Firebase Authentication (anonymous), combined with a family code and password |
| Access control | Firestore security rules (`firestore.rules`) |
| Notifications | UserNotifications (local notifications) |
| Distribution | Not on the App Store; installed directly onto your own iPhone with Xcode |

### Files

| File | Contents |
|---|---|
| `HomeStockApp.swift` | App entry point, first-launch flow, tabs |
| `HomeStore.swift` | All data reads and writes, cloud sync, creating and joining a family |
| `Models.swift` | Data models (items, tags, rooms, cabinets, boxes, furniture) |
| `FamilyViews.swift` | Create / join a family, family management |
| `ItemListView.swift` | Find (home) screen |
| `ItemFormView.swift` | Add and edit items |
| `ItemDetailView.swift` | Item details |
| `InlineTagPicker.swift` | Inline tag selector component |
| `TagViews.swift` | Tag management |
| `LocationViews.swift` | Managing and picking rooms, cabinets, compartments, and boxes |
| `MapView.swift` | Grid map, walls and doors, custom furniture |
| `NotificationManager.swift` | Notification scheduling |
| `SettingsView.swift` | Settings |
| `Theme.swift` | Colors and shared components |
| `firestore.rules` | Database security rules (paste into the Firebase console) |



## Not Yet Implemented

- **AI photo recognition**: take a photo of a product and fill in its name and brand automatically. Planned to use the Google Gemini API, with the API key entered by the user in Settings.
- **Dragging walls and doors**: currently, a misplaced wall or door has to be deleted and redrawn.
- **Furniture–wall collision**: furniture can currently be placed on top of walls.
- **Cells outside walls**: cells outside the walls are still visible and can still hold objects.
- **Map cell size**: cells are fairly small on a phone screen, so cabinet names are hard to read.
- **Performance**: every data change reschedules all notifications, which may cause lag with a lot of data.
- **Restock notification scope**: only the phone that changed the quantity gets the restock notification; other family members don't.
- **Migrating old data**: there's no way to upload data that was stored on the phone before the switch to the cloud database.


## Getting Started

### 1. Requirements

- A Mac with a recent version of Xcode that supports your phone's iOS version (e.g. a phone on iOS 26 needs Xcode 26 or later)
- An iPhone (iOS 17+) and a cable
- An Apple ID (a free account is fine)
- A Google account (to create the Firebase project)

### 2. Set Up Firebase

This repo does **not** include `GoogleService-Info.plist`. You need to create your own Firebase project and download it.

1. Create a project in the [Firebase console](https://console.firebase.google.com). The free Spark plan is enough.
2. Add an app → choose **iOS**, and enter your Xcode project's Bundle Identifier as the Apple bundle ID.
3. Download `GoogleService-Info.plist` and put it in the `HomeStock` folder of the Xcode project.
4. **Authentication** → Sign-in method → enable **Anonymous**.
5. **Firestore Database** → Create database (location `asia-east1` recommended for Taiwan; start in production mode).
6. In Firestore's **Rules** tab, paste the contents of this project's `firestore.rules` and publish.

### 3. Install on Your iPhone with Xcode

1. Open `HomeStock.xcodeproj` in Xcode.
2. If the Firebase packages don't load automatically: File → Add Package Dependencies → enter `https://github.com/firebase/firebase-ios-sdk`, and add only **FirebaseAuth** and **FirebaseFirestore**.
3. TARGETS HomeStock → **Signing & Capabilities** → set Team to your Apple ID.
4. Connect your iPhone to the Mac with a cable, select it in the device menu at the top, and press ▶ to run.
5. On first install, do two things on the iPhone:
   - Settings › Privacy & Security › turn on **Developer Mode** (the phone will restart).
   - Settings › General › VPN & Device Management › trust your developer app.

> **Note**: Apps signed with a free Apple ID must be re-signed every **7 days**. When it expires, the app won't open; just connect to the Mac and press ▶ again. Your data is not lost.
> If you check **Connect via network** in Xcode's Window › Devices and Simulators, you can reinstall without a cable whenever the Mac and phone are on the same Wi-Fi.
>
> **Don't delete the app from the phone**: after reinstalling, you'll have to rejoin the family with the code and password, and any private rooms that phone created will no longer be accessible.

### 4. First Launch

- **First person**: choose "Create Family" and enter a family name, your nickname, and a password. A 6-character **family code** is shown when done.
- **Other family members**: choose "Join Family" and enter the family code, password, and their nickname.
- Allow notifications to receive reminders.
- The family code can be viewed later in Settings › Family.

### 5. Everyday Use

1. **Set up locations**: in the "Locations" tab, add rooms (shared or private), then add cabinets with their number of shelves and columns, and add boxes to compartments if needed.
2. **Lay out the map**: in the "Map" tab, tap "Edit", add furniture with +, and drag cabinets into place. Switch to the "Draw Wall" and "Place Door" tools to outline the room.
3. **Add items**: in the "Add" tab, enter a name, pick tags and a location, set an expiry date, usage interval, and quantity as needed, then tap "Save".
4. **Find items**: search or filter in the "Find" tab, or tap a cabinet in the "Map" tab to see what's in each compartment.
5. **Handle reminders**:
   - After using something that needs regular replacement, tap "**Used**" on its detail page to restart the timer.
   - When you use something up, tap **−** to reduce the quantity; you'll get a reminder when it's running low.
6. **Settings**: change the notification time and manage tags and family members in the "Settings" tab.

> The app's interface is currently in Traditional Chinese.
