# 🚀 DirXplore `v1.0.8`

**DirXplore** is a high-performance, premium Flutter application designed for power users who need to browse, crawl, and download from open directories (Apache/Nginx) with surgical precision.

---

## ✨ Cool Things About This Project

### 🌐 Advanced Browser & Deep Crawler
- **Isolate-Powered Crawling**: BFS (Breadth-First Search) crawler that runs in a background isolate, ensuring the UI stays butter-smooth even while scanning thousands of folders.
* **Smart Categorization**: Automatically filters for Movies, Series, Games, and Software using intelligent keyword mapping.
* **Navigation Stack**: Robust history management with "Up", "Back", and "Sort" capabilities.

### 📥 Ultimate Download Manager
* **Multi-Threaded Concurrency**: Download multiple files simultaneously with configurable limits.
* **Pause & Resume**: Full support for `Range` headers and `206 Partial Content`, meaning you never lose progress.
* **Liquid Glass UI**: Stunning progress bars with real-time speed tracking and ETA calculation.

### 🛡️ Premium Proxy System
* **App-Specific Tunneling**: Integrated support for **SOCKS5, SOCKS4, and HTTP** proxies that only affect internal `dio` traffic.
* **One-Tap Switch**: Seamlessly toggle between multiple proxy configurations.
* **Latency Testing**: Built-in ping tool to check proxy speed before connecting.

### 💎 Liquid Glass Design
* **Modern Aesthetics**: Built with a "Liquid Glass" design system, featuring vibrant gradients, deep blurs, and organic micro-animations.
* **Dynamic Themes**: Seamless switching between Material Light, Dark, and a true **AMOLED Black** mode for OLED screens.

### 🛠️ Tech Stack
* **Flutter & Dart**: For a high-fidelity cross-platform experience.
* **Dio Client**: For robust networking and custom proxy adapters.
* **C++ Native Extensions**: High-performance hash calculation and file processing using Dart FFI.
* **Provider**: Scalable and reactive state management.

---

## 🛠️ Getting Started

1.  Clone the repository: `git clone https://github.com/rakibshorkar2/dirxplore1.git`
2.  Install dependencies: `flutter pub get`
3.  Run on Android: `flutter run --release`

Created with ❤️ by **RAKIB**
