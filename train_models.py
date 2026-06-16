import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestClassifier, RandomForestRegressor
from sklearn.metrics import accuracy_score, mean_squared_error, r2_score
import joblib
import os

def risk_level(area):
    if area == 0:
        return "Low"
    elif area < 10:
        return "Medium"
    else:
        return "High"

def main():
    # File paths
    data_path = os.path.join('data', 'forestfires.csv')
    
    if not os.path.exists(data_path):
        print(f"Error: Could not find {data_path}")
        return

    # Load dataset
    print("Loading dataset...")
    df = pd.read_csv(data_path)

    # We will use temp, RH, wind, and rain as features as recommended
    features = ['temp', 'RH', 'wind', 'rain']
    X = df[features]
    
    # Target 1: Fire Occurs or Not
    y_fire = (df['area'] > 0).astype(int)
    
    # Target 2: Risk Level
    y_risk = df['area'].apply(risk_level)
    
    # Target 3: Burned Area
    y_area = df['area']

    # Split for Fire Model
    X_train_f, X_test_f, y_train_f, y_test_f = train_test_split(X, y_fire, test_size=0.2, random_state=42)
    
    # Split for Risk Model
    X_train_r, X_test_r, y_train_r, y_test_r = train_test_split(X, y_risk, test_size=0.2, random_state=42)
    
    # Split for Area Model
    X_train_a, X_test_a, y_train_a, y_test_a = train_test_split(X, y_area, test_size=0.2, random_state=42)

    # 1. Train Fire Occurrence Model
    print("Training Fire Occurrence Model...")
    model_fire = RandomForestClassifier(random_state=42)
    model_fire.fit(X_train_f, y_train_f)
    preds_fire = model_fire.predict(X_test_f)
    print(f"Fire Model Accuracy: {accuracy_score(y_test_f, preds_fire):.4f}")

    # 2. Train Risk Level Model
    print("Training Risk Level Model...")
    model_risk = RandomForestClassifier(random_state=42)
    model_risk.fit(X_train_r, y_train_r)
    preds_risk = model_risk.predict(X_test_r)
    print(f"Risk Model Accuracy: {accuracy_score(y_test_r, preds_risk):.4f}")

    # 3. Train Burned Area Model
    print("Training Burned Area Model...")
    model_area = RandomForestRegressor(random_state=42)
    model_area.fit(X_train_a, y_train_a)
    preds_area = model_area.predict(X_test_a)
    print(f"Area Model R2 Score: {r2_score(y_test_a, preds_area):.4f}")
    print(f"Area Model MSE: {mean_squared_error(y_test_a, preds_area):.4f}")

    # Ensure models directory exists
    os.makedirs('models', exist_ok=True)

    # Save models
    print("Saving models...")
    joblib.dump(model_fire, os.path.join('models', 'fire_model.pkl'))
    joblib.dump(model_risk, os.path.join('models', 'risk_model.pkl'))
    joblib.dump(model_area, os.path.join('models', 'area_model.pkl'))
    
    print("All models trained and saved successfully!")

if __name__ == "__main__":
    main()
