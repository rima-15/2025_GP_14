<p align="center">
  <img src="madar_app/images/Madar2.png" alt="Madar Logo" width="180"/>
</p>
<p align="center">
  <b>AI-Powered Indoor Navigation & AR Guidance System</b>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Graduation%20Project-2025-8B5E34?style=for-the-badge" />
  <img src="https://img.shields.io/badge/University-King%20Saud%20University-6F4B29?style=for-the-badge" />
  <img src="https://img.shields.io/badge/Platform-Android-3D332F?style=for-the-badge" />
</p>

---

## Overview

**Madar** is a 2025 Graduation Project developed at **King Saud University**.

Madar is an augmented reality mobile application that helps visitors navigate large indoor venues such as stadiums, malls, festivals, and expo centers. The application combines **AR-based turn-by-turn navigation**, **interactive 3D multi-floor maps**, **real-time friend tracking**, and **smart meeting-point suggestions** to improve the visitor experience inside complex venues.

> Built in alignment with Saudi Arabia’s **Vision 2030** to enhance visitor experience at large-scale public events.

---

## Key Features

| Feature | Description |
|---|---|
| **AR Navigation** | Provides turn-by-turn directions overlaid on the real world through the device camera, dynamically adapting to the user’s position and point of view. |
| **AR Exploration** | Allows users to scan their surroundings and discover nearby facilities, services, and points of interest. |
| **Interactive 3D Map** | Displays a multi-floor venue map and supports path preview from the user’s location to a selected destination. |
| **Friend Tracking & Navigation** | Enables users to track a friend’s live position and navigate directly toward them. |
| **Smart Meeting Point** | Suggests an optimal meeting point based on the shortest paths for all group members. |

> **Current prototype venue:** Solitaire Mall, Riyadh.  
> Other venues currently provide basic informational content.

---

## Technologies

| Layer | Technology |
|---|---|
| **Mobile Framework** | Flutter & Dart |
| **AR & 3D Visualization** | Unity 6, ARCore, Multiset SDK |
| **3D Modeling** | Blender |
| **External APIs** | Google Maps API |
| **Backend & Cloud** | Firebase Firestore, Firebase Auth |
| **Design** | Figma |
| **Project Management** | GitHub, Jira |

---

## Prerequisites

Before running the project, make sure the following tools are installed and configured:

- [Flutter](https://flutter.dev/docs/get-started/install) latest stable version, with Dart added to your system PATH
- [Android Studio](https://developer.android.com/studio) for emulator and SDK management
- [Unity 6](https://unity.com/releases/unity-6) for AR features
- Android device or emulator with:
  - ARCore support
  - Developer Mode enabled for physical devices

---

## Launching Instructions

### 1. Clone the Repository

Open the Command Prompt or Terminal and run:

```bash
git clone https://github.com/rima-15/2025_GP_14
```

### 2. Install Dependencies

In the project directory, run:

```bash
flutter pub get
```

### 3. Unity Setup for AR Features

The Unity project is required to run the AR features.

#### Step 1 — Download the Unity Project

Download the full Unity project ZIP from Google Drive:

```text
https://drive.google.com/file/d/1NNqKsQVFbJupl3vjhj7zvEinXpqixeg2/view?usp=sharing
```

#### Step 2 — Open the Project in Unity 6

Extract the ZIP file, then open the extracted folder using **Unity 6**.

#### Step 3 — Export Unity as a Library

Export the Unity project as a library. This will generate the following folder:

```text
unityLibrary
```

#### Step 4 — Copy the Required AAR Files

From the Unity export, locate these files:

```text
firebase-app-unity-13.5.0.aar
firebase-firestore-unity-13.5.0.aar
```

Paste both files into:

```text
madar_app/android/unityLibrary/libs/
```

#### Step 5 — Replace the Unity Library build.gradle File

Download the updated `build.gradle` file from Google Drive:

```text
https://drive.google.com/file/d/1yX4fkI5i9DeZ0Rm5tnQZWKRdbbOLRp-i/view?usp=sharing
```

Replace the content of:

```text
madar_app/android/unityLibrary/build.gradle
```

with the downloaded file.

> **Note:**  
> The Unity project is shared as a ZIP on Google Drive because Unity files exceed GitHub’s size limits, and the `unityLibrary` output may differ across devices. Using a ZIP provides a consistent and stable AR project that can be opened and exported reliably with Unity 6.

---

## Run the App

To launch the app on an Android device or emulator, run:

```bash
flutter run
```

---

## Troubleshooting

### Flutter or Dart not found

Make sure Flutter and Dart are installed and added to your system PATH. You can verify the installation using:

```bash
flutter --version
dart --version
```

### unityLibrary folder not found

You must complete the Unity export step before running the Flutter app.

The `unityLibrary` folder is not committed to the repository because it is generated locally from the Unity export.

### AR features not working

Make sure your Android device supports ARCore. You can check the supported devices list here:

```text
https://developers.google.com/ar/devices
```

ARCore must also be installed on the device. On supported devices, it is usually installed automatically through Google Play.

### Google Drive links inaccessible

If either Google Drive link is unavailable, please contact the team directly.

---

## Contact

For support or inquiries, contact us at **madar.support@gmail.com**.

---

## Team

**Supervisor:** Dr. Nouf Alrumaih  
**King Saud University**

**Project Members:**  
Remas Hezam Al-Subaie · Mona Saleh Alnajjar · Razan Saeed Aldosari · Rima Khalid Alsonbul

---

<p align="center">
  <b>Madar — Smarter venues. Better experiences.</b>
</p>
