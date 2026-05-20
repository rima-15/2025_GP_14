# Madar — مدار
> **AI-Powered Indoor Navigation & AR Guidance System**
 
Madar is a 2025 Graduation Project developed at **King Saud University**   
It is an augmented reality mobile application that helps visitors navigate large indoor venues — stadiums, malls, festivals, and expo centers — by combining AR-based turn-by-turn navigation, interactive 3D multi-floor maps, real-time friend tracking, and smart meeting-point suggestions.
 
> Built in alignment with Saudi Arabia's **Vision 2030** to enhance visitor experience at large-scale public events.

## Key Features
- **AR Navigation** — Turn-by-turn directions overlaid on the real world through the device camera, dynamically adapting to the user's position and point of view.
- **AR Exploration** — Scan surroundings to discover nearby facilities, services, and points of interest (POIs).
- **Interactive 3D Map** — Multi-floor venue visualization with a highlighted path from the user's location to their destination.
- **Friend Tracking & Navigation** — Navigate directly toward a tracked friend's live position.
- **Smart Meeting Point** — The app automatically suggests an optimal meeting point based on the shortest paths for all group members.

> **Current prototype venue:** Solitaire Mall, Riyadh. Other venues show basic informational content.

## Technologies 
| Layer | Technology |
|---|---|
| Mobile Framework | Flutter & Dart |
| AR & 3D Visualization | Unity 6, ARCore, Multisense SDK |
| 3D Modeling | Blender |
| Backend & Cloud | Firebase (Firestore, Auth) |
| Design | Figma |
| Project Management | GitHub, Jira |

## Prerequisites
 
Before you begin, make sure you have the following installed and configured:
 
- [Flutter](https://flutter.dev/docs/get-started/install) (latest stable) & Dart — added to your system PATH
- [Android Studio](https://developer.android.com/studio) — for emulator and SDK management
- [Unity 6](https://unity.com/releases/unity-6) — required for AR features
- An Android device or emulator with:
  - **ARCore support**
  - Developer Mode enabled (for physical devices)
 
## Launching Instructions

### 1.Clone the Repository

Open the Command Prompt or Terminal and run the following command:

```bash
git clone https://github.com/rima-15/2025_GP_14
```

### 2.Install Dependencies

In the project directory, run the following command to fetch all necessary packages:

```bash
flutter pub get
```
### 3.Unity Setup (Required for AR Features)

- Step 1 - **Download the full Unity project ZIP** from Google Drive:  
  https://drive.google.com/file/d/1F7o6-_UUwTj8-sqNXyBySFHWlEhCujWp/view?usp=drive_link

- Step 2 - **Extract** the folder and open it in **Unity 6**.

- Step 3 - **Export Unity as a Library**  
  (this will generate the `unityLibrary` folder).

- Step 4 - **Copy the required AAR files** into the Flutter project:
  - From your Unity export, locate:
    - `firebase-app-unity-13.5.0.aar`
    - `firebase-firestore-unity-13.5.0.aar`
  - Paste both files into:  
    `madar_app/android/unityLibrary/libs/`

- Step 5 - **Replace the build.gradle file** inside the Unity Library:
  - Download the updated build.gradle file from Google Drive:  
    https://drive.google.com/file/d/1yX4fkI5i9DeZ0Rm5tnQZWKRdbbOLRp-i/view?usp=sharing
  - Replace the content of:  
    `madar_app/android/unityLibrary/build.gradle`  
    with the file you downloaded.

#### Note: 
We shared the Unity project as a ZIP on Google Drive because Unity files exceed GitHub’s size limits and the unityLibrary output differs across devices. Using a ZIP ensures a consistent, stable version of the AR project that can be opened and exported reliably with Unity 6.
### Run the App

To launch the app on an Android device or emulator, use:

```bash
flutter run
```

### Troubleshooting

- **Flutter and Dart not found:**
Ensure both Flutter and Dart are installed and added to your system path. Verify installation by running:
```bash
flutter --version
dart --version
```

- **`unityLibrary` folder not found**
You must complete the Unity export step (Step 4 above) before running the Flutter app. The `unityLibrary` folder is not committed to the repository — it is generated locally from your Unity export.
 
- **AR features not working**
Ensure your Android device supports ARCore. Check the [supported devices list](https://developers.google.com/ar/devices). ARCore must also be installed on the device (it installs automatically on supported devices via Google Play).

- **Google Drive links inaccessible**
If either Drive link is unavailable, contact the team directly (see below).

---
 
## Team
 
**Supervised by:** Dr. Nouf Alrumaih — King Saud University
 
| Name | Student ID |
|---|---|
| Remas Hezam Al-Subaie | 444200712 |
| Mona Saleh Alnajjar | 444200091 |
| Razan Saeed Aldosari | 444201215 |
| Rima Khalid Alsonbul | 444200524 |
 
---
