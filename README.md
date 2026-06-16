# DeepFire: End-to-End Forest Fire Prediction System 🔥

DeepFire is a comprehensive, full-stack machine learning application designed to predict the probability, risk level, and potential spread area of forest fires. It combines a powerful Python backend with a stunning, highly-interactive Flutter UI.

## 🌟 Key Features

*   **Machine Learning Engine**: Utilizes Scikit-Learn `RandomForestClassifier`, `DecisionTreeClassifier`, and `RandomForestRegressor` trained on historical forest fire datasets.
*   **Live Weather Integration**: Automatically fetches real-time environmental data (Temperature, Humidity, Wind Speed, and Precipitation) for any searched location via the **Open-Meteo API**.
*   **Geospatial Intelligence**: Uses `flutter_map` and the **OpenStreetMap Nominatim API** to provide an interactive 2D map.
*   **Smart Search Autocomplete**: Features a 500ms-debounced search bar that suggests locations as you type.
*   **Fire Spread Visualization**: Dynamically calculates the predicted burn area (in hectares) and draws a scaled danger radius directly onto the map.
*   **Premium Glassmorphism UI**: Built with a sleek, dark-themed, glass-frosted aesthetic designed to feel like a high-end commercial product.

## 🏗️ Architecture

The project is split into two main components:
1.  **Backend (Python & Flask)**: Handles the trained `.pkl` models and exposes a RESTful `/predict` API.
2.  **Frontend (Flutter)**: A cross-platform UI (Web/Android/iOS/Windows) that manages state, user interactions, geospatial mapping, and API orchestration.

### Directory Structure
```text
forest-fire/
│
├── app.py                 # Flask REST API server
├── train_models.py        # ML Training pipeline script
├── test_api.py            # Simple script to test the Flask endpoint
├── models/                # Serialized (.pkl) machine learning models
├── data/                  # Historical datasets (e.g., forestfires.csv)
│
└── forest_fire_app/       # Flutter Frontend Application
    ├── lib/
    │   └── main.dart      # Core Flutter UI, map logic, and API calls
    └── pubspec.yaml       # Flutter dependencies
```

## 🚀 Getting Started

### 1. Run the Backend (Python)

Ensure you have Python installed, then set up the environment:

```bash
# Optional: Create a virtual environment
python -m venv venv
venv\Scripts\activate  # On Windows

# Install dependencies
pip install flask scikit-learn pandas numpy flask-cors joblib

# (Optional) Train the models if they don't exist in /models/
python train_models.py

# Start the Flask API
python app.py
```
*The API will start running on `http://127.0.0.1:5000`.*

### 2. Run the Frontend (Flutter)

Ensure you have the Flutter SDK installed.

```bash
cd forest_fire_app

# Install dependencies
flutter pub get

# Run the app (Edge/Chrome recommended for web deployment)
flutter run -d edge
```

## 🛠️ Tech Stack
*   **Machine Learning**: `scikit-learn`, `pandas`, `numpy`, `joblib`
*   **API Framework**: `Flask`, `flask-cors`
*   **Frontend Framework**: `Flutter`, `Dart`
*   **Mapping UI**: `flutter_map`, `latlong2`
*   **External APIs**: `OpenStreetMap Nominatim` (Geocoding), `Open-Meteo` (Weather)

## 📝 License
This project is open-source and available under the MIT License.
