**Role:** Expert Senior Flutter & Dart Developer

**Task:** I want you to create a complete, highly advanced Flutter application for Android. This app is an evolution of a Python/Kivy HTTP/FTP Open Directory Browser and Download Manager. 

The app parses Apache/Nginx-style open directories, allows deep crawling/searching with category filters, features a robust concurrent download manager with pause/resume, has a fully dedicated in-app proxy management system, and includes a settings tab with GitHub OTA update capabilities.

### 1. App Architecture & State Management
*   **Target Platform:** Android.
*   **Theme:** Dynamic (Dark/Light/System) managed via state.
*   **State Management:** Use `Provider` or `Riverpod` to manage the UI state, directory browsing history, download queues, proxy lists, and settings.
*   **Networking:** Use the `dio` package for network requests, robust downloading, and handling proxies. Use `native_dio_adapter` or `dio.httpClientAdapter` to route traffic.
*   **HTML Parsing:** Use the `html` package (Dart equivalent to BeautifulSoup) to parse `<a href>` tags.
*   **Local Storage & Permissions:** `shared_preferences` for app settings, `sqflite` or `hive` for saving proxy lists and download history. `permission_handler` for handling Android 11+ `MANAGE_EXTERNAL_STORAGE` and standard read/write permissions.

### 2. Core Features & Tab Layout (4 Tabs via BottomNavigationBar)

#### Tab 1: Browser
*   **URL Controls:** URL text input box, "CONNECT" (or Go) button, "PASTE" link button, and "COPY" link button.
*   **Navigation Tools:** "< Back" (uses history stack), "^ Up" (goes to parent directory), "SORT" (cycles Folders First, By Type, A-Z), "SELECT ALL" (checkboxes).
*   **Deep Crawler & Search Bar:**
    *   Text input for search terms.
    *   Dropdown for Categories: `All Categories`, `Movies`, `Series/TV`, `Games`, `Software`.
    *   "DEEP CRAWL" button: Initiates a background Breadth-First Search (BFS) isolate to crawl folders recursively without freezing the UI.
    *   *Crawler Rules:* Ignore "Parent Directory", "../", "Name", "Size". Filter by category keywords (e.g., Movies: 1080p, bluray; Series: s01, e01, etc.).
*   **List View:** Shows parsed items with Icon Tags (`[DIR]`, `[VID]`, `[ZIP]`, etc.), Name, File Size, Checkbox, and an "OPEN" button for directories.
*   **Action:** "QUEUE SELECTED" button to send files (or recursively scrape selected folders) to the Download Tab.

#### Tab 2: Download Manager
*   **Global Controls:** "PAUSE ALL", "RESUME ALL", "CLEAR DONE", "CLEAR ALL".
*   **List View (Queue):**
    *   Each row shows: File Name, Size (Downloaded / Total), Progress Bar (0-100%), Speed & ETA (e.g., `1.5 MB/s | ETA: 05m 30s`), Status (Queued, Downloading, Stopped, Error, Done).
    *   Action button per row: STOP, RESUME, RETRY, DONE.
*   **Download Engine Rules:**
    *   **Concurrency:** Configurable limit (default 3 active downloads).
    *   **Resumable Downloads:** Send `Range: bytes={existing_size}-` header. Handle `206 Partial Content`.
    *   **Auto-Retry:** Retry up to 3 times on connection drops.

#### Tab 3: Proxy Manager (Advanced)
*   **Core Rule:** Proxies configured here MUST ONLY apply to the app's internal `dio` requests. It must NOT act as a device-wide VPN.
*   **Supported Protocols:** SOCKS5, SOCKS4, HTTP, HTTPS.
*   **Add Proxy Forms:**
    *   *Form A (Manual):* Dropdown for Protocol, Inputs for IP, Port, Username (optional), Password (optional).
    *   *Form B (URI/Link):* Single input for a proxy string (e.g., `socks5://user:pass@192.168.1.1:1080`) which auto-parses into the correct fields.
*   **Proxy List UI:** A ListView of all added proxies.
    *   Each proxy item has an individual ON/OFF toggle switch. (Only one proxy can be active at a time, turning one ON turns others OFF).
    *   "TEST PROXY" button: Pings a reliable URL (like `https://1.1.1.1` or `http://google.com`) through the specific proxy and returns the latency (ms) or "Failed".
    *   Delete/Edit buttons.

#### Tab 4: Settings
*   **UI Customization:** Theme Toggle (Dark / Light / System Default).
*   **Download Preferences:** Default Save Path picker, Max Concurrent Downloads slider/input, Connection Timeout setting.
*   **About Section:** 
    *   Text: "Created by RAKIB" (Make this prominent).
    *   App Version info (fetched via `package_info_plus`).
*   **OTA Updater:**
    *   "Check for Updates" button.
    *   Logic: Ping a public GitHub Repository's Releases API (`https://api.github.com/repos/YOUR_USERNAME/YOUR_REPO/releases/latest`).
    *   Compare the fetched version tag (e.g., `v1.2.0`) with the app's current version.
    *   If an update is available, show a dialog with release notes and a button to download the new `.apk` via `url_launcher` or the internal download manager.

### 3. Utility Functions Needed
1.  **Size Formatter:** Convert bytes to B, KB, MB, GB.
2.  **Time Formatter:** Convert seconds to `Xh Ym Zs`.
3.  **Proxy Adapter Override:** Custom logic to attach `dio.httpClientAdapter = IOHttpClientAdapter(createHttpClient: () { ... client.findProxy = ... })` based on the active proxy.

### 4. Implementation Details for the Agent
Please provide the code logically separated. You don't have to write the entire app in one block, but please provide the complete code for:
1.  `pubspec.yaml` (List all exact dependencies like `dio`, `html`, `provider`, `shared_preferences`, `permission_handler`, `url_launcher`, `package_info_plus`).
2.  `main.dart` (Initialization, Themeing, and Bottom Navigation routing).
3.  `services/dio_client.dart` (The singleton network client that handles dynamic proxy injection).
4.  `services/github_updater.dart` (Logic to check GitHub releases).
5.  `screens/browser_tab.dart` (UI and BFS logic).
6.  `screens/download_tab.dart` (UI and chunk-writing logic).
7.  `screens/proxy_tab.dart` (UI for proxy management and testing).
8.  `screens/settings_tab.dart` (UI for configuration, "Created by RAKIB", and Update checking).

**Crucial:** Ensure the Android `AndroidManifest.xml` instructions are detailed so permissions (`INTERNET`, `MANAGE_EXTERNAL_STORAGE`, `REQUEST_INSTALL_PACKAGES` for updates) work flawlessly.