import requests
import json

def test_prediction():
    url = "http://127.0.0.1:5000/predict"
    
    # Sample payload representing weather conditions
    payload = {
        "temp": 28.5,
        "RH": 45,
        "wind": 5.4,
        "rain": 0.0
    }
    
    headers = {
        "Content-Type": "application/json"
    }
    
    print(f"Sending POST request to {url}")
    print(f"Payload: {json.dumps(payload, indent=2)}")
    
    try:
        response = requests.post(url, json=payload, headers=headers)
        response.raise_for_status() # Raise an exception for HTTP errors
        
        print("\nResponse Status Code:", response.status_code)
        print("Response JSON:")
        print(json.dumps(response.json(), indent=2))
        
    except requests.exceptions.RequestException as e:
        print(f"\nError connecting to the API: {e}")

if __name__ == "__main__":
    test_prediction()
