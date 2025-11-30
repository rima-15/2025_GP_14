# Madar
## Introduction 
*Madar* is our 2025 Graduation Project at King Saud University
The goal of this project is to develop an **AI-powered guidance system for indoor navigation** designed for large, crowded venues such as stadiums, events, malls, and festivals
Madar helps attendees navigate entrances, exits, and facilites, while also enabling them to locate family members or friends easily  
The system aims to improve visitors satisfication and reduce confusion during large gatherings

## Technologies 
- **Mobile Framework :** Flutter & Dart (cross-platform development)  
- **AR Tools :** Unity, ARCore, MultiSet SDK  
- **3D Modeling :** Blender  
- **Backend & Cloud Services :** Firebase 
- **Other Tools :** Figma, GitHub, Jira  

## Launching Instructions

### Clone the Repository

Open the Command Prompt or Terminal and run the following command:

```bash
git clone https://github.com/rima-15/2025_GP_14
```

### Install Prerequisites

* Ensure you have **Flutter**, **Dart**, and **Android Studio** installed.
* Add Flutter and Dart to your system path.
* Have an Android device with **Developer Mode** enabled or an **Android emulator** running via Android Studio.
* Unity 6 (required for AR features)

### Install Dependencies

In the project directory, run the following command to fetch all necessary packages:

```bash
flutter pub get
```
### Unity Setup (Required for AR Features)

- **Download the full Unity project ZIP** from Google Drive:  
  https://drive.google.com/file/d/1F7o6-_UUwTj8-sqNXyBySFHWlEhCujWp/view?usp=drive_link

- **Extract** the folder and open it in **Unity 6**.

- **Export Unity as a Library**  
  (this will generate the `unityLibrary` folder).

- **Copy the required AAR files** into the Flutter project:
  - From your Unity export, locate:
    - `firebase-app-unity-13.5.0.aar`
    - `firebase-firestore-unity-13.5.0.aar`
  - Paste both files into:  
    `madar_app/android/unityLibrary/libs/`

- **Replace the build.gradle file** inside the Unity Library:
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

* **Flutter and Dart not found:** Ensure both Flutter and Dart are installed and added to your system path. Verify installation by running:

```bash
flutter --version
dart --version
```
