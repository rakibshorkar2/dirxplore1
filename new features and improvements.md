**Role:** Expert Senior Flutter & Dart Developer

**Task:** I am building an advanced Android Flutter application: an HTTP/FTP Open Directory Browser, Deep Crawler, and Concurrent Download Manager with an in-app Proxy system. I need you to implement the following critical enhancements and architectural upgrades to the existing app design.

Please provide code and architectural guidance for the following specific features:

### 1. Active Download Notification System & Foreground Service
*   **Requirement:** When a file is downloading, show a persistent notification in the Android notification panel.
*   **Notification Content:** Must display the File Name, a dynamic Progress Bar, Download Speed (e.g., `5.2 MB/s`), and Downloaded Size vs Total Size (e.g., `1.2 GB / 2.0 GB`).
*   **Tech Stack:** Use `flutter_local_notifications` for the UI and a background execution strategy (like `flutter_background_service`) so the download and notification continue even if the app is minimized.
*   **Settings Toggle:** Add a boolean toggle in the Settings Tab (e.g., "Show Download Notifications") saved via `shared_preferences`. If toggled off, downloads happen silently.

### 2. Universal Domain & Subdomain Support (Browser Tab)
*   **Requirement:** The app's URL parser must flawlessly support named domains and subdomains (e.g., `http://new.circleftp.net` or `https://ftp.domain.com`) exactly as it supports raw IP addresses (e.g., `http://172.16.50.4`).
*   **Logic:** Ensure the `html` parser correctly resolves relative paths (`href="movie.mp4"`) and absolute paths (`href="/movies/movie.mp4"`) against the base `Uri`. Handle redirects properly and ensure the Proxy `dio` client resolves DNS correctly.

### 3. YAML Proxy Import System (Proxy Tab)
*   **Requirement:** Allow users to bulk-import proxies from a `.yaml` or `.yml` file.
*   **Tech Stack:** Use the `file_picker` package to select the file, and the `yaml` package to parse it.
*   **Logic:** Add an "Import from YAML" button. The expected YAML structure should be a list of proxies (e.g., containing `type`, `ip`, `port`, `username`, `password`). Loop through the parsed YAML and inject them into the local proxy database (`sqflite` or `shared_preferences`).

### 4. 120Hz / High Refresh Rate Optimization
*   **Requirement:** The app must run at maximum available FPS (90Hz/120Hz) on supported flagship Android displays.
*   **Tech Stack:** Use the `flutter_displaymode` package. 
*   **Logic:** During the `main()` initialization, query the device's supported display modes and automatically set it to the highest refresh rate available.

### 5. Safe Deletion Protocol (Download Tab)
*   **Requirement:** Prevent accidental deletion of queued or finished files.
*   **Logic:** When a user clicks the "CLEAR" or "DELETE" button on a download task (or "CLEAR ALL"), trigger an `AlertDialog` requiring confirmation ("Are you sure you want to remove this task? / Delete file from storage as well?"). Provide checkboxes to either just remove the task from the list or physically delete the `.mp4/.mkv` file from storage.

6.Storage Analyzer:
At the top of the "Downloads" tab, add a sleek horizontal bar showing how much storage is left on the device (e.g., Free Space: 45 GB / 128 GB). This prevents the app from crashing by attempting to download a 50GB file when there is no space.

7.Speed Limiter & Bandwidth Throttling:
Add a slider in the Settings tab to limit the download speed (e.g., "Cap at 2 MB/s"). This is incredibly useful so the app doesn't hog the entire Wi-Fi network while the user is trying to watch YouTube or play games.

8.Material You (Dynamic Color Theme):
Use the dynamic_color package so your app automatically changes its theme to match the user's Android wallpaper (the default behavior in Android 12+). It makes the app feel like a premium, native system app.

9.Wake Lock / Screen On Option:
Add a setting called "Keep Screen Awake While Downloading". Using the wakelock_plus package, you can prevent the phone from going to sleep, which sometimes helps maintain maximum Wi-Fi speeds on certain restrictive Android skins (like MIUI/HyperOS).

10.UI/UX & Quality of Life (Flagship Feel)
Floating Download Bubble (Picture-in-Picture): Like Facebook Messenger bubbles, show a tiny floating circle on the edge of the user's screen with the current download speed (e.g., ↓ 12 MB/s). They can browse Facebook while keeping an eye on the download speed.
Swipe Gestures for Queue: In the Download Tab, allow the user to swipe left on a task to quickly Pause/Resume, and swipe right to trigger the "Safe Deletion" dialog.
Media Grid View with Auto-Thumbnails: Open directories usually look like boring text lists. Add a toggle to switch to "Grid View". If the app detects .jpg or .mp4, it can download the first few kilobytes to generate and display a visual thumbnail!
Speed Dial / Bookmarks: On the Browser tab's empty state, show a visual grid of "Favorite FTPs" with custom icons so users don't have to type new.circleftp.net every time.

