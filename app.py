from flask import Flask, request, jsonify
from flask_cors import CORS
import joblib
import pandas as pd
import os

app = Flask(__name__)
CORS(app)

# Load models at startup
try:
    model_fire = joblib.load(os.path.join('models', 'fire_model.pkl'))
    model_risk = joblib.load(os.path.join('models', 'risk_model.pkl'))
    model_area = joblib.load(os.path.join('models', 'area_model.pkl'))
    print("Models loaded successfully.")
except Exception as e:
    print(f"Error loading models: {e}")
    model_fire, model_risk, model_area = None, None, None

@app.route('/predict', methods=['POST'])
def predict():
    try:
        data = request.get_json()
        
        # Extract features
        temp = data.get('temp', 0.0)
        rh = data.get('RH', 0.0)
        wind = data.get('wind', 0.0)
        rain = data.get('rain', 0.0)
        
        # Create a DataFrame to match the training feature names
        features = pd.DataFrame([{
            'temp': temp,
            'RH': rh,
            'wind': wind,
            'rain': rain
        }])
        
        response = {}
        
        # Predict Fire Probability
        if model_fire is not None:
            # predict_proba returns [[prob_no_fire, prob_fire]]
            proba = model_fire.predict_proba(features)[0][1]
            response['fire_probability'] = f"{proba * 100:.1f}%"
        else:
            response['fire_probability'] = "Model not loaded"
            
        # Predict Risk Level
        if model_risk is not None:
            risk = model_risk.predict(features)[0]
            response['risk_level'] = risk
        else:
            response['risk_level'] = "Model not loaded"
            
        # Predict Expected Burned Area
        if model_area is not None:
            area = model_area.predict(features)[0]
            # Avoid returning negative area
            area = max(0, area)
            response['expected_area'] = f"{area:.2f} hectares"
        else:
            response['expected_area'] = "Model not loaded"
            
        return jsonify(response), 200

    except Exception as e:
        return jsonify({'error': str(e)}), 400

if __name__ == '__main__':
    app.run(debug=True, port=5000)
