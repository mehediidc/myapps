# MyExpenses — Flutter Native Android

This project is a native Flutter rebuild of MyExpenses. It does not use Cordova/WebView for the app UI.

## Included
- Offline SQLite database
- Income / Expense entry
- History and editing/deleting
- Today summary
- Category-wise expense percentage
- Dark mode
- Native Android file-picker backup
- Restore from JSON backup
- Share backup
- Native Android print dialog
- PDF ledger generation
- GitHub Actions APK build

## Very easy GitHub method

1. Create a new GitHub repository, for example `MyExpenses`.
2. Open the ZIP and upload the **contents** of this folder to the repository.
3. Commit to `main`.
4. Open **Actions**.
5. Select **Build MyExpenses APK**.
6. Press **Run workflow** (or wait for the push build).
7. Open the green/completed workflow.
8. Scroll to **Artifacts**.
9. Download **MyExpenses-release-apk**.
10. Extract the artifact and install `app-release.apk` on Android.

The workflow automatically creates the standard Flutter Android/Gradle wrapper before building, so you do not need Android Studio just to build the APK.

## Important
The current APK was a Cordova/WebView package. This project rebuilds the core app natively in Flutter rather than trying to patch Cordova printing/storage behavior.

## Local development
With Flutter installed:
```bash
flutter pub get
flutter run
```