11.Smart Automation & Storage Handling
Smart Folder Routing: Add a feature in settings where the app automatically sorts downloaded files into sub-folders based on extensions.
.mkv, .mp4 ➔ /Storage/Downloads/OpenDir/Movies
.iso, .rar ➔ /Storage/Downloads/OpenDir/Games
.apk ➔ /Storage/Downloads/OpenDir/Apps
Battery & Wi-Fi Check: Add toggles: "Pause downloads if battery is below 15%" and "Download on Wi-Fi Only". This prevents users from accidentally draining their mobile data on a 10GB 4K movie.
Anti-Sleep / WakeLock: Android kills apps that run too long. Add a "Keep Screen Dimly Awake" feature that lowers the screen brightness to 1% and displays a sleek black screen with just the download progress, preventing the phone from sleeping and dropping the Wi-Fi speed.

12. FLAGSHIP UPGRADES: AMOLED, Biometrics, Streaming, & Reliability
I am continuing to build my advanced Flutter OpenDir Downloader. Please provide the code, logic, and state management integration for the following premium features:

#### 1. True AMOLED Dark Mode Toggle
*   **Requirement:** In the Settings Tab, the Theme selector must have 4 options: `Light`, `Material Dark`, `True AMOLED Black`, and `System`.
*   **Implementation:** When `True AMOLED Black` is selected, override the `ThemeData` to set `scaffoldBackgroundColor: Colors.black`, `appBarTheme.backgroundColor: Colors.black`, and set surface/card colors to very dark gray (`#0A0A0A`). Ensure all borders and dividers are high-contrast (e.g., `#1E1E1E`).

#### 2. Biometric Privacy Lock
*   **Requirement:** Use the `local_auth` package. Add a toggle in Settings: "Require Fingerprint to Open App".
*   **Implementation:** Wrap the main `MaterialApp` router or `HomePage` in a stateful widget that checks biometric status on `AppLifecycleState.resumed`. Show a pure black screen with a Fingerprint icon until authenticated.

#### 3. In-App Media Streaming (Preview Mode)
*   **Requirement:** Use the `media_kit` or `better_player` package.
*   **Implementation:** In the Browser Tab, if a file has a `.mp4`, `.mkv`, or `.webm` extension, show a "▶️ STREAM" button next to the download button. Pressing it opens a full-screen video player that streams the file directly from the HTTP/FTP URL. Ensure the proxy settings (if active) are passed to the player's network configuration so BDIX/local streams work through the proxy.

#### 4. Smart Auto-Resume (Network & Boot Persistence)
*   **Requirement:** Downloads should survive app closures and network drops.
*   **Implementation:** 
    *   Use `connectivity_plus`. Listen to network changes. If the state goes from `none` to `wifi`/`mobile`, trigger a function that checks the database for "Downloading" or "Paused (Network Error)" tasks and automatically resumes them.
    *   Explain how to register a `RECEIVE_BOOT_COMPLETED` receiver in Android (`AndroidManifest.xml`) and trigger a background headless task (using `workmanager` or `flutter_background_service`) to wake the app up and resume the queue after the phone restarts.

#### 5. File Integrity Checker (Checksum)
*   **Requirement:** Allow users to verify downloaded files.
*   **Implementation:** In the Download Tab, add a "Verify Hash" option to the menu of completed downloads. Open a Dialog where the user can paste an expected MD5 or SHA256 string. Use the `crypto` package in Dart inside an `Isolate` (so the UI doesn't freeze on huge files) to calculate the file's hash by reading it in chunks, and compare it to the user's input. Display a Green ✅ or Red ❌ result.

#### 6. Export / Import Queue
*   **Requirement:** Backup and Restore functionality for the download queue.
*   **Implementation:** Add buttons in Settings to "Export Queue" and "Import Queue". Convert the local database (Hive or SQLite) of all tasks (Name, URL, SavePath, DownloadedBytes, TotalBytes) into a JSON string. Use the `path_provider` and `share_plus` packages to save/share this JSON file, and `file_picker` to load it back in.

**Code Quality constraints:** Provide the updated `pubspec.yaml` dependencies. Ensure all heavy processing (like hashing a 10GB file) is strictly done using `Isolate.run()` to maintain the 120Hz UI performance we set up previously.

13.The Ultimate Streaming Engine
In-App Cinematic Player: Use media_kit (which has hardware acceleration and VLC's engine under the hood) to play .mkv, .mp4, .avi, and .webm directly inside the app. It supports multi-audio tracks and subtitles.
External Player Bridge (Localhost Tunnel): Add a "Play in External App" button. The app spins up a local HTTP server, pipes the proxy traffic through it, and fires an Android Intent to open MX Player, VLC, or XPlayer natively.
Resume Playback Position: If you stop watching a movie at 45:12, the app remembers this. Next time you stream it, it asks: "Resume from 45:12?"

